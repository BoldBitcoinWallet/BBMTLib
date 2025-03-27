package main

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"math/rand"
	"os"
	"strconv"
	"time"

	"github.com/BoldBitcoinWallet/BBMTLib/tss"
)

func randomSeed(length int) string {
	const characters = "0123456789abcdef"
	result := make([]byte, length)
	r := rand.New(rand.NewSource(time.Now().UnixNano()))
	for i := 0; i < length; i++ {
		result[i] = characters[r.Intn(len(characters))]
	}
	return string(result)
}

func main() {

	mode := os.Args[1]

	if mode == "keypair" {
		kp, _ := tss.GenerateKeyPair()
		fmt.Println(kp)
	}

	if mode == "random" {
		fmt.Println(randomSeed(64))
	}

	if mode == "relay" {
		port := os.Args[2]
		defer tss.StopRelay()
		tss.RunRelay(port)
		select {}
	}

	if mode == "keygen" {

		server := os.Args[2]
		session := os.Args[3]
		chainCode := os.Args[4]
		party := os.Args[5]
		parties := os.Args[6]
		encKey := os.Args[7]
		decKey := os.Args[8]
		sessionKey := ""
		nostrPrivKey := os.Args[9]
		nostrPubKey := os.Args[10]
		ppmFile := party + ".json"
		keyshareFile := party + ".ks"

		// Assign different Nostr keys based on which peer is running
		var peerNostrPubKey, peerNostrPrivKey string
		if party == "peer1" {
			peerNostrPubKey = nostrPubKey
			peerNostrPrivKey = nostrPrivKey
		} else if party == "peer2" {
			peerNostrPubKey = os.Args[11]
			peerNostrPrivKey = os.Args[12]
		} else {
			fmt.Printf("Invalid party: %s\n", party)
			return
		}

		keyshare, err := tss.JoinKeygen(ppmFile, party, parties, encKey, decKey, session, server, chainCode, sessionKey, peerNostrPubKey, peerNostrPrivKey)
		if err != nil {
			fmt.Printf("Go Error: %v\n", err)
		} else {

			var kgR tss.KeygenResponse
			if err := json.Unmarshal([]byte(keyshare), &kgR); err != nil {
				fmt.Printf("Failed to parse keyshare for %s: %v\n", party, err)
			}

			// Create LocalState with Nostr keys
			var localState tss.LocalState
			if err := json.Unmarshal([]byte(keyshare), &localState); err != nil {
				fmt.Printf("Failed to parse keyshare for %s: %v\n", party, err)
			}
			localState.NostrPubKey = peerNostrPubKey
			localState.NostrPrivKey = peerNostrPrivKey

			// Initialize peer nostr public keys map
			localState.PeerNostrPubKeys = make(map[string]string)

			// Store peer nostr public keys
			if party == "peer1" {
				localState.PeerNostrPubKeys["peer2"] = os.Args[11]
			} else if party == "peer2" {
				localState.PeerNostrPubKeys["peer1"] = nostrPubKey
			}

			// Marshal the updated LocalState
			updatedKeyshare, err := json.Marshal(localState)
			if err != nil {
				fmt.Printf("Failed to marshal updated keyshare for %s: %v\n", party, err)
			}

			// save keyshare file - base64 encoded
			fmt.Printf(party + " Keygen Result Saved")
			encodedResult := base64.StdEncoding.EncodeToString(updatedKeyshare)
			if err := os.WriteFile(keyshareFile, []byte(encodedResult), 0644); err != nil {
				fmt.Printf("Failed to save keyshare for %s: %v\n", party, err)
			}

			// print out pubkeys and p2pkh address
			fmt.Printf(party+" Public Key: %s\n", kgR.PubKey)
			xPub := kgR.PubKey
			btcPath := "m/44'/0'/0'/0/0"
			btcPub, err := tss.GetDerivedPubKey(xPub, chainCode, btcPath, false)
			if err != nil {
				fmt.Printf("Failed to generate btc pubkey for %s: %v\n", party, err)
			} else {
				fmt.Printf(party+" BTC Public Key: %s\n", btcPub)
				btcP2Pkh, err := tss.ConvertPubKeyToBTCAddress(btcPub, "testnet3")
				if err != nil {
					fmt.Printf("Failed to generate btc address for %s: %v\n", party, err)
				} else {
					fmt.Printf(party+" address btcP2Pkh: %s\n", btcP2Pkh)
					fmt.Printf(party+" NOSTR PUBLIC KEY: %s\n", peerNostrPubKey)
					fmt.Printf(party+" NOSTR PRIVATE KEY: %s\n", peerNostrPrivKey)
					fmt.Println("--------------------------------")
				}
			}
		}
	}

	if mode == "keysign" {

		server := os.Args[2]
		session := os.Args[3]
		party := os.Args[4]
		parties := os.Args[5]
		encKey := os.Args[6]
		decKey := os.Args[7]
		sessionKey := ""
		keyshare := os.Args[8]
		derivePath := os.Args[9]
		message := os.Args[10]
		useNostr, err := strconv.ParseBool(os.Args[11])
		if err != nil {
			fmt.Printf("Failed to parse useNostr flag: %v\n", err)
			return
		}

		// message hash, base64 encoded
		messageHash, _ := tss.Sha256(message)
		messageHashBytes := []byte(messageHash)
		messageHashBase64 := base64.StdEncoding.EncodeToString(messageHashBytes)

		decodedKeyshare, err := base64.StdEncoding.DecodeString(keyshare)
		if err != nil {
			fmt.Printf("Failed to decode base64 keyshare: %v\n", err)
			return
		}

		// Get the public key and chain code from keyshare
		var localState tss.LocalState
		if err := json.Unmarshal(decodedKeyshare, &localState); err != nil {
			fmt.Printf("Failed to parse keyshare: %v\n", err)
			return
		}

		fmt.Printf(party+" NOSTR PUBLIC KEY: %+v\n", localState.NostrPubKey)
		fmt.Printf(party+" NOSTR PRIVATE KEY: %+v\n", localState.NostrPrivKey)

		// Print all peer nostr public keys
		fmt.Printf("\nPeer Nostr Public Keys for %s:\n", party)
		for peerID, pubKey := range localState.PeerNostrPubKeys {
			fmt.Printf("  %s: %s\n", peerID, pubKey)
		}
		fmt.Println()
		keysign, err := tss.JoinKeysign(server, party, parties, session, sessionKey, encKey, decKey, keyshare, derivePath, messageHashBase64, useNostr)
		time.Sleep(time.Second)

		if err != nil {
			fmt.Printf("Go Error: %v\n", err)
		} else {
			fmt.Printf("\n [%s] Keysign Result %s\n", party, keysign)
		}
	}

	if mode == "mpcsendbtc" {
		server := os.Args[2]
		session := os.Args[3]
		party := os.Args[4]
		parties := os.Args[5]
		encKey := os.Args[6]
		decKey := os.Args[7]
		sessionKey := ""
		keyshare := os.Args[8]
		derivePath := os.Args[9]
		receiverAddress := os.Args[10]
		amountSatoshi := os.Args[11]
		estimatedFee := os.Args[12]
		useNostr, err := strconv.ParseBool(os.Args[13])
		if err != nil {
			fmt.Printf("Failed to parse useNostr flag: %v\n", err)
			return
		}
		//nostrPubKey := os.Args[13]
		//nostrPrivKey := os.Args[14]
		//peerNostrPubKey := os.Args[15]

		// Decode base64 keyshare
		decodedKeyshare, err := base64.StdEncoding.DecodeString(keyshare)
		if err != nil {
			fmt.Printf("Failed to decode base64 keyshare: %v\n", err)
			return
		}

		// Get the public key and chain code from keyshare
		var localState tss.LocalState
		if err := json.Unmarshal(decodedKeyshare, &localState); err != nil {
			fmt.Printf("Failed to parse keyshare: %v\n", err)
			return
		}

		// Get the derived public key using chain code from keyshare
		btcPub, err := tss.GetDerivedPubKey(localState.PubKey, localState.ChainCodeHex, derivePath, false)
		if err != nil {
			fmt.Printf("Failed to get derived public key: %v\n", err)
			return
		}

		// Get the sender address
		senderAddress, err := tss.ConvertPubKeyToBTCAddress(btcPub, "testnet3")
		if err != nil {
			fmt.Printf("Failed to get sender address: %v\n", err)
			return
		}

		amount, err := strconv.ParseInt(amountSatoshi, 10, 64)
		if err != nil {
			fmt.Printf("Failed to parse amount: %v\n", err)
			return
		}
		fee, err := strconv.ParseInt(estimatedFee, 10, 64)
		if err != nil {
			fmt.Printf("Failed to parse fee: %v\n", err)
			return
		}

		result, err := tss.MpcSendBTC(
			server, party, parties, session, sessionKey, encKey, decKey, keyshare, derivePath,
			btcPub, senderAddress, receiverAddress, amount, fee, useNostr,
		)
		time.Sleep(time.Second)

		if err != nil {
			fmt.Printf("Go Error: %v\n", err)
		} else {
			fmt.Printf("\n [%s] MPCSendBTC Result %s\n", party, result)
		}
	}
}
