#!/bin/bash

# Test script for Bitcoin P2P network connection
# This demonstrates connecting directly to the Bitcoin network

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

NETWORK="${BITCOIN_NETWORK:-testnet3}"

echo "=== Bitcoin P2P Network Test ==="
echo "Network: $NETWORK"
echo "================================"
echo ""

# Create test program
cat > /tmp/test_p2p.go << 'EOF'
package main

import (
	"fmt"
	"os"
	"github.com/BoldBitcoinWallet/BBMTLib/tss"
)

func main() {
	network := os.Getenv("BITCOIN_NETWORK")
	if network == "" {
		network = "testnet3"
	}

	fmt.Printf("Connecting to Bitcoin %s P2P network...\n\n", network)

	// Connect to P2P network
	result, err := tss.ConnectToBitcoinNetwork(network)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error connecting to P2P network: %v\n", err)
		fmt.Fprintf(os.Stderr, "\nMake sure:\n")
		fmt.Fprintf(os.Stderr, "1. You have internet connectivity\n")
		fmt.Fprintf(os.Stderr, "2. Firewall allows outbound connections to port %s\n", 
			map[string]string{"mainnet": "8333", "testnet3": "18333"}[network])
		os.Exit(1)
	}
	fmt.Printf("✓ %s\n\n", result)

	// Check connection status
	netInfo, _ := tss.GetNetwork()
	fmt.Printf("Network status: %s\n\n", netInfo)

	// Test transaction query (if txid provided)
	testTxID := os.Getenv("TEST_TXID")
	if testTxID != "" {
		fmt.Printf("Testing transaction query for: %s\n", testTxID)
		txOut, isWitness, err := tss.FetchUTXODetails(testTxID, 0)
		if err != nil {
			fmt.Printf("⚠ Error: %v\n", err)
		} else {
			fmt.Printf("✓ Transaction found: %d satoshis, Witness: %v\n", txOut.Value, isWitness)
		}
	} else {
		fmt.Println("Skipping transaction test (set TEST_TXID env var to test)")
	}

	fmt.Println("\n✓ P2P connection test complete!")
	fmt.Println("\nNote: UTXO queries still use API (P2P doesn't support address-based queries)")
}
EOF

# Run the test
export BITCOIN_NETWORK="$NETWORK"
go run /tmp/test_p2p.go

# Cleanup
rm -f /tmp/test_p2p.go

echo ""
echo "=== Test Complete ==="

