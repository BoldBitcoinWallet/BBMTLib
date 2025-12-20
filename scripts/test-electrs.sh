#!/bin/bash

# Test script for Electrum server auto-discovery and usage
# This demonstrates automatic discovery of public Electrum servers

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

NETWORK="${BITCOIN_NETWORK:-testnet3}"

echo "=== Electrum Server Auto-Discovery Test ==="
echo "Network: $NETWORK"
echo "==========================================="
echo ""

# Create test program
cat > /tmp/test_electrs.go << 'EOF'
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

	fmt.Printf("Auto-discovering public Electrum server for %s...\n\n", network)

	// Set network first
	tss.SetNetwork(network)

	// Try auto-discovery
	result, err := tss.AutoDiscoverElectrs(network)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Auto-discovery failed: %v\n", err)
		fmt.Fprintf(os.Stderr, "\nYou can manually configure:\n")
		fmt.Fprintf(os.Stderr, "  tss.UseElectrsServer(\"https://electrum.blockstream.info\")\n")
		os.Exit(1)
	}
	fmt.Printf("✓ %s\n\n", result)

	// Check connection status
	netInfo, _ := tss.GetNetwork()
	fmt.Printf("Network status: %s\n\n", netInfo)

	// Test UTXO query (if address provided)
	testAddress := os.Getenv("TEST_ADDRESS")
	if testAddress != "" {
		fmt.Printf("Testing UTXO query for: %s\n", testAddress)
		utxos, err := tss.FetchUTXOs(testAddress)
		if err != nil {
			fmt.Printf("⚠ Error: %v\n", err)
		} else {
			fmt.Printf("✓ Found %d UTXOs\n", len(utxos))
			for i, utxo := range utxos {
				if i < 3 { // Show first 3
					fmt.Printf("  UTXO %d: %s:%d = %d satoshis\n", i+1, utxo.TxID, utxo.Vout, utxo.Value)
				}
			}
			if len(utxos) > 3 {
				fmt.Printf("  ... and %d more\n", len(utxos)-3)
			}
		}
	} else {
		fmt.Println("Skipping UTXO test (set TEST_ADDRESS env var to test)")
	}

	fmt.Println("\n✓ Electrum server test complete!")
}
EOF

# Run the test
export BITCOIN_NETWORK="$NETWORK"
go run /tmp/test_electrs.go

# Cleanup
rm -f /tmp/test_electrs.go

echo ""
echo "=== Test Complete ==="
echo ""
echo "Note: Auto-discovery tests multiple public servers and uses the first working one."

