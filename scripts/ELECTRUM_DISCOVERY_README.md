# Electrum Server Discovery Script

The `discover-electrum-servers.sh` script automatically discovers public Electrum servers by using Electrum's peer discovery protocol.

## How It Works

1. **Connects to seed servers** - Queries known Electrum servers (Blockstream, Bitaroo)
2. **Requests peer lists** - Uses `server.peers.subscribe` method to get peer lists
3. **Discovers recursively** - Each server provides a list of other servers
4. **Displays results** - Shows all discovered servers with their connection details

## Usage

```bash
# Discover mainnet servers
./scripts/discover-electrum-servers.sh

# Discover testnet servers
BITCOIN_NETWORK=testnet3 ./scripts/discover-electrum-servers.sh
```

## Example Output

```
=== Electrum Server Peer Discovery ===
Network: mainnet
======================================

Querying 2 seed servers for peer lists...

--- Querying electrum.blockstream.info:50001 ---
Connecting to electrum.blockstream.info:50001...
✓ Found 26 peers

--- Querying electrum.bitaroo.net:50001 ---
Connecting to electrum.bitaroo.net:50001...
✓ Found 199 peers

=== Discovered Electrum Servers ===
Total unique servers: 225

  1. electrum.blockstream.info (v1.4)
     TCP: electrum.blockstream.info:50001
     SSL: ssl://electrum.blockstream.info:50002
...
```

## What It Discovers

- **Server hostnames/IPs** - All discovered Electrum servers
- **Protocol versions** - Server protocol versions (v1.4, v1.5, v1.6, etc.)
- **Port information** - TCP and SSL ports for each server
- **Connection details** - How to connect to each server

## Important Notes

⚠️ **Not all servers support HTTP REST API**

Most Electrum servers use the **Electrum protocol** (TCP/SSL), not HTTP REST API. Only **Electrs** servers support HTTP REST API for address-based queries.

- **Electrum protocol servers**: Use TCP (port 50001) or SSL (port 50002)
- **Electrs HTTP REST servers**: Use HTTP (typically port 3000 or similar)

The discovered list includes both types, but you'll need to test which ones support HTTP REST API if you want to use them with `UseElectrsServer()`.

## Using Discovered Servers

### For Electrum Protocol (not HTTP REST)

If you want to use the Electrum protocol directly, you'd need an Electrum protocol client library. The current library supports HTTP REST API (Electrs format).

### For HTTP REST API (Electrs)

Test discovered servers to see if they support HTTP REST:

```go
// Try a discovered server (if it supports HTTP REST)
tss.UseElectrsServer("http://some-discovered-server:3000")
```

Most discovered servers won't support HTTP REST - they use the Electrum protocol instead.

## Seed Servers Used

The script queries these seed servers:
- **Blockstream**: `electrum.blockstream.info:50001`
- **Bitaroo**: `electrum.bitaroo.net:50001`

These servers maintain peer lists and share them via the `server.peers.subscribe` method.

## Protocol Details

The Electrum protocol uses:
- **JSON-RPC** over TCP or SSL
- **Line-delimited JSON** (one JSON object per line)
- **Method**: `server.peers.subscribe` (returns list of peer servers)
- **Response format**: `[[ip, hostname, [features]], ...]`

## Statistics

The script shows:
- Total unique servers discovered
- Version distribution (how many servers run each version)
- Connection details for each server

## Limitations

- **Protocol mismatch**: Most discovered servers use Electrum protocol, not HTTP REST
- **Availability**: Not all discovered servers may be online
- **Rate limiting**: Some servers may rate-limit connections
- **Privacy**: Connecting reveals your IP to the servers

## Next Steps

To use discovered servers with the library:
1. Test which servers support HTTP REST API
2. Or implement Electrum protocol client support
3. Or use the auto-discovery function which tests known HTTP REST servers

