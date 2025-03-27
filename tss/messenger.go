package tss

import (
	"encoding/json"
	"fmt"
	"strconv"
	"sync"
)

// NostrMessenger implements the Messenger interface for Nostr communication
type NostrMessenger struct {
	Server     string
	SessionID  string
	SessionKey string
	Mutex      sync.Mutex
	LocalState *LocalState
}

// Send implements the Messenger interface for Nostr communication
func (m *NostrMessenger) Send(from, to, body string) error {
	m.Mutex.Lock()
	defer m.Mutex.Unlock()

	// Compute MD5 hash of the body
	hash, err := md5Hash(body)
	if err != nil {
		Logln("BBMTLog", "Error computing MD5 hash:", err)
	}

	status := getStatus(m.SessionID)

	// Create the message structure
	msg := struct {
		SessionID string   `json:"session_id,omitempty"`
		From      string   `json:"from,omitempty"`
		To        []string `json:"to,omitempty"`
		Body      string   `json:"body,omitempty"`
		SeqNo     string   `json:"sequence_no,omitempty"`
		Hash      string   `json:"hash,omitempty"`
	}{
		SessionID: m.SessionID,
		From:      from,
		To:        []string{to},
		Body:      body,
		SeqNo:     strconv.Itoa(status.SeqNo),
		Hash:      hash,
	}

	// Marshal the message
	msgBytes, err := json.Marshal(msg)
	if err != nil {
		return fmt.Errorf("failed to marshal message: %w", err)
	}

	// TODO: Implement Nostr message sending here
	// This is where you would use the Nostr protocol to send the message
	// using m.LocalState.NostrPrivKey and m.LocalState.PeerNostrPubKeys[to]

	// For now, we'll just log that we're using Nostr
	Logln("BBMTLog", "Sending message via Nostr:", string(msgBytes))

	// Increment the sequence number after successful send
	status.Info = fmt.Sprintf("Sent Message %d", status.SeqNo)
	status.Step++
	status.SeqNo++
	setSeqNo(m.SessionID, status.Info, status.Step, status.SeqNo)

	return nil
}

// NewMessenger creates a new messenger based on the useNostr flag
func NewMessenger(server, sessionID, sessionKey string, useNostr bool, localState *LocalState) Messenger {
	if useNostr {
		return &NostrMessenger{
			Server:     server,
			SessionID:  sessionID,
			SessionKey: sessionKey,
			LocalState: localState,
		}
	}
	return &MessengerImp{
		Server:     server,
		SessionID:  sessionID,
		SessionKey: sessionKey,
	}
}

// NostrJoinSession implements session joining for Nostr
func NostrJoinSession(server, session, key string) error {
	// TODO: Implement Nostr session joining
	// This would involve creating a Nostr event for session joining
	Logln("BBMTLog", "Joining session via Nostr:", session, "with key:", key)
	return nil
}

// NostrAwaitJoiners implements waiting for other participants using Nostr
func NostrAwaitJoiners(parties []string, server, session string) error {
	// TODO: Implement Nostr participant waiting
	// This would involve subscribing to Nostr events for session joining
	Logln("BBMTLog", "Waiting for participants via Nostr:", parties)
	return nil
}

// NostrEndSession implements session ending for Nostr
func NostrEndSession(server, session string) error {
	// TODO: Implement Nostr session ending
	// This would involve creating a Nostr event for session ending
	Logln("BBMTLog", "Ending session via Nostr:", session)
	return nil
}

// NostrFlagPartyComplete implements party completion flagging for Nostr
func NostrFlagPartyComplete(serverURL, session, localPartyID string) error {
	// TODO: Implement Nostr party completion flagging
	// This would involve creating a Nostr event for party completion
	Logln("BBMTLog", "Flagging party complete via Nostr:", localPartyID)
	return nil
}

// NostrDownloadMessage implements message downloading for Nostr
func NostrDownloadMessage(server, session, sessionKey, key string, tssServerImp ServiceImpl, endCh chan struct{}, wg *sync.WaitGroup) {
	defer wg.Done()
	// TODO: Implement Nostr message downloading
	// This would involve subscribing to Nostr events for messages
	Logln("BBMTLog", "Downloading messages via Nostr")
}
