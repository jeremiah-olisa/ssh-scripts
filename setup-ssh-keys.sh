#!/bin/bash
# =============================================================================
# setup-ssh-keys.sh — SSH Key Generation & Authentication Hardening
# Version: 1.0.0
# Supports: Ubuntu 24.04 LTS, macOS (key generation only)
# Hardens SSH: disables root login, disables password auth
# Idempotent — safe to re-run at any time
# Usage: sudo bash setup-ssh-keys.sh [--generate] [--key-path PATH] [--user USER]
# =============================================================================

set -euo pipefail

# === COLORS ===
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

log()     { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
err()     { echo -e "${RED}[ERR]${NC} $1"; exit 1; }
info()    { echo -e "${CYAN}[>>]${NC} $1"; }
section() { echo -e "\n${BLUE}━━━ $1 ━━━${NC}"; }

# === ROOT CHECK ===
[ "$(id -u)" -ne 0 ] && err "Run as root: sudo bash setup-ssh-keys.sh"

# === DEFAULTS ===
GENERATE_KEYS=0
KEY_PATH=""
TARGET_USER="root"
SSH_USER_HOME=""
PUBKEY=""
LOCAL_PUBKEY_PATH=""
GENERATE_FOR_USER=0

# === HELP ===
usage() {
  cat << 'EOF'
Usage: sudo bash setup-ssh-keys.sh [OPTIONS]

OPTIONS:
  --generate              Generate new SSH key pair for the target user
  --key-path PATH         Path to public key file to import (e.g., ~/.ssh/id_rsa.pub)
  --user USER             Target user for SSH hardening (default: root)
  --help                  Show this help message

EXAMPLES:

  # Generate new key for root
  sudo bash setup-ssh-keys.sh --generate

  # Import existing key for root
  sudo bash setup-ssh-keys.sh --key-path /path/to/id_rsa.pub

  # Generate key for devops user
  sudo bash setup-ssh-keys.sh --generate --user devops

  # Import key for devops user
  sudo bash setup-ssh-keys.sh --key-path ~/.ssh/id_rsa.pub --user devops

WHAT THIS SCRIPT DOES:

  1. Validates or generates an SSH public key
  2. Adds public key to target user's ~/.ssh/authorized_keys
  3. Sets correct permissions (700 for ~/.ssh, 600 for authorized_keys)
  4. Disables root login (PermitRootLogin no)
  5. Disables password authentication (PasswordAuthentication no)
  6. Enforces public key authentication (PubkeyAuthentication yes)
  7. Runs SSH validation check (sshd -t)
  8. Reloads SSH daemon

SAFETY:

  - Idempotent: safe to re-run
  - Validates SSH config before applying
  - Backs up existing authorized_keys
  - Tests SSH syntax before reload

EOF
  exit 0
}

# === ARGUMENT PARSING ===
while [[ $# -gt 0 ]]; do
  case "$1" in
    --generate)
      GENERATE_KEYS=1
      shift
      ;;
    --key-path)
      KEY_PATH="$2"
      shift 2
      ;;
    --user)
      TARGET_USER="$2"
      shift 2
      ;;
    --help)
      usage
      ;;
    *)
      err "Unknown option: $1"
      ;;
  esac
done

# =============================================================================
# STEP 0: VALIDATE TARGET USER
# =============================================================================
section "Validating target user"

if ! id "$TARGET_USER" &>/dev/null; then
  err "User '$TARGET_USER' does not exist"
fi

SSH_USER_HOME=$(eval echo "~$TARGET_USER")
log "Target user: $TARGET_USER (home: $SSH_USER_HOME)"

# =============================================================================
# STEP 1: GENERATE OR IMPORT SSH KEY
# =============================================================================
if [ $GENERATE_KEYS -eq 1 ]; then
  section "Generating SSH key pair"
  
  TEMP_DIR=$(mktemp -d)
  trap "rm -rf $TEMP_DIR" EXIT
  
  TEMP_KEY="${TEMP_DIR}/id_rsa"
  TEMP_PUBKEY="${TEMP_DIR}/id_rsa.pub"
  
  info "Generating 4096-bit RSA key..."
  ssh-keygen -t rsa -b 4096 -f "$TEMP_KEY" -N "" -C "$TARGET_USER@$(hostname)" > /dev/null 2>&1
  
  PUBKEY=$(cat "$TEMP_PUBKEY")
  LOCAL_PUBKEY_PATH="$TEMP_PUBKEY"
  
  log "SSH key generated"
  
  # Display private key for user to save
  echo ""
  echo -e "${YELLOW}━━━ SAVE THIS PRIVATE KEY SECURELY ━━━${NC}"
  echo ""
  cat "$TEMP_KEY"
  echo ""
  echo -e "${YELLOW}━━━ END PRIVATE KEY ━━━${NC}"
  echo ""
  warn "⚠️  IMPORTANT: Copy the private key above and save it somewhere safe."
  warn "⚠️  You will need it to SSH into $TARGET_USER@$(hostname)"
  warn "⚠️  This key will NOT be displayed again."
  echo ""
  read -p "Press Enter once you've saved the private key..."
  
elif [ -n "$KEY_PATH" ]; then
  section "Importing SSH public key"
  
  # Expand ~ if needed
  KEY_PATH="${KEY_PATH/#\~/$HOME}"
  
  if [ ! -f "$KEY_PATH" ]; then
    err "Public key file not found: $KEY_PATH"
  fi
  
  PUBKEY=$(cat "$KEY_PATH")
  LOCAL_PUBKEY_PATH="$KEY_PATH"
  
  log "Public key imported from $KEY_PATH"
else
  err "Must provide either --generate or --key-path"
fi

# =============================================================================
# STEP 2: VALIDATE PUBLIC KEY FORMAT
# =============================================================================
section "Validating public key"

if ! echo "$PUBKEY" | grep -qE '^ssh-rsa |^ssh-ed25519 |^ecdsa-sha2-'; then
  err "Invalid public key format. Expected ssh-rsa, ssh-ed25519, or ecdsa-sha2-*"
fi

log "Public key valid"

# =============================================================================
# STEP 3: SET UP ~/.ssh DIRECTORY
# =============================================================================
section "Setting up ~/.ssh for $TARGET_USER"

SSH_DIR="${SSH_USER_HOME}/.ssh"
AUTHORIZED_KEYS="${SSH_DIR}/authorized_keys"

if [ ! -d "$SSH_DIR" ]; then
  mkdir -p "$SSH_DIR"
  chmod 700 "$SSH_DIR"
  chown "$TARGET_USER:$TARGET_USER" "$SSH_DIR"
  log "Created $SSH_DIR"
else
  log "$SSH_DIR already exists"
fi

# =============================================================================
# STEP 4: BACKUP & ADD PUBLIC KEY
# =============================================================================
section "Adding public key to authorized_keys"

if [ -f "$AUTHORIZED_KEYS" ]; then
  cp "$AUTHORIZED_KEYS" "${AUTHORIZED_KEYS}.backup-$(date +%Y%m%d-%H%M%S)"
  warn "Backed up existing authorized_keys"
fi

# Check if key already exists
if grep -q "$(echo "$PUBKEY" | awk '{print $2}')" "$AUTHORIZED_KEYS" 2>/dev/null; then
  log "Public key already in authorized_keys (no change)"
else
  echo "$PUBKEY" >> "$AUTHORIZED_KEYS"
  log "Public key added to authorized_keys"
fi

chmod 600 "$AUTHORIZED_KEYS"
chown "$TARGET_USER:$TARGET_USER" "$AUTHORIZED_KEYS"

# =============================================================================
# STEP 5: HARDEN SSH CONFIG
# =============================================================================
section "Hardening SSH configuration"

SSHD_CONF="/etc/ssh/sshd_config.d/harden-keys.conf"

cat > "$SSHD_CONF" << EOF
# =============================================================================
# SSH Hardening for Key-Based Authentication
# Applied by setup-ssh-keys.sh
# =============================================================================

# Disable root login completely
PermitRootLogin no

# Require public key authentication
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
KbdInteractiveAuthentication no

# Session limits & timeouts
MaxAuthTries 3
MaxSessions 2
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2

# Security logging
LogLevel VERBOSE

# Disable forwarding & X11 (adjust as needed for your use case)
AllowTcpForwarding no
X11Forwarding no

# DNS off (faster auth, less DNS exposure)
UseDNS no
EOF

log "SSH hardening config written to $SSHD_CONF"

# =============================================================================
# STEP 6: VALIDATE SSH CONFIG
# =============================================================================
section "Validating SSH configuration"

if sshd -t 2>&1 | grep -i error; then
  err "SSH config validation failed — not reloading"
fi

log "SSH config syntax valid"

# =============================================================================
# STEP 7: RELOAD SSH DAEMON
# =============================================================================
section "Reloading SSH daemon"

if systemctl is-active ssh &>/dev/null; then
  systemctl reload ssh
  log "SSH daemon reloaded (ssh)"
elif systemctl is-active sshd &>/dev/null; then
  systemctl reload sshd
  log "SSH daemon reloaded (sshd)"
else
  warn "SSH daemon not found or not running"
fi

# =============================================================================
# STEP 8: VERIFICATION CHECKLIST
# =============================================================================
section "Verifying SSH hardening"

PASS=0; FAIL=0

check() {
  local label="$1" cmd="$2" expect="$3" result
  result=$(eval "$cmd" 2>/dev/null || echo "")
  if echo "$result" | grep -q "$expect"; then
    echo -e "  ${GREEN}✓${NC} $label"
    ((PASS++))
  else
    echo -e "  ${RED}✗${NC} $label"
    ((FAIL++))
  fi
}

check "Public key in authorized_keys"     "grep -c '$(echo "$PUBKEY" | awk '{print $2}')' $AUTHORIZED_KEYS"    "[1-9]"
check "authorized_keys owned by $TARGET_USER"  "stat -c '%U' $AUTHORIZED_KEYS"                               "$TARGET_USER"
check "authorized_keys has 600 perms"     "stat -c '%a' $AUTHORIZED_KEYS"                                "600"
check "~/.ssh owned by $TARGET_USER"      "stat -c '%U' $SSH_DIR"                                        "$TARGET_USER"
check "~/.ssh has 700 perms"              "stat -c '%a' $SSH_DIR"                                        "700"
check "PermitRootLogin disabled"          "sshd -T | grep permitrootlogin"                               "no"
check "PasswordAuthentication disabled"   "sshd -T | grep passwordauthentication"                        "no"
check "PubkeyAuthentication enabled"      "sshd -T | grep pubkeyauthentication"                         "yes"

echo ""
echo -e "${BLUE}━━━ Verification Results ━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${GREEN}Passed: $PASS${NC}   ${RED}Failed: $FAIL${NC}"

if [ $FAIL -gt 0 ]; then
  err "Some checks failed — SSH may not be properly configured"
fi

# =============================================================================
# FINAL SUMMARY
# =============================================================================
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN} SSH KEY SETUP COMPLETE — v1.0.0${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [ $GENERATE_KEYS -eq 1 ]; then
  echo -e "${YELLOW} 🔑 NEXT STEPS:${NC}"
  echo -e " 1. Save the private key you displayed above to your local machine:"
  echo -e "    ${CYAN}~/.ssh/id_rsa${NC} (on your workstation)"
  echo ""
  echo -e " 2. Set correct permissions on local private key:"
  echo -e "    ${CYAN}chmod 600 ~/.ssh/id_rsa${NC}"
  echo ""
  echo -e " 3. Test SSH connection:"
  echo -e "    ${CYAN}ssh -i ~/.ssh/id_rsa $TARGET_USER@$(hostname)${NC}"
  echo ""
else
  echo -e "${YELLOW} 🔑 NEXT STEPS:${NC}"
  echo -e " 1. Ensure private key for $TARGET_USER exists on your workstation"
  echo ""
  echo -e " 2. Test SSH connection:"
  echo -e "    ${CYAN}ssh -i /path/to/private/key $TARGET_USER@$(hostname)${NC}"
  echo ""
fi

echo -e " 3. Password login is now DISABLED for all users"
echo -e " 4. Root login is now DISABLED"
echo -e " 5. Only SSH key authentication works"
echo ""
echo -e "${YELLOW} KEY FILES:${NC}"
echo -e "  $AUTHORIZED_KEYS"
echo -e "  $SSHD_CONF"
echo -e "  /etc/ssh/sshd_config"
echo ""
echo -e "${YELLOW} ROLLBACK (if needed):${NC}"
if [ -f "${AUTHORIZED_KEYS}.backup-"* ]; then
  echo -e "  Authorized keys backup: ${AUTHORIZED_KEYS}.backup-*"
  echo -e "  SSH config backup: /etc/ssh/sshd_config.orig (if exists)"
fi
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
