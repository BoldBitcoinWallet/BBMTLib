#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

RELAYS_DEFAULT="wss://bbw-nostr.xyz"
RELAYS="${RELAYS:-$RELAYS_DEFAULT}"
TIMEOUT="${TIMEOUT:-90}"
OUTPUT_DIR="${OUTPUT_DIR:-./nostr-keygen-output}"
mkdir -p "$OUTPUT_DIR"

random_hex() {
	go run ./scripts/main.go random
}

generate_keypair() {
	go run ./scripts/main.go nostr-keypair
}

# Prompt user for number of parties
echo "=== Nostr Keygen - Multi-Party Setup ==="
read -p "Enter the number of parties for the session: " NUM_PARTIES

# Validate input
if ! [[ "$NUM_PARTIES" =~ ^[0-9]+$ ]] || [ "$NUM_PARTIES" -lt 2 ]; then
	echo "Error: Number of parties must be an integer >= 2"
	exit 1
fi

# Prompt user for verbose mode
echo ""
read -p "Display output in terminal (verbose mode)? [Y/n]: " VERBOSE_INPUT
VERBOSE_INPUT="${VERBOSE_INPUT:-Y}"
if [[ "$VERBOSE_INPUT" =~ ^[Yy]$ ]] || [ -z "$VERBOSE_INPUT" ]; then
	VERBOSE_MODE=1
	echo "Verbose mode: ON"
else
	VERBOSE_MODE=0
	echo "Verbose mode: OFF (output will be logged to files only)"
fi

# Calculate recommended timeout based on number of parties
# Base timeout: 60 seconds, plus 20 seconds per party
# More parties = more messages = more time needed
RECOMMENDED_TIMEOUT=$((60 + (NUM_PARTIES * 20)))
if [ -n "${TIMEOUT:-}" ] && [ "$TIMEOUT" != "90" ]; then
	# Use environment variable if set and not default
	USER_TIMEOUT="$TIMEOUT"
else
	USER_TIMEOUT="$RECOMMENDED_TIMEOUT"
fi

# Prompt user for timeout
echo ""
read -p "Timeout in seconds (recommended: ${RECOMMENDED_TIMEOUT}s for $NUM_PARTIES parties) [${USER_TIMEOUT}]: " TIMEOUT_INPUT
if [ -n "$TIMEOUT_INPUT" ]; then
	if ! [[ "$TIMEOUT_INPUT" =~ ^[0-9]+$ ]] || [ "$TIMEOUT_INPUT" -lt 30 ]; then
		echo "Warning: Timeout must be an integer >= 30. Using recommended value: ${RECOMMENDED_TIMEOUT}s"
		TIMEOUT="$RECOMMENDED_TIMEOUT"
	else
		TIMEOUT="$TIMEOUT_INPUT"
	fi
else
	TIMEOUT="$USER_TIMEOUT"
fi
echo "Using timeout: ${TIMEOUT}s"

# Check for existing keyshare files
echo ""
EXISTING_FILES=()
for ((i=1; i<=NUM_PARTIES; i++)); do
	KEYSHARE_FILE="$OUTPUT_DIR/party$i-keyshare.json"
	if [ -f "$KEYSHARE_FILE" ]; then
		EXISTING_FILES+=("$KEYSHARE_FILE")
	fi
done

if [ ${#EXISTING_FILES[@]} -gt 0 ]; then
	echo "⚠️  WARNING: Existing keyshare files found in $OUTPUT_DIR:"
	for file in "${EXISTING_FILES[@]}"; do
		echo "  - $file"
	done
	echo ""
	read -p "Do you want to overwrite these existing keyshare files? [y/N]: " OVERWRITE_INPUT
	if ! [[ "$OVERWRITE_INPUT" =~ ^[Yy]$ ]]; then
		echo "Aborted. Existing keyshare files will not be overwritten."
		exit 0
	fi
	echo "Proceeding to overwrite existing keyshare files..."
fi

echo ""
echo "Generating keypairs for $NUM_PARTIES parties..."

# Generate keypairs for all parties
declare -a NSEC_ARRAY
declare -a NPUB_ARRAY

for ((i=1; i<=NUM_PARTIES; i++)); do
	read -r NSEC NPUB <<<"$(generate_keypair | awk -F',' '{print $1" "$2}')"
	NSEC_ARRAY[$i]="$NSEC"
	NPUB_ARRAY[$i]="$NPUB"
done

SESSION_ID="$(random_hex)"
SESSION_KEY="$(random_hex)"
CHAINCODE="$(random_hex)"

echo ""
echo "=== Generated Parameters ==="
echo "Relays      : $RELAYS"
echo "Session ID  : $SESSION_ID"
echo "Session Key : $SESSION_KEY"
echo "Chaincode   : $CHAINCODE"
echo ""

# Display all party keypairs
for ((i=1; i<=NUM_PARTIES; i++)); do
	echo "Party $i npub: ${NPUB_ARRAY[$i]}"
	echo "Party $i nsec: ${NSEC_ARRAY[$i]}"
	echo ""
done
echo "============================"

run_party() {
	local party_num="$1"
	local nsec="$2"
	local npub="$3"
	local peers="$4"
	local output="$5"
	local ppm="$6"

	NOSTR_NSEC="$nsec" go run ./tss/cmd/nostr-keygen \
		-relays "$RELAYS" \
		-ppm "$OUTPUT_DIR/ppm-$ppm.json" \
		-npub "$npub" \
		-peers "$peers" \
		-session "$SESSION_ID" \
		-session-key "$SESSION_KEY" \
		-chaincode "$CHAINCODE" \
		-timeout "$TIMEOUT" \
		-output "$output"
}

# Build peer lists for each party (all other parties)
declare -a PEER_LISTS
for ((i=1; i<=NUM_PARTIES; i++)); do
	PEERS=""
	for ((j=1; j<=NUM_PARTIES; j++)); do
		if [ "$i" -ne "$j" ]; then
			if [ -n "$PEERS" ]; then
				PEERS="$PEERS,${NPUB_ARRAY[$j]}"
			else
				PEERS="${NPUB_ARRAY[$j]}"
			fi
		fi
	done
	PEER_LISTS[$i]="$PEERS"
done

# Initialize arrays for PIDs and outputs
declare -a PIDS
declare -a OUTPUTS

echo ""
echo "Starting Nostr keygen for all $NUM_PARTIES parties in parallel..."

# Record start time
START_TIME=$(date +%s)

# Run all parties in background
for ((i=1; i<=NUM_PARTIES; i++)); do
	OUTPUT_FILE="$OUTPUT_DIR/party$i-keyshare.json"
	OUTPUTS[$i]="$OUTPUT_FILE"
	LOG_FILE="$OUTPUT_DIR/party$i.log"
	
	if [ $VERBOSE_MODE -eq 1 ]; then
		# Verbose mode: display in terminal and log to file
		echo "Party $i output (also logged to: $LOG_FILE):"
		run_party "$i" "${NSEC_ARRAY[$i]}" "${NPUB_ARRAY[$i]}" "${PEER_LISTS[$i]}" "$OUTPUT_FILE" "$i" 2>&1 | tee "$LOG_FILE" &
	else
		# Non-verbose mode: log to file only
		echo "$(pwd)/$LOG_FILE"
		run_party "$i" "${NSEC_ARRAY[$i]}" "${NPUB_ARRAY[$i]}" "${PEER_LISTS[$i]}" "$OUTPUT_FILE" "$i" > "$LOG_FILE" 2>&1 &
	fi
	PIDS[$i]=$!
	echo "Party $i PID: ${PIDS[$i]}"
done

# Build cleanup command
CLEANUP_CMD="kill"
for ((i=1; i<=NUM_PARTIES; i++)); do
	CLEANUP_CMD="$CLEANUP_CMD ${PIDS[$i]}"
done
CLEANUP_CMD="$CLEANUP_CMD 2>/dev/null; exit"

# Handle cleanup on exit
trap "echo 'Stopping processes...'; $CLEANUP_CMD" SIGINT SIGTERM

echo ""
echo "Logs:"
for ((i=1; i<=NUM_PARTIES; i++)); do
	echo "  $OUTPUT_DIR/party$i.log"
done
echo ""
echo "Waiting for keygen to complete..."

# Wait for all processes and collect exit codes
declare -a EXIT_CODES
ALL_SUCCESS=0

for ((i=1; i<=NUM_PARTIES; i++)); do
	wait ${PIDS[$i]}
	EXIT_CODES[$i]=$?
	if [ ${EXIT_CODES[$i]} -ne 0 ]; then
		ALL_SUCCESS=1
	fi
done

# Calculate elapsed time
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
MINUTES=$((ELAPSED / 60))
SECONDS_REMAINING=$((ELAPSED % 60))

echo ""
if [ $ALL_SUCCESS -eq 0 ]; then
	echo "✓ Keygen completed successfully!"
	echo ""
	
	# Extract and display public keys and BTC addresses
	ALL_OUTPUTS_EXIST=0
	for ((i=1; i<=NUM_PARTIES; i++)); do
		if [ -f "${OUTPUTS[$i]}" ]; then
			go run ./scripts/main.go show-keyshare "${OUTPUTS[$i]}" "party$i" 2>/dev/null
		else
			ALL_OUTPUTS_EXIST=1
		fi
	done
	
	if [ $ALL_OUTPUTS_EXIST -eq 0 ]; then
		echo ""
		echo "Outputs saved to:"
		for ((i=1; i<=NUM_PARTIES; i++)); do
			echo "  ${OUTPUTS[$i]}"
		done
	fi
	
	# Collect statistics from log files
	echo ""
	echo "=== Statistics ==="
	echo "Total time: ${ELAPSED} seconds"
	echo ""
	
	# Initialize totals
	TOTAL_BYTES=0
	TOTAL_EVENTS=0
	declare -a EVENTS_PER_PARTY
	declare -a BYTES_PER_PARTY
	
	# Parse each log file
	for ((i=1; i<=NUM_PARTIES; i++)); do
		LOG_FILE="$OUTPUT_DIR/party$i.log"
		PARTY_BYTES=0
		
		if [ -f "$LOG_FILE" ]; then
			# Count events sent (Client.PublishWrap lines with "event kind=" - these are the actual events)
			EVENT_COUNT=$(grep -c "Client.PublishWrap - event kind=" "$LOG_FILE" 2>/dev/null || echo "0")
			EVENTS_PER_PARTY[$i]=$EVENT_COUNT
			TOTAL_EVENTS=$((TOTAL_EVENTS + EVENT_COUNT))
			
			# Extract bytes sent from "Messenger sending message" lines
			# Format: "BBMTLog: Messenger sending message from ... to ... (237964 bytes)"
			while IFS= read -r line; do
				if [[ $line =~ \(([0-9]+)\ bytes\) ]]; then
					BYTES="${BASH_REMATCH[1]}"
					PARTY_BYTES=$((PARTY_BYTES + BYTES))
					TOTAL_BYTES=$((TOTAL_BYTES + BYTES))
				fi
			done < <(grep "Messenger sending message" "$LOG_FILE" 2>/dev/null || true)
		fi
		
		BYTES_PER_PARTY[$i]=$PARTY_BYTES
	done
	
	# Convert bytes to KB (divide by 1024)
	TOTAL_KB=$((TOTAL_BYTES / 1024))
	
	# Display per-party statistics
	echo "Nostr events sent per party:"
	for ((i=1; i<=NUM_PARTIES; i++)); do
		PARTY_KB=$((BYTES_PER_PARTY[$i] / 1024))
		echo "  Party $i: ${EVENTS_PER_PARTY[$i]} nostr events, ${PARTY_KB} KB"
	done
	echo ""
	echo "Total nostr events sent: $TOTAL_EVENTS"
	echo "Total data transmitted: ${TOTAL_KB} KB (${TOTAL_BYTES} bytes)"
	echo "============================"
else
	echo "✗ Keygen failed!"
	echo "Time elapsed: ${ELAPSED} seconds"
	echo ""
	echo "Exit codes:"
	for ((i=1; i<=NUM_PARTIES; i++)); do
		echo "  Party $i: ${EXIT_CODES[$i]}"
	done
	echo ""
	echo "Check logs:"
	for ((i=1; i<=NUM_PARTIES; i++)); do
		echo "  $OUTPUT_DIR/party$i.log"
	done
	exit 1
fi
