#!/bin/bash

set -e  # Exit on error
set -o pipefail  # Catch errors in pipes

# Function to print a section header
print_header() {
    echo "==========================================="
    echo "$1"
    echo "==========================================="
}

# Function to print a field with proper formatting
print_field() {
    local field_name="$1"
    local field_value="$2"
    printf "%-25s: %s\n" "$field_name" "$field_value"
}

# Function to parse and display a keyshare file
parse_keyshare() {
    local file="$1"
    local party="$2"
    
    print_header "Parsing keyshare for $party"
    
    # Read and decode the keyshare file
    local keyshare=$(cat "$file")
    local decoded=$(echo "$keyshare" | base64 -d)
    
    # Print basic fields
    print_field "Public Key" "$(echo "$decoded" | jq -r '.pub_key')"
    print_field "Local Party Key" "$(echo "$decoded" | jq -r '.local_party_key')"
    print_field "Chain Code" "$(echo "$decoded" | jq -r '.chain_code_hex')"
    print_field "Reshare Prefix" "$(echo "$decoded" | jq -r '.reshare_prefix')"
    
    # Print Nostr keys
    print_field "Nostr Public Key" "$(echo "$decoded" | jq -r '.nostr_pub_key')"
    print_field "Nostr Private Key" "$(echo "$decoded" | jq -r '.nostr_priv_key')"
    
    # Print Keygen Committee Keys
    echo "Keygen Committee Keys:"
    echo "$decoded" | jq -r '.keygen_committee_keys[]' | while read -r key; do
        echo "  - $key"
    done
    
    # Print Peer Nostr Public Keys
    echo "Peer Nostr Public Keys:"
    echo "$decoded" | jq -r '.peer_nostr_pub_keys | to_entries | .[] | "  \(.key): \(.value)"'
    
    # Print ECDSA Local Data (summary)
    echo "ECDSA Local Data Summary:"
    echo "$decoded" | jq -r '.ecdsa_local_data | "  Share Index: \(.ShareIndex)\n  Key Index: \(.KeyIndex)\n  Private Key: \(.PrivateKey)\n  Public Key: \(.PublicKey)"'
    
    echo -e "\n"
}

# Parse both peer keyshares
parse_keyshare "peer1.ks" "Peer 1"
parse_keyshare "peer2.ks" "Peer 2" 