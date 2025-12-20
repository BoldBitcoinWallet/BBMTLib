# Electrs Server Support for Address-Based Queries

Yes! There are Bitcoin indexing servers that support address-based queries. The library now supports **Electrs** servers, which provide address-based UTXO queries via HTTP REST API.

## What is Electrs?

**Electrs** (Electrum Server in Rust) is a high-performance Bitcoin indexer that:
- Indexes the entire Bitcoin blockchain
- Maintains address-to-UTXO mappings
- Provides HTTP REST API for address-based queries
- Much faster than scanning the blockchain

## Supported Services

### Option 1: Automatic Discovery (Easiest!)

The library can automatically discover working public Electrum servers:

```go
// Automatically find and connect to a working server
tss.AutoDiscoverElectrs("mainnet")
```

This tests multiple known public servers and uses the first working one.

### Option 2: Public Electrs Servers (Manual)

Several public Electrs servers are available:

- **Blockstream Electrum**: `https://electrum.blockstream.info`
  - Mainnet: `https://electrum.blockstream.info`
  - Testnet: `https://electrum.blockstream.info/testnet`
  - Most reliable, recommended

- **Other public servers**: 
  - Bitaroo, Ultracloud, Hsmiths, and other community-run servers
  - Auto-discovery tests these automatically

### Option 2: Run Your Own Electrs Server

You can run your own Electrs server locally:
1. Install Electrs (Rust-based, fast indexing)
2. Point it to your Bitcoin Core node
3. Let it index the blockchain
4. Use it for address queries

## Usage

### Manual Configuration

```go
import "github.com/BoldBitcoinWallet/BBMTLib/tss"

// Configure Electrs server
result, err := tss.UseElectrsServer("https://electrum.blockstream.info")
if err != nil {
    log.Fatal(err)
}
fmt.Println(result) // "Electrs server configured: https://electrum.blockstream.info"

// Now FetchUTXOs() will use Electrs automatically
utxos, err := tss.FetchUTXOs("1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa")
if err != nil {
    log.Fatal(err)
}
fmt.Printf("Found %d UTXOs\n", len(utxos))
```

### Auto-Discovery (Recommended)

The library can automatically discover and test multiple public Electrum servers:

```go
// Automatically find a working public Electrum server
result, err := tss.AutoDiscoverElectrs("mainnet")
if err != nil {
    // Fallback to API if no server found
    log.Printf("No Electrum server found, using API: %v", err)
} else {
    fmt.Println(result) // "Electrs server configured: https://electrum.blockstream.info"
}
```

**How it works:**
1. Tests multiple known public Electrum servers in parallel
2. Returns the first working server found
3. Prefers Blockstream servers (most reliable)
4. Fast discovery (tests servers concurrently)

**Servers tested:**
- Mainnet: Blockstream, Bitaroo, and other community servers
- Testnet: Blockstream testnet and other testnet servers

## How It Works

1. **Electrs indexes the blockchain** - Builds a database of address-to-UTXO mappings
2. **HTTP REST API** - Provides `/addrs/:address/utxo` endpoint
3. **Fast queries** - Returns UTXOs in milliseconds (vs. scanning entire blockchain)
4. **Automatic fallback** - Library falls back to mempool.space API if Electrs fails

## Comparison: Electrs vs API vs P2P

| Feature | Electrs | API (mempool.space) | P2P Network |
|---------|---------|---------------------|-------------|
| **Address Queries** | ✅ Yes | ✅ Yes | ❌ No |
| **Transaction Queries** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Setup Required** | Server URL | None | None |
| **Privacy** | Depends on server | Lower (third-party) | Higher (direct) |
| **Speed** | Very Fast | Fast | Variable |
| **Reliability** | Depends on server | High | Variable |

## Electrs API Format

The library uses Electrs REST API format:
```
GET /addrs/:address/utxo
```

Response format:
```json
[
  {
    "txid": "abc123...",
    "vout": 0,
    "value": 0.001,
    "satoshis": 100000,
    "scriptPubKey": "76a914...",
    "height": 800000
  }
]
```

## Example: Complete Setup

```go
package main

import (
    "fmt"
    "log"
    "github.com/BoldBitcoinWallet/BBMTLib/tss"
)

func main() {
    // Set network
    tss.SetNetwork("testnet3")
    
    // Option 1: Use public Electrs server
    _, err := tss.UseElectrsServer("https://electrum.blockstream.info/testnet")
    if err != nil {
        log.Fatal(err)
    }
    
    // Option 2: Or try auto-discovery
    // tss.AutoDiscoverElectrs("testnet3")
    
    // Now address queries use Electrs
    address := "tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx"
    utxos, err := tss.FetchUTXOs(address)
    if err != nil {
        log.Fatal(err)
    }
    
    fmt.Printf("Found %d UTXOs for %s\n", len(utxos), address)
    for _, utxo := range utxos {
        fmt.Printf("  %s:%d = %d satoshis\n", utxo.TxID, utxo.Vout, utxo.Value)
    }
}
```

## Running Your Own Electrs Server

If you want to run your own Electrs server:

1. **Install Electrs**: `cargo install electrs` (requires Rust)
2. **Configure**: Point to your Bitcoin Core RPC
3. **Index**: Let it sync and index the blockchain
4. **Use**: Configure library with `UseElectrsServer("http://localhost:3000")`

Electrs documentation: https://github.com/romanz/electrs

## Benefits of Electrs

✅ **Address-based queries** - Query UTXOs by address directly  
✅ **Fast** - Indexed database, not blockchain scanning  
✅ **Self-hostable** - Run your own server for privacy  
✅ **Open source** - Transparent and auditable  
✅ **Lightweight** - Doesn't require full blockchain storage (uses Bitcoin Core)

## Limitations

- **Requires indexing** - Server must index the blockchain first
- **Server dependency** - Depends on Electrs server availability
- **Public servers** - May have rate limits or privacy concerns

## Best Practices

1. **For privacy**: Run your own Electrs server
2. **For convenience**: Use public servers (Blockstream, etc.)
3. **For reliability**: Have fallback to API mode
4. **For speed**: Use Electrs (fastest for address queries)

## Summary

**Yes, there are Bitcoin nodes that support address-based queries!** Electrs servers provide this functionality. The library now supports:

- ✅ **Electrs servers** - For address-based UTXO queries
- ✅ **P2P network** - For transaction queries by hash
- ✅ **API fallback** - mempool.space as backup

You can use all three together for maximum flexibility and reliability.

