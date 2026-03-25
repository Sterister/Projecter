#!/usr/bin/env bash
set -euo pipefail

HOSTS_FILE="$HOME/.config/ssh-menu/hosts"

if [[ ! -f "$HOSTS_FILE" ]]; then
    echo "No hosts file found: $HOSTS_FILE"
    echo "Create one with the format:"
    echo "  # Name | User | Address"
    echo "  Desktop | stian | 100.x.x.x"
    exit 1
fi

# Read entries (ignore blank lines and comments)
mapfile -t entries < <(grep -v '^\s*#' "$HOSTS_FILE" | grep -v '^\s*$')

if [[ ${#entries[@]} -eq 0 ]]; then
    echo "No entries in $HOSTS_FILE"
    exit 1
fi

# Build display lists
names=()
users=()
addrs=()
for entry in "${entries[@]}"; do
    IFS='|' read -r name user addr <<< "$entry"
    names+=("$(echo "$name" | xargs)")
    users+=("$(echo "$user" | xargs)")
    addrs+=("$(echo "$addr" | xargs)")
done

# Select host
if command -v fzf &>/dev/null; then
    display=""
    for i in "${!names[@]}"; do
        display+="${names[$i]}  →  ${users[$i]}@${addrs[$i]}"$'\n'
    done
    chosen=$(echo -n "$display" | fzf --height=~50% --reverse --prompt="SSH to: ") || exit 0
    idx=-1
    for i in "${!names[@]}"; do
        line="${names[$i]}  →  ${users[$i]}@${addrs[$i]}"
        if [[ "$chosen" == "$line" ]]; then
            idx=$i
            break
        fi
    done
else
    # Fallback: numbered list
    echo "SSH menu:"
    echo ""
    for i in "${!names[@]}"; do
        printf "  %d) %s  →  %s@%s\n" $((i+1)) "${names[$i]}" "${users[$i]}" "${addrs[$i]}"
    done
    echo ""
    read -rp "Select (1-${#names[@]}): " choice
    if [[ -z "$choice" ]]; then exit 0; fi
    idx=$((choice - 1))
    if [[ $idx -lt 0 || $idx -ge ${#names[@]} ]]; then
        echo "Invalid selection"
        exit 1
    fi
fi

if [[ $idx -ge 0 ]]; then
    echo "Connecting to ${names[$idx]} (${users[$idx]}@${addrs[$idx]})..."
    exec ssh "${users[$idx]}@${addrs[$idx]}"
fi
