#!/bin/bash

# Script to discover Electrum servers by querying known servers for their peer lists
# Uses Electrum's peer discovery protocol

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

NETWORK="${BITCOIN_NETWORK:-mainnet}"

echo "=== Electrum Server Peer Discovery ==="
echo "Network: $NETWORK"
echo "======================================"
echo ""

# Create Go program to query Electrum servers for peer lists
cat > /tmp/discover_electrum.go << 'EOF'
package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"strconv"
	"strings"
	"time"
)

type ElectrumRequest struct {
	ID     int           `json:"id"`
	Method string        `json:"method"`
	Params []interface{} `json:"params"`
}

type ElectrumResponse struct {
	ID     int             `json:"id"`
	Result json.RawMessage `json:"result"`
	Error  *ElectrumError  `json:"error"`
}

type ElectrumError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

type PeerInfo struct {
	IP      string
	Host    string
	TCPPort int
	SSLPort int
	Version string
}

func queryElectrumPeers(serverAddr string) ([]PeerInfo, error) {
	// Parse server address
	host := serverAddr
	port := "50001" // Default TCP port
	useSSL := false

	if strings.HasPrefix(serverAddr, "ssl://") {
		useSSL = true
		serverAddr = strings.TrimPrefix(serverAddr, "ssl://")
		port = "50002" // Default SSL port
	} else if strings.HasPrefix(serverAddr, "tcp://") {
		serverAddr = strings.TrimPrefix(serverAddr, "tcp://")
		port = "50001"
	}

	// Check if port is specified
	if strings.Contains(serverAddr, ":") {
		parts := strings.Split(serverAddr, ":")
		host = parts[0]
		port = parts[1]
	}

	address := fmt.Sprintf("%s:%s", host, port)
	fmt.Printf("Connecting to %s...\n", address)

	// Connect to server
	var conn net.Conn
	var err error
	if useSSL {
		// For SSL, we'd need crypto/tls - for now, try TCP
		conn, err = net.DialTimeout("tcp", address, 5*time.Second)
	} else {
		conn, err = net.DialTimeout("tcp", address, 5*time.Second)
	}
	if err != nil {
		return nil, fmt.Errorf("failed to connect: %w", err)
	}
	defer conn.Close()

	// Set timeout
	conn.SetDeadline(time.Now().Add(10 * time.Second))

	// Send server.peers.subscribe request
	req := ElectrumRequest{
		ID:     1,
		Method: "server.peers.subscribe",
		Params: []interface{}{},
	}

	reqJSON, err := json.Marshal(req)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	// Electrum protocol: send JSON followed by newline
	_, err = conn.Write(append(reqJSON, '\n'))
	if err != nil {
		return nil, fmt.Errorf("failed to send request: %w", err)
	}

	// Read response (Electrum sends JSON lines, read until newline)
	var responseBuf []byte
	buf := make([]byte, 1024)
	for {
		n, err := conn.Read(buf)
		if n > 0 {
			responseBuf = append(responseBuf, buf[:n]...)
			// Check if we have a complete JSON line (ends with newline)
			if bytes.Contains(responseBuf, []byte{'\n'}) {
				break
			}
		}
		if err != nil {
			if len(responseBuf) > 0 {
				break // Use what we have
			}
			return nil, fmt.Errorf("failed to read response: %w", err)
		}
	}

	// Extract first line (Electrum sends one JSON object per line)
	lines := bytes.Split(responseBuf, []byte{'\n'})
	if len(lines) == 0 {
		return nil, fmt.Errorf("no response received")
	}

	// Parse response
	var resp ElectrumResponse
	if err := json.Unmarshal(lines[0], &resp); err != nil {
		return nil, fmt.Errorf("failed to parse response: %w (got: %s)", err, string(lines[0]))
	}

	if resp.Error != nil {
		return nil, fmt.Errorf("server error: %s", resp.Error.Message)
	}

	// Parse peer list
	// Electrum protocol returns: [[ip, hostname, [features]], ...]
	// Features format: ["v1.4", "p10000", "t50001", "s50002"]
	var peerTuples [][]interface{}
	if err := json.Unmarshal(resp.Result, &peerTuples); err != nil {
		return nil, fmt.Errorf("failed to parse peer list: %w", err)
	}

	peers := make([]PeerInfo, 0, len(peerTuples))
	for _, tuple := range peerTuples {
		if len(tuple) < 3 {
			continue
		}

		ip, ok1 := tuple[0].(string)
		hostname, ok2 := tuple[1].(string)
		featuresRaw, ok3 := tuple[2].([]interface{})
		if !ok1 || !ok2 || !ok3 {
			continue
		}

		peer := PeerInfo{
			IP:      ip,
			Host:    hostname,
			TCPPort: 50001, // Default mainnet TCP
			SSLPort: 50002, // Default mainnet SSL
		}

		// Parse features
		for _, feat := range featuresRaw {
			featStr, ok := feat.(string)
			if !ok {
				continue
			}
			if len(featStr) == 0 {
				continue
			}

			prefix := featStr[0]
			value := featStr[1:]

			switch prefix {
			case 'v':
				peer.Version = value
			case 't':
				if value == "" {
					peer.TCPPort = 50001 // Default
				} else {
					if port, err := strconv.Atoi(value); err == nil {
						peer.TCPPort = port
					}
				}
			case 's':
				if value == "" {
					peer.SSLPort = 50002 // Default
				} else {
					if port, err := strconv.Atoi(value); err == nil {
						peer.SSLPort = port
					}
				}
			}
		}

		peers = append(peers, peer)
	}

	return peers, nil
}

func main() {
	network := os.Getenv("BITCOIN_NETWORK")
	if network == "" {
		network = "mainnet"
	}

	// Known Electrum servers to query for peer lists
	var seedServers []string
	if network == "mainnet" {
		seedServers = []string{
			"electrum.blockstream.info:50001",
			"electrum.bitaroo.net:50001",
		}
	} else {
		seedServers = []string{
			"electrum.blockstream.info:60001", // testnet TCP port
		}
	}

	fmt.Printf("Querying %d seed servers for peer lists...\n\n", len(seedServers))

	allPeers := make(map[string]PeerInfo)
	successCount := 0

	for _, server := range seedServers {
		fmt.Printf("--- Querying %s ---\n", server)
		peers, err := queryElectrumPeers(server)
		if err != nil {
			fmt.Printf("✗ Error: %v\n\n", err)
			continue
		}

		successCount++
		fmt.Printf("✓ Found %d peers\n", len(peers))

		// Add to master list (deduplicate by host)
		for _, peer := range peers {
			// Use hostname as key, prefer hostname over IP
			key := peer.Host
			if key == "" {
				key = peer.IP
			}
			// Add or update peer info
			allPeers[key] = peer
		}
		fmt.Println()
	}

	if successCount == 0 {
		fmt.Fprintf(os.Stderr, "Error: Failed to connect to any seed servers\n")
		os.Exit(1)
	}

	// Display discovered servers
	fmt.Println("=== Discovered Electrum Servers ===")
	fmt.Printf("Total unique servers: %d\n\n", len(allPeers))

	// Sort by hostname for display
	peerList := make([]PeerInfo, 0, len(allPeers))
	for _, peer := range allPeers {
		peerList = append(peerList, peer)
	}

	// Simple sort by host
	for i := 0; i < len(peerList)-1; i++ {
		for j := i + 1; j < len(peerList); j++ {
			if peerList[i].Host > peerList[j].Host {
				peerList[i], peerList[j] = peerList[j], peerList[i]
			}
		}
	}

	// Show summary first
	fmt.Printf("Discovered %d unique Electrum servers\n\n", len(peerList))
	fmt.Println("Top 20 servers (showing first 20):")
	fmt.Println()

	// Show first 20 for brevity
	displayCount := 20
	if len(peerList) < displayCount {
		displayCount = len(peerList)
	}

	for i := 0; i < displayCount; i++ {
		peer := peerList[i]
		displayHost := peer.Host
		if displayHost == "" {
			displayHost = peer.IP
		}
		version := peer.Version
		if version == "" {
			version = "unknown"
		}
		fmt.Printf("%3d. %s (v%s)\n", i+1, displayHost, version)
		if peer.TCPPort > 0 {
			fmt.Printf("     TCP: %s:%d\n", displayHost, peer.TCPPort)
		}
		if peer.SSLPort > 0 {
			fmt.Printf("     SSL: ssl://%s:%d\n", displayHost, peer.SSLPort)
		}
		fmt.Println()
	}

	if len(peerList) > displayCount {
		fmt.Printf("... and %d more servers (total: %d)\n\n", len(peerList)-displayCount, len(peerList))
	}

	fmt.Println()
	fmt.Println("=== Usage ===")
	fmt.Println("For HTTP REST API (Electrs format), try servers that support it:")
	fmt.Println("  tss.UseElectrsServer(\"http://host:port\")")
	fmt.Println()
	fmt.Println("Note:")
	fmt.Println("  - TCP ports: 50001 (mainnet), 60001 (testnet)")
	fmt.Println("  - SSL ports: 50002 (mainnet), 60002 (testnet)")
	fmt.Println("  - Not all servers support HTTP REST API")
	fmt.Println("  - Most servers use Electrum protocol (TCP/SSL), not HTTP REST")
	fmt.Println("  - For HTTP REST, use Electrs servers specifically")
	fmt.Println()
	fmt.Println("=== Server Statistics ===")
	versionCount := make(map[string]int)
	for _, peer := range peerList {
		version := peer.Version
		if version == "" {
			version = "unknown"
		}
		versionCount[version]++
	}
	fmt.Println("Version distribution:")
	for version, count := range versionCount {
		fmt.Printf("  v%s: %d servers\n", version, count)
	}
}
EOF

# Run the discovery
export BITCOIN_NETWORK="$NETWORK"
go run /tmp/discover_electrum.go

# Cleanup
rm -f /tmp/discover_electrum.go

echo ""
echo "=== Discovery Complete ==="

