#!/bin/bash
set -e

CYAN='\033[0;36m'
GREEN='\033[0;32m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

echo ""
echo -e "${BOLD}${CYAN}Projecter${RESET} — Terminal project navigator"
echo ""

# Detect script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Copy scripts
cp "$SCRIPT_DIR/ssh-menu.sh" "$HOME/.ssh-menu.sh"
cp "$SCRIPT_DIR/project-nav.sh" "$HOME/.project-nav.sh"
chmod +x "$HOME/.ssh-menu.sh" "$HOME/.project-nav.sh"

echo -e "  ${GREEN}Installed${RESET} ~/.ssh-menu.sh"
echo -e "  ${GREEN}Installed${RESET} ~/.project-nav.sh"

# Install ssh-connect (s command)
INSTALL_DIR="$HOME/.local/bin"
mkdir -p "$INSTALL_DIR"
cp "$SCRIPT_DIR/ssh-connect.sh" "$INSTALL_DIR/s"
chmod +x "$INSTALL_DIR/s"
echo -e "  ${GREEN}Installed${RESET} $INSTALL_DIR/s"

# Create hosts config if it doesn't exist
HOSTS_DIR="$HOME/.config/ssh-menu"
if [ ! -f "$HOSTS_DIR/hosts" ]; then
    mkdir -p "$HOSTS_DIR"
    cp "$SCRIPT_DIR/hosts.example" "$HOSTS_DIR/hosts"
    echo -e "  ${GREEN}Created${RESET} $HOSTS_DIR/hosts (edit this to add your machines)"
else
    echo -e "  ${DIM}Hosts config already exists at $HOSTS_DIR/hosts${RESET}"
fi

# Detect shell config file
if [ -n "$ZSH_VERSION" ] || [ "$SHELL" = "$(which zsh 2>/dev/null)" ]; then
    RC_FILE="$HOME/.zshrc"
else
    RC_FILE="$HOME/.bashrc"
fi

# Check if already installed
if grep -q "project-nav.sh" "$RC_FILE" 2>/dev/null; then
    echo -e "  ${DIM}Shell config already set up in ${RC_FILE}${RESET}"
else
    cat >> "$RC_FILE" << 'SHELL_BLOCK'

# Projecter — terminal project navigator
p() { source ~/.project-nav.sh; }
if [ -n "$SSH_CONNECTION" ] && [ -z "$SSH_MENU_SHOWN" ]; then
    export SSH_MENU_SHOWN=1
    source ~/.ssh-menu.sh
fi
SHELL_BLOCK
    echo -e "  ${GREEN}Added${RESET} shell hooks to ${RC_FILE}"
fi

echo ""
echo -e "  ${BOLD}Configuration (add to ${RC_FILE}):${RESET}"
echo ""
echo -e "    ${DIM}# Set your projects directory (default: ~/Projects)${RESET}"
echo -e "    export PROJECTER_ROOT=\"\$HOME/Documents/Projects\""
echo ""
echo -e "    ${DIM}# Set your name for the SSH greeting (default: username)${RESET}"
echo -e "    export PROJECTER_USER=\"YourName\""
echo ""
echo -e "  ${BOLD}Usage:${RESET}"
echo -e "    ${CYAN}p${RESET}        — Open project navigator"
echo -e "    ${CYAN}s${RESET}        — SSH quick-connect menu"
echo -e "    ${CYAN}SSH in${RESET}    — Menu appears automatically"
echo ""
echo -e "  ${GREEN}Done!${RESET} Restart your shell or run: source ${RC_FILE}"
echo ""
