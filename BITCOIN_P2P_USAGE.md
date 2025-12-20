# Bitcoin P2P Network Integration

This library now supports connecting directly to the Bitcoin peer-to-peer (P2P) network to query transaction details and broadcast transactions, without requiring a local Bitcoin Core node or RPC setup.

## Features

- **Direct P2P Connection** - Connects to Bitcoin network peers automatically
- **Transaction Querying** - Fetches transaction details directly from the network
- **Transaction Broadcasting** - Broadcasts transactions to multiple peers
- **Automatic Peer Discovery** - Uses DNS seeds to find Bitcoin network peers
- **Fallback Support** - Automatically falls back to API if P2P times out

## Usage

### Connecting to Bitcoin Network

To connect directly to the Bitcoin P2P network:

```go
import "github.com/BoldBitcoinWallet/BBMTLib/tss"

// Connect to testnet
result, err := tss.ConnectToBitcoinNetwork("testnet3")
if err != nil {
    log.Fatal(err)
}
fmt.Println(result) // "connected to 3 Bitcoin P2P peers"

// Or connect to mainnet
result, err = tss.ConnectToBitcoinNetwork("mainnet")
```

### Querying Transactions

Once connected, transaction queries automatically use P2P:

```go
// Fetch transaction details (automatically uses P2P if connected)
txOut, isWitness, err := tss.FetchUTXODetails(txID, vout)
if err != nil {
    log.Fatal(err)
}
```

The function will:
1. Check cache first (for performance)
2. Query P2P network peers using `getdata` message
3. Automatically fall back to API if P2P times out (30 seconds)

### Broadcasting Transactions

Broadcast transactions directly to the network:

```go
// Broadcast transaction (automatically uses P2P if connected)
txid, err := tss.PostTx(rawTxHex)
if err != nil {
    log.Fatal(err)
}
fmt.Printf("Transaction broadcasted: %s\n", txid)
```

The transaction is broadcast to all connected peers simultaneously.

### Checking Connection Status

```go
netInfo, _ := tss.GetNetwork()
fmt.Println(netInfo) // "testnet3@p2p" if P2P is active
```

## How It Works

### Peer Discovery

1. **DNS Seeds**: The library queries Bitcoin DNS seeds to discover active peers
   - Mainnet: `seed.bitcoin.sipa.be`, `dnsseed.bluematt.me`, etc.
   - Testnet: `testnet-seed.bitcoin.jonasschnelli.ch`, etc.

2. **Connection**: Connects to up to 3 peers simultaneously for redundancy

3. **Handshake**: Performs Bitcoin protocol handshake (version/verack)

### Transaction Querying

1. **Request**: Sends `getdata` message with transaction hash
2. **Response**: Receives `tx` message with full transaction
3. **Caching**: Caches transactions for faster subsequent queries
4. **Timeout**: Falls back to API after 30 seconds if no response

### Transaction Broadcasting

1. **Serialization**: Deserializes raw transaction hex
2. **Broadcast**: Sends transaction to all connected peers
3. **Propagation**: Peers propagate transaction to the network

## Limitations

### UTXO Queries

**Note**: The Bitcoin P2P protocol doesn't support querying UTXOs by address directly. However, you can use **Electrs servers** for address-based queries!

**Options for UTXO queries:**
1. **Electrs servers** - Use `UseElectrsServer()` to connect to an Electrs indexer (supports address queries)
2. **API (mempool.space)** - Default fallback, always works
3. **P2P** - Not supported (P2P only supports transaction queries by hash)

See `ELECTRS_ADDRESS_QUERIES.md` for details on using Electrs servers.

### What Works via P2P

✅ **Transaction Details** (`FetchUTXODetails`) - Query by transaction hash  
✅ **Transaction Broadcasting** (`PostTx`) - Broadcast to network  
❌ **UTXO Queries** (`FetchUTXOs`) - Still uses API (address-based queries)  
❌ **Fee Estimation** (`RecommendedFees`) - Still uses API (requires mempool analysis)

## Example

```go
package main

import (
    "fmt"
    "log"
    "github.com/BoldBitcoinWallet/BBMTLib/tss"
)

func main() {
    // Connect to Bitcoin testnet P2P network
    result, err := tss.ConnectToBitcoinNetwork("testnet3")
    if err != nil {
        log.Fatal("Failed to connect:", err)
    }
    fmt.Printf("✓ %s\n", result)

    // Check connection status
    netInfo, _ := tss.GetNetwork()
    fmt.Printf("Network: %s\n", netInfo)

    // Query a transaction (uses P2P automatically)
    txID := "your_transaction_hash_here"
    txOut, isWitness, err := tss.FetchUTXODetails(txID, 0)
    if err != nil {
        log.Fatal("Failed to fetch:", err)
    }
    fmt.Printf("Transaction output: %d satoshis, Witness: %v\n", txOut.Value, isWitness)

    // Broadcast a transaction (uses P2P automatically)
    rawTx := "your_raw_transaction_hex_here"
    broadcastTxID, err := tss.PostTx(rawTx)
    if err != nil {
        log.Fatal("Failed to broadcast:", err)
    }
    fmt.Printf("Broadcasted: %s\n", broadcastTxID)
}
```

## Network Ports

- **Mainnet**: Port `8333`
- **Testnet**: Port `18333`

## Performance

- **Caching**: Transactions are cached after first query
- **Parallel Queries**: Can query multiple peers simultaneously
- **Timeout**: 30-second timeout with automatic API fallback
- **Connection Pool**: Maintains up to 3 peer connections

## Security Considerations

- **No Authentication**: P2P connections don't require authentication
- **Public Network**: You're connecting to public Bitcoin network peers
- **Transaction Privacy**: Broadcasting reveals your transaction to peers
- **DoS Protection**: Limited to 3 peers to prevent resource exhaustion

## Troubleshooting

### Connection Failures

If connection fails:
1. Check internet connectivity
2. Verify firewall allows outbound connections to ports 8333/18333
3. Try again (peer availability varies)

### Timeout Issues

If queries timeout:
- The library automatically falls back to API mode
- This is normal if peers are slow or unavailable
- Consider using API mode directly for more reliable queries

### UTXO Queries

Remember: UTXO queries still use API because P2P doesn't support address-based queries.

## Comparison: P2P vs API

| Feature | P2P Network | API (mempool.space) |
|---------|-------------|---------------------|
| **Setup** | Automatic | None needed |
| **Transaction Query** | ✅ Direct from network | ✅ Via API |
| **UTXO Query** | ❌ Not supported | ✅ Supported |
| **Broadcasting** | ✅ Direct to network | ✅ Via API |
| **Fee Estimation** | ❌ Not supported | ✅ Supported |
| **Privacy** | Lower (connects to peers) | Higher (HTTPS) |
| **Reliability** | Depends on peers | High (managed service) |
| **Speed** | Variable | Consistent |

## Best Practices

1. **Use P2P for**: Transaction queries when you have the txid
2. **Use API for**: UTXO queries, fee estimation, and when you need reliability
3. **Hybrid Approach**: Let the library automatically choose (P2P with API fallback)

