#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

RELAYS_DEFAULT="wss://bbw-nostr.xyz"
RELAYS="${RELAYS:-$RELAYS_DEFAULT}"
TIMEOUT="${TIMEOUT:-90}"
KEYGEN_OUTPUT_DIR="${OUTPUT_DIR:-./nostr-keygen-output}"
KEYSIGN_OUTPUT_DIR="${KEYSIGN_OUTPUT_DIR:-./nostr-keysign-output}"
mkdir -p "$KEYSIGN_OUTPUT_DIR"

random_hex() {
	go run ./scripts/main.go random
}

# Prompt user for number of parties
echo "=== Nostr Keysign - Multi-Party Setup ==="
read -p "Enter the number of parties for the session: " NUM_PARTIES

# Validate input
if ! [[ "$NUM_PARTIES" =~ ^[0-9]+$ ]] || [ "$NUM_PARTIES" -lt 2 ]; then
	echo "Error: Number of parties must be an integer >= 2"
	exit 1
fi

# Prompt for keyshare directory
echo ""
read -p "Keyshare directory [${KEYGEN_OUTPUT_DIR}]: " KEYSHARE_DIR_INPUT
KEYSHARE_DIR="${KEYSHARE_DIR_INPUT:-$KEYGEN_OUTPUT_DIR}"

# Validate keyshare files exist
echo ""
echo "Checking for keyshare files..."
MISSING_FILES=()
declare -a KEYSHARE_FILES
for ((i=1; i<=NUM_PARTIES; i++)); do
	KEYSHARE_FILE="$KEYSHARE_DIR/party$i-keyshare.json"
	KEYSHARE_FILES[$i]="$KEYSHARE_FILE"
	if [ ! -f "$KEYSHARE_FILE" ]; then
		MISSING_FILES+=("$KEYSHARE_FILE")
	fi
done

if [ ${#MISSING_FILES[@]} -gt 0 ]; then
	echo "Error: Missing keyshare files:"
	for file in "${MISSING_FILES[@]}"; do
		echo "  - $file"
	done
	echo ""
	echo "Please run nostr-keygen-nparty.sh first to generate keyshares."
	exit 1
fi

echo "✓ All keyshare files found"

# Extract npubs and nsecs from keyshare files
echo ""
echo "Extracting party information from keyshares..."
declare -a NSEC_ARRAY
declare -a NPUB_ARRAY
declare -a ALL_PARTIES_ARRAY

for ((i=1; i<=NUM_PARTIES; i++)); do
	NPUB_ARRAY[$i]=$(go run ./scripts/main.go extract-npub "${KEYSHARE_FILES[$i]}")
	NSEC_ARRAY[$i]=$(go run ./scripts/main.go extract-nsec "${KEYSHARE_FILES[$i]}")
	ALL_PARTIES_ARRAY[$i]=${NPUB_ARRAY[$i]}
done

# Build all parties CSV
ALL_PARTIES_CSV=$(IFS=','; echo "${ALL_PARTIES_ARRAY[*]}")

# Prompt for which parties to use for signing
echo ""
echo "Available parties:"
for ((i=1; i<=NUM_PARTIES; i++)); do
	echo "  Party $i: ${NPUB_ARRAY[$i]}"
done
echo ""
read -p "Enter party numbers to use for signing (comma-separated, e.g., 1,2,3 or press Enter for all): " PARTY_SELECTION

if [ -z "$PARTY_SELECTION" ]; then
	# Use all parties
	KEYSIGN_PARTIES_CSV="$ALL_PARTIES_CSV"
	KEYSIGN_PARTY_NUMS=()
	for ((i=1; i<=NUM_PARTIES; i++)); do
		KEYSIGN_PARTY_NUMS+=($i)
	done
else
	# Parse selected parties
	KEYSIGN_PARTY_NUMS=()
	KEYSIGN_PARTIES=()
	IFS=',' read -ra SELECTED <<< "$PARTY_SELECTION"
	for party_num in "${SELECTED[@]}"; do
		party_num=$(echo "$party_num" | tr -d ' ')
		if ! [[ "$party_num" =~ ^[0-9]+$ ]] || [ "$party_num" -lt 1 ] || [ "$party_num" -gt "$NUM_PARTIES" ]; then
			echo "Error: Invalid party number: $party_num"
			exit 1
		fi
		KEYSIGN_PARTY_NUMS+=($party_num)
		KEYSIGN_PARTIES+=("${NPUB_ARRAY[$party_num]}")
	done
	KEYSIGN_PARTIES_CSV=$(IFS=','; echo "${KEYSIGN_PARTIES[*]}")
fi

KEYSIGN_NUM_PARTIES=${#KEYSIGN_PARTY_NUMS[@]}
echo "Using $KEYSIGN_NUM_PARTIES parties for signing: ${KEYSIGN_PARTY_NUMS[*]}"

# Prompt for message to sign
echo ""
read -p "Enter message to sign (hex string, or press Enter to generate random): " MESSAGE_INPUT
if [ -z "$MESSAGE_INPUT" ]; then
	MESSAGE=$(random_hex)
	echo "Generated random message: $MESSAGE"
else
	MESSAGE="$MESSAGE_INPUT"
	# Validate hex string
	if ! [[ "$MESSAGE" =~ ^[0-9a-fA-F]+$ ]]; then
		echo "Warning: Message does not appear to be a valid hex string"
	fi
fi

# Prompt for derivation path
echo ""
DEFAULT_DERIVATION_PATH="m/44'/0'/0'/0/0"
read -p "Enter derivation path [$DEFAULT_DERIVATION_PATH]: " DERIVATION_PATH_INPUT
DERIVATION_PATH="${DERIVATION_PATH_INPUT:-$DEFAULT_DERIVATION_PATH}"

# Prompt for relays
echo ""
read -p "Enter Nostr relays (comma-separated) [${RELAYS}]: " RELAYS_INPUT
if [ -n "$RELAYS_INPUT" ]; then
	RELAYS="$RELAYS_INPUT"
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
RECOMMENDED_TIMEOUT=$((60 + (KEYSIGN_NUM_PARTIES * 20)))
if [ -n "${TIMEOUT:-}" ] && [ "$TIMEOUT" != "90" ]; then
	USER_TIMEOUT="$TIMEOUT"
else
	USER_TIMEOUT="$RECOMMENDED_TIMEOUT"
fi

# Prompt user for timeout
echo ""
read -p "Timeout in seconds (recommended: ${RECOMMENDED_TIMEOUT}s for $KEYSIGN_NUM_PARTIES parties) [${USER_TIMEOUT}]: " TIMEOUT_INPUT
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

# Generate session ID and key for keysign
SESSION_ID="$(random_hex)"
SESSION_KEY="$(random_hex)"

echo ""
echo "=== Keysign Parameters ==="
echo "Relays         : $RELAYS"
echo "Session ID     : $SESSION_ID"
echo "Session Key    : $SESSION_KEY"
echo "Message        : $MESSAGE"
echo "Derivation Path: $DERIVATION_PATH"
echo "Parties        : ${KEYSIGN_PARTY_NUMS[*]}"
echo "============================"

run_party() {
	local party_num="$1"
	local nsec="$2"
	local npub="$3"
	local keyshare="$4"
	local output="$5"
	local log="$6"
	local verbose="$7"

	if [ "$verbose" -eq 1 ]; then
		# Verbose mode: tee both stdout and stderr, filter stdout for JSON
		go run ./tss/cmd/nostr-keysign \
			-relays "$RELAYS" \
			-nsec "$nsec" \
			-peers "$KEYSIGN_PARTIES_CSV" \
			-session "$SESSION_ID" \
			-session-key "$SESSION_KEY" \
			-keyshare "$keyshare" \
			-path "$DERIVATION_PATH" \
			-message "$MESSAGE" \
			-timeout "$TIMEOUT" 2>&1 | tee "$log" | awk '/^{/,/^}/' > "$output" || true
	else
		# Non-verbose mode: redirect stderr to log file, filter stdout to extract only JSON
		go run ./tss/cmd/nostr-keysign \
			-relays "$RELAYS" \
			-nsec "$nsec" \
			-peers "$KEYSIGN_PARTIES_CSV" \
			-session "$SESSION_ID" \
			-session-key "$SESSION_KEY" \
			-keyshare "$keyshare" \
			-path "$DERIVATION_PATH" \
			-message "$MESSAGE" \
			-timeout "$TIMEOUT" 2> "$log" | awk '/^{/,/^}/' > "$output" || true
	fi
}

# Initialize arrays for PIDs, outputs, and logs
declare -a PIDS
declare -a OUTPUTS
declare -a LOGS

echo ""
echo "Starting Nostr keysign for $KEYSIGN_NUM_PARTIES parties in parallel..."

# Record start time
START_TIME=$(date +%s)

# Run all selected parties in background
for idx in "${!KEYSIGN_PARTY_NUMS[@]}"; do
	PARTY_NUM=${KEYSIGN_PARTY_NUMS[$idx]}
	OUTPUT_FILE="$KEYSIGN_OUTPUT_DIR/party${PARTY_NUM}-signature.json"
	LOG_FILE="$KEYSIGN_OUTPUT_DIR/party${PARTY_NUM}.log"
	
	OUTPUTS[$idx]="$OUTPUT_FILE"
	LOGS[$idx]="$LOG_FILE"
	
	# Remove old log file if it exists
	rm -f "$LOG_FILE"
	
	if [ $VERBOSE_MODE -eq 1 ]; then
		# Verbose mode: display in terminal and log to file
		echo "Party $PARTY_NUM output - also logged to: $LOG_FILE"
		run_party "$PARTY_NUM" "${NSEC_ARRAY[$PARTY_NUM]}" "${NPUB_ARRAY[$PARTY_NUM]}" "${KEYSHARE_FILES[$PARTY_NUM]}" "$OUTPUT_FILE" "$LOG_FILE" "$VERBOSE_MODE" &
	else
		# Non-verbose mode: log to file only
		echo "$(pwd)/$LOG_FILE"
		run_party "$PARTY_NUM" "${NSEC_ARRAY[$PARTY_NUM]}" "${NPUB_ARRAY[$PARTY_NUM]}" "${KEYSHARE_FILES[$PARTY_NUM]}" "$OUTPUT_FILE" "$LOG_FILE" "$VERBOSE_MODE" &
	fi
	PIDS[$idx]=$!
	echo "Party $PARTY_NUM PID: ${PIDS[$idx]}"
done

# Build cleanup command
CLEANUP_CMD="kill"
for pid in "${PIDS[@]}"; do
	CLEANUP_CMD="$CLEANUP_CMD $pid"
done
CLEANUP_CMD="$CLEANUP_CMD 2>/dev/null; exit"

# Handle cleanup on exit
trap "echo Stopping processes...; $CLEANUP_CMD" SIGINT SIGTERM

echo ""
echo "Logs:"
for log in "${LOGS[@]}"; do
	echo "  $log"
done
echo ""
echo "Waiting for keysign to complete..."
echo "Note: If the process seems stuck, check the log files for progress"
echo ""

# Wait for all processes with timeout monitoring
declare -a EXIT_CODES
ALL_SUCCESS=0
TIMEOUT_REACHED=0

# Calculate timeout with some buffer (add 30 seconds to user timeout)
WAIT_TIMEOUT=$((TIMEOUT + 30))
START_WAIT=$(date +%s)

# Function to check if processes are still running
check_processes() {
	for idx in "${!PIDS[@]}"; do
		if ! kill -0 ${PIDS[$idx]} 2>/dev/null; then
			return 1  # At least one process finished
		fi
	done
	return 0  # All processes still running
}

# Wait for processes with progress updates
while true; do
	# Check if all processes have finished
	ALL_DONE=1
	for idx in "${!PIDS[@]}"; do
		if kill -0 ${PIDS[$idx]} 2>/dev/null; then
			ALL_DONE=0
			break
		fi
	done
	
	if [ $ALL_DONE -eq 1 ]; then
		break
	fi
	
	# Check for timeout
	CURRENT_TIME=$(date +%s)
	ELAPSED_WAIT=$((CURRENT_TIME - START_WAIT))
	if [ $ELAPSED_WAIT -ge $WAIT_TIMEOUT ]; then
		echo ""
		echo "⚠️  WARNING: Timeout reached (${WAIT_TIMEOUT}s) while waiting for processes to complete"
		echo "Some processes may still be running. Checking status..."
		echo ""
		echo "Common causes for keysign to hang:"
		echo "  1. Not all parties started simultaneously"
		echo "  2. Network/relay connectivity issues"
		echo "  3. Timeout too short for the number of parties"
		echo "  4. One or more parties failed to connect"
		echo ""
		echo "Check the log files for more details:"
		for log in "${LOGS[@]}"; do
			if [ -f "$log" ]; then
				LAST_LINE=$(tail -1 "$log" 2>/dev/null || echo "empty")
				echo "  $(basename $log): $LAST_LINE"
			fi
		done
		TIMEOUT_REACHED=1
		break
	fi
	
	# Show progress every 10 seconds
	if [ $((ELAPSED_WAIT % 10)) -eq 0 ] && [ $ELAPSED_WAIT -gt 0 ]; then
		echo "  Still waiting... (${ELAPSED_WAIT}s elapsed, timeout: ${WAIT_TIMEOUT}s)"
	fi
	
	sleep 1
done

# Collect exit codes
for idx in "${!PIDS[@]}"; do
	if kill -0 ${PIDS[$idx]} 2>/dev/null; then
		# Process still running - kill it
		echo "  Killing hung process (Party ${KEYSIGN_PARTY_NUMS[$idx]}, PID: ${PIDS[$idx]})"
		kill ${PIDS[$idx]} 2>/dev/null || true
		sleep 1
		kill -9 ${PIDS[$idx]} 2>/dev/null || true
		EXIT_CODES[$idx]=124  # Timeout exit code
		ALL_SUCCESS=1
	else
		# Process finished - get exit code
		wait ${PIDS[$idx]} 2>/dev/null
		EXIT_CODES[$idx]=$?
		if [ ${EXIT_CODES[$idx]} -ne 0 ]; then
			ALL_SUCCESS=1
		fi
	fi
done

# Calculate elapsed time
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
if [ $ALL_SUCCESS -eq 0 ]; then
	echo "✓ Keysign completed successfully!"
	echo ""
	
	# Display signatures
	ALL_OUTPUTS_EXIST=0
	for idx in "${!OUTPUTS[@]}"; do
		PARTY_NUM=${KEYSIGN_PARTY_NUMS[$idx]}
		OUTPUT_FILE="${OUTPUTS[$idx]}"
		if [ -f "$OUTPUT_FILE" ]; then
			echo "=== Party $PARTY_NUM Signature ==="
			if command -v jq >/dev/null 2>&1; then
				jq . "$OUTPUT_FILE" 2>/dev/null || cat "$OUTPUT_FILE"
			else
				cat "$OUTPUT_FILE"
			fi
			echo ""
		else
			ALL_OUTPUTS_EXIST=1
		fi
	done
	
	if [ $ALL_OUTPUTS_EXIST -eq 0 ]; then
		# Verify signatures match (compare JSON files)
		if [ ${#OUTPUTS[@]} -gt 1 ]; then
			if command -v jq >/dev/null 2>&1; then
				# Normalize and compare JSON
				FIRST_NORM=$(jq -c . "${OUTPUTS[0]}" 2>/dev/null)
				ALL_MATCH=1
				for idx in "${!OUTPUTS[@]}"; do
					if [ $idx -eq 0 ]; then
						continue
					fi
					CURRENT_NORM=$(jq -c . "${OUTPUTS[$idx]}" 2>/dev/null)
					if [ "$FIRST_NORM" != "$CURRENT_NORM" ] || [ -z "$FIRST_NORM" ]; then
						ALL_MATCH=0
						break
					fi
				done
				if [ $ALL_MATCH -eq 1 ] && [ -n "$FIRST_NORM" ]; then
					echo "✓ All signatures match!"
				else
					echo "⚠ Warning: Signatures differ - this should not happen"
				fi
			else
				# Fallback: simple file comparison
				ALL_MATCH=1
				for idx in "${!OUTPUTS[@]}"; do
					if [ $idx -eq 0 ]; then
						continue
					fi
					if ! cmp -s "${OUTPUTS[0]}" "${OUTPUTS[$idx]}"; then
						ALL_MATCH=0
						break
					fi
				done
				if [ $ALL_MATCH -eq 1 ]; then
					echo "✓ All signatures match!"
				else
					echo "⚠ Warning: Signatures differ - this should not happen"
				fi
			fi
		fi
		
		echo ""
		echo "Signatures saved to:"
		for idx in "${!OUTPUTS[@]}"; do
			PARTY_NUM=${KEYSIGN_PARTY_NUMS[$idx]}
			echo "  Party $PARTY_NUM: ${OUTPUTS[$idx]}"
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
	for idx in "${!LOGS[@]}"; do
		PARTY_NUM=${KEYSIGN_PARTY_NUMS[$idx]}
		LOG_FILE="${LOGS[$idx]}"
		PARTY_BYTES=0
		
		if [ -f "$LOG_FILE" ]; then
			# Count events sent (Client.PublishWrap lines with "event kind=" - these are the actual events)
			EVENT_COUNT=$(grep -c "Client.PublishWrap - event kind=" "$LOG_FILE" 2>/dev/null || echo "0")
			EVENTS_PER_PARTY[$idx]=$EVENT_COUNT
			TOTAL_EVENTS=$((TOTAL_EVENTS + EVENT_COUNT))
			
			# Extract bytes sent from "Messenger sending message" lines
			# Format: BBMTLog: Messenger sending message from ... to ... with bytes count
			while IFS= read -r line; do
				if [[ $line =~ \(([0-9]+)\ bytes\) ]]; then
					BYTES="${BASH_REMATCH[1]}"
					PARTY_BYTES=$((PARTY_BYTES + BYTES))
					TOTAL_BYTES=$((TOTAL_BYTES + BYTES))
				fi
			done < <(grep "Messenger sending message" "$LOG_FILE" 2>/dev/null || true)
		fi
		
		BYTES_PER_PARTY[$idx]=$PARTY_BYTES
	done
	
	# Convert bytes to KB (divide by 1024)
	TOTAL_KB=$((TOTAL_BYTES / 1024))
	
	# Display per-party statistics
	echo "Nostr events sent per party:"
	for idx in "${!EVENTS_PER_PARTY[@]}"; do
		PARTY_NUM=${KEYSIGN_PARTY_NUMS[$idx]}
		PARTY_KB=$((BYTES_PER_PARTY[$idx] / 1024))
		echo "  Party $PARTY_NUM: ${EVENTS_PER_PARTY[$idx]} nostr events, ${PARTY_KB} KB"
	done
	echo ""
	echo "Total nostr events sent: $TOTAL_EVENTS"
	echo "Total data transmitted: ${TOTAL_KB} KB - ${TOTAL_BYTES} bytes"
	echo "============================"
else
	echo "✗ Keysign failed!"
	echo "Time elapsed: ${ELAPSED} seconds"
	if [ $TIMEOUT_REACHED -eq 1 ]; then
		echo ""
		echo "⚠️  Process timed out. This usually means:"
		echo "  - Not all parties started at the same time"
		echo "  - Network/relay issues preventing communication"
		echo "  - Timeout value too short (try increasing with -timeout flag)"
		echo ""
		echo "To retry:"
		echo "  1. Ensure all parties start simultaneously"
		echo "  2. Check relay connectivity"
		echo "  3. Increase timeout: rerun with higher timeout value"
	fi
	echo ""
	echo "Exit codes:"
	for idx in "${!EXIT_CODES[@]}"; do
		PARTY_NUM=${KEYSIGN_PARTY_NUMS[$idx]}
		EXIT_CODE=${EXIT_CODES[$idx]}
		if [ $EXIT_CODE -eq 124 ]; then
			echo "  Party $PARTY_NUM: TIMEOUT (process was killed)"
		else
			echo "  Party $PARTY_NUM: $EXIT_CODE"
		fi
	done
	echo ""
	echo "Check logs for details:"
	for log in "${LOGS[@]}"; do
		if [ -f "$log" ]; then
			echo "  $log"
			# Show last few lines of each log
			echo "    Last lines:"
			tail -3 "$log" 2>/dev/null | sed 's/^/      /' || echo "      (log file empty or unreadable)"
		fi
	done
	exit 1
fi
