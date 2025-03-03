package tss

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"strings"
	"time"

	"github.com/nbd-wtf/go-nostr"
	"github.com/nbd-wtf/go-nostr/nip04"
)

func main() {

	data := map[string]interface{}{
		"name": "some data",
		"data": "things",
	}

	jsonData, err := json.Marshal(data)

	myPrivateKey := "425f99e808b14584b335c9e66fb6054efd3ce5e712a396e7d8571c575fa61bb6"
	myPublicKey := "d82ef5e9d7bb344f0eb5ee477ec297ad9e9cffb383cf9944095deff4985d7276"

	peerPublicKeys := []string{
		"c4ecad49a85355933a86514d0d441477a224e6fdb59cb222156bc36aff259e59",
		"9d2c70b6e4389a96b3a3f4b53a3d488b9b5d9203049e916489b3b4a0a468b20a",
		"d82ef5e9d7bb344f0eb5ee477ec297ad9e9cffb383cf9944095deff4985d7276",
	}

	for _, peerPubKey := range peerPublicKeys {
		if !nostr.IsValidPublicKey(peerPubKey) {
			log.Printf("Invalid peer public key: %s\n", peerPubKey)
			return
		}
	}

	if err := validateKeys(myPrivateKey, myPublicKey); err != nil {
		log.Printf("Key validation error: %v\n", err)
		return
	}

	log.Printf("My Public Key: %s\n", myPublicKey)
	fmt.Printf("Starting message listener and sending initial test message...")

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	relay, err := nostr.RelayConnect(ctx, "ws://bbw-nostr.xyz")
	if err != nil {
		log.Printf("Error connecting to relay: %v\n", err)
		return
	}
	defer relay.Close()

	go listenForMessages(ctx, relay, myPrivateKey, myPublicKey)

	for _, peerPubKey := range peerPublicKeys {
		if peerPubKey != myPublicKey {

			sendMessage(ctx, relay, myPrivateKey, myPublicKey, peerPubKey, string(jsonData))
		}
	}

	select {}
}

func validateKeys(privateKey, publicKey string) error {
	if len(privateKey) != 64 || !nostr.IsValidPublicKey(publicKey) {
		return fmt.Errorf("invalid key format")
	}
	derivedPubKey, err := nostr.GetPublicKey(privateKey)
	if err != nil {
		return fmt.Errorf("error deriving public key: %v", err)
	}
	if derivedPubKey != publicKey {
		return fmt.Errorf("private key does not match public key")
	}
	return nil
}

func computeChecksum(message string) string {
	hash := sha256.Sum256([]byte(message))
	return hex.EncodeToString(hash[:])
}

func listenForMessages(ctx context.Context, relay *nostr.Relay, privateKey, publicKey string) {

	cutoffTime := time.Now().Add(-1 * time.Hour)
	since := nostr.Timestamp(cutoffTime.Unix())

	filters := nostr.Filters{
		{
			Kinds: []int{nostr.KindEncryptedDirectMessage},
			Tags:  nostr.TagMap{"p": []string{publicKey}},
			Since: &since, // Only get events after this time
		},
	}

	sub, err := relay.Subscribe(ctx, filters)
	if err != nil {
		log.Printf("Error subscribing to events: %v\n", err)
		return
	}

	for {
		select {
		case event := <-sub.Events:
			sharedSecret, err := nip04.ComputeSharedSecret(event.PubKey, privateKey)
			if err != nil {
				log.Printf("Error computing shared secret: %v\n", err)
				continue
			}

			decryptedMessage, err := nip04.Decrypt(event.Content, sharedSecret)
			if err != nil {
				log.Printf("Error decrypting message: %v\n", err)
				continue
			}

			// Check if this is an acknowledgment message
			if strings.HasPrefix(decryptedMessage, "ACK:") {
				checksum := strings.TrimPrefix(decryptedMessage, "ACK:")
				log.Printf("\n[Received ACK from %s at %s]\n",
					event.PubKey[:8]+"...",
					time.Unix(int64(event.CreatedAt), 0).Format(time.RFC3339))
				log.Printf("Checksum: %s\n", checksum)
				continue
			}

			log.Printf("\n[Received message from %s at %s]\n",
				event.PubKey[:8]+"...",
				time.Unix(int64(event.CreatedAt), 0).Format(time.RFC3339))
			log.Printf("Message: %s\n", decryptedMessage)

			// Send acknowledgment with checksum
			checksum := computeChecksum(decryptedMessage)
			ackMessage := "ACK:" + checksum
			log.Printf(ackMessage)
			go sendMessage(ctx, relay, privateKey, publicKey, event.PubKey, ackMessage)

		case <-ctx.Done():
			return

		case <-sub.EndOfStoredEvents:
			fmt.Printf("Received all stored events, continuing to listen...\n")
		}
	}
}

func sendMessage(ctx context.Context, relay *nostr.Relay, privateKey, publicKey, recipientPubKey, message string) {
	sharedSecret, err := nip04.ComputeSharedSecret(recipientPubKey, privateKey)
	if err != nil {
		log.Printf("Error computing shared secret: %v\n", err)
		return
	}

	finalMessage := message

	encryptedContent, err := nip04.Encrypt(finalMessage, sharedSecret)
	if err != nil {
		log.Printf("Error encrypting message: %v\n", err)
		return
	}

	event := nostr.Event{
		PubKey:    publicKey,
		CreatedAt: nostr.Now(),
		Kind:      nostr.KindEncryptedDirectMessage,
		Tags:      nostr.Tags{{"p", recipientPubKey}},
		Content:   encryptedContent,
	}

	event.Sign(privateKey)

	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()

	err = relay.Publish(ctx, event)
	if err != nil {
		log.Printf("Error publishing event: %v\n", err)
		return
	}

	if strings.HasPrefix(message, "ACK:") {
		log.Printf("ACK sent successfully to %s...\n", recipientPubKey[:8])
	} else {
		log.Printf("Message sent successfully to %s...\n", recipientPubKey[:8])
	}
}
