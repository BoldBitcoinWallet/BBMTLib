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
	// data := map[string]interface{}{
	// 	"name": "new test",
	// 	"data": "stuff",
	// }

	// jsonData, err := json.Marshal(data)
	// Client 2's keys (valid pair)
	myPrivateKey := "privKey goes here"
	myPublicKey := "pubKey goes here"

	// Client 1's public keys (for sending messages)
	peerPublicKeys := []string{
		"peer pubkeys go here",
		"peer pubkeys go here",
		"peer pubkeys go here",
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
			//sendMessage(ctx, relay, myPrivateKey, myPublicKey, peerPubKey, string(jsonData))
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

func computeEventChecksum(event nostr.Event) string {
	// Serialize the event to JSON
	eventBytes, err := json.Marshal(event)
	if err != nil {
		log.Printf("Error marshaling event for checksum: %v\n", err)
		return ""
	}
	hash := sha256.Sum256(eventBytes)
	return hex.EncodeToString(hash[:])
}

func listenForMessages(ctx context.Context, relay *nostr.Relay, privateKey, publicKey string) {
	cutoffTime := time.Now().Add(-24 * time.Hour)
	since := nostr.Timestamp(cutoffTime.Unix())

	filters := nostr.Filters{
		{
			Kinds: []int{nostr.KindEncryptedDirectMessage},
			Tags:  nostr.TagMap{"p": []string{publicKey}},
			Since: &since,
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
				log.Printf("Received event checksum: %s\n", checksum)
				continue
			}

			log.Printf("\n[Received message from %s at %s]\n",
				event.PubKey[:8]+"...",
				time.Unix(int64(event.CreatedAt), 0).Format(time.RFC3339))
			log.Printf("Message: %s\n", decryptedMessage)

			// Compute checksum of received event and send it back
			checksum := computeEventChecksum(*event)
			ackMessage := "ACK:" + checksum
			log.Printf("Sending ACK with checksum: %s", checksum)
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

	encryptedContent, err := nip04.Encrypt(message, sharedSecret)
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

	// Sign the event before computing checksum
	event.Sign(privateKey)

	// Compute checksum of the event before sending
	checksum := computeEventChecksum(event)

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
		log.Printf("Event checksum: %s\n", checksum)
	}
}
