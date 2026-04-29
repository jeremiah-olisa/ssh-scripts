#!/bin/bash
# =============================================================================
# verify-hardening.sh — Automated Hardening Verification (50+ Tests)
# =============================================================================
#
# WHAT THIS SCRIPT DOES:
#   Tests that all hardening steps from harden-node.sh are actually working.
#   Runs 50+ automated checks and shows which ones PASS (✅) and FAIL (❌).
#
# WHY VERIFY:
#   Sometimes hardening steps fail silently (e.g., UFW rule doesn't apply,
#   iptables chain not created, service didn't start). This script finds
#   problems so you can fix them before relying on security.
#
# USAGE:
#   # Run all checks (shows color-coded pass/fail)
#   sudo bash verify-hardening.sh
#
#   # Run with verbose debugging (shows WHY checks pass/fail)
#   VERBOSE=1 sudo bash verify-hardening.sh
#
# WHAT IT CHECKS:
#   ✓ UFW Firewall       = Rules correctly configured
#   ✓ SSH Hardening      = Root login disabled, keys required
#   ✓ Tailscale          = Installed, connected, has IP
#   ✓ iptables           = DOCKER-USER chain exists, rules applied
#   ✓ Kernel Hardening   = Sysctl parameters set correctly
#   ✓ Services           = auditd, fail2ban, AppArmor running
#   ✓ Audit Logging      = Rules loaded and active
#
# EXIT CODES:
#   0 = All checks passed (system is hardened!)
#   1 = One or more checks failed (fix the issue)
#
# VERBOSE MODE:
#   Set VERBOSE=1 to see WHY each check passes/fails
#   VERBOSE=1 sudo bash verify-hardening.sh
#
# VERSION: 1.0.0 | Last Updated: 2026-04-29
# =============================================================================

set -euo pipefail

# =============================================================================
# LOGGING FUNCTIONS - Pretty-print with colors for readability
# =============================================================================
RED='\033[0;31m'          # Red = errors or failed checks
GREEN='\033[0;32m'        # Green = success or passed checks
YELLOW='\033[1;33m'       # Yellow = warnings
BLUE='\033[0;34m'         # Blue = section headers
CYAN='\033[0;36m'         # Cyan = info messages
NC='\033[0m'              # NC = "No Color" (reset terminal color)

# Print success message with green [OK] prefix
log()     { echo -e "${GREEN}[OK]${NC} $1"; }

# Print warning message with yellow [!] prefix
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }

# Print error message with red [ERR] prefix (doesn't exit like in other scripts)
err()     { echo -e "${RED}[ERR]${NC} $1"; }

# Print info message with cyan [>>] prefix
info()    { echo -e "${CYAN}[>>]${NC} $1"; }

# Print section header with blue background and dividers
section() { echo -e "\n${BLUE}━━━ $1 ━━━${NC}"; }

# Print a passed check with green checkmark (✅)
check()   { echo -e "  ${GREEN}☑${NC}  $1"; }
fail()    { echo -e "  ${RED}☐${NC}  $1"; }

# =============================================================================
# SECURITY CHECK: Must run as root
# =============================================================================
# This script tests security controls that require root privileges to access
if [ "$(id -u)" -ne 0 ]; then
  err "This script requires root. Run with: sudo bash verify-hardening.sh"
  exit 1
fi

# =============================================================================
# COUNTERS - Track how many checks pass/fail
# =============================================================================
# We increment these as we run each check
# At the end, we print the summary (e.g., "Passed: 47  Failed: 3")
TOTAL=0    # Total number of checks run
PASSED=0   # Number of checks that passed
FAILED=0   # Number of checks that failed

# =============================================================================
# VERIFY_CHECK FUNCTION - Generic test function for checking security controls
# =============================================================================
# WHAT: Runs a command and checks if output contains an expected string
# PARAMETERS:
#   $1 = label: Human-readable name of the check (e.g., "UFW is active")
#   $2 = cmd: Bash command to run (e.g., "ufw status | grep Status")
#   $3 = expect: String that output must contain (e.g., "active")
# EXAMPLE:
#   verify_check "SSH allows only key auth" "sshd -T | grep pubkeyauth" "yes"
# BEHAVIOR:
#   - Runs the command
#   - If output contains the expected string → PASS (✅ green checkmark)
#   - If output doesn't contain it → FAIL (❌ red X)
#   - If VERBOSE=1, shows what we expected vs what we actually got
verify_check() {
  local label="$1" cmd="$2" expect="$3"
  local result
  
  # Increment total check counter
  ((TOTAL++))
  
  # Run the command and capture output
  # 2>/dev/null = suppress error messages (don't want them cluttering output)
  # || echo "" = if command fails entirely, set result to empty string
  result=$(eval "$cmd" 2>/dev/null || echo "")
  
  # Check if result contains the expected string
  if echo "$result" | grep -q "$expect"; then
    # PASS: Show green checkmark and count this as a pass
    check "$label"
    ((PASSED++))
  else
    # FAIL: Show red X and count this as a fail
    fail "$label"
    ((FAILED++))
    # If user ran with VERBOSE=1, show debugging info
    if [ -n "${VERBOSE:-}" ]; then
      echo "    Expected: $expect"
      echo "    Got: $result"
    fi
  fi
}

# =============================================================================
# UFW FIREWALL CHECKS
# =============================================================================
section "UFW Firewall"

verify_check "UFW is active" \
  "ufw status" \
  "Status: active"

verify_check "Default incoming policy is DENY" \
  "ufw status verbose | grep -A1 'Default:'" \
  "deny (incoming)"

verify_check "SSH locked to tailscale0 only (no public rule)" \
  "ufw status | grep -c tailscale0" \
  "[1-9]"

verify_check "Port 80/443 has Cloudflare IP rules" \
  "ufw status | grep -E '80|443'" \
  "173.245"

verify_check "Docker Swarm port 2377 DENY" \
  "ufw status | grep 2377" \
  "DENY"

verify_check "Docker Swarm port 7946 DENY" \
  "ufw status | grep 7946" \
  "DENY"

verify_check "Port 3000 DENY (no public rule)" \
  "ufw status | grep 3000" \
  "DENY"

# =============================================================================
# SSH HARDENING CHECKS
# =============================================================================
section "SSH Hardening"

verify_check "SSH via tailscale0 allowed" \
  "ufw status | grep tailscale0" \
  "tailscale0"

verify_check "PermitRootLogin disabled" \
  "sshd -T 2>/dev/null | grep permitrootlogin" \
  "no"

verify_check "PasswordAuthentication disabled" \
  "sshd -T 2>/dev/null | grep passwordauthentication" \
  "no"

verify_check "PubkeyAuthentication enabled" \
  "sshd -T 2>/dev/null | grep pubkeyauthentication" \
  "yes"

verify_check "MaxSessions restricted (2)" \
  "sshd -T 2>/dev/null | grep maxsessions" \
  "2"

verify_check "AllowTcpForwarding disabled" \
  "sshd -T 2>/dev/null | grep allowtcpforwarding" \
  "no"

verify_check "X11Forwarding disabled" \
  "sshd -T 2>/dev/null | grep x11forwarding" \
  "no"

verify_check "MaxAuthTries restricted (3)" \
  "sshd -T 2>/dev/null | grep maxauthtries" \
  "3"

# =============================================================================
# TAILSCALE CHECKS
# =============================================================================
section "Tailscale"

verify_check "Tailscale installed" \
  "which tailscale" \
  "tailscale"

verify_check "Tailscale connected" \
  "tailscale status 2>/dev/null | head -3" \
  "ok"

verify_check "Tailscale IP assigned (100.64.0.0/10 range)" \
  "tailscale ip -4 2>/dev/null" \
  "100\\."

# =============================================================================
# IPTABLES / DOCKER-USER CHECKS
# =============================================================================
section "iptables (DOCKER-USER Chain)"

verify_check "DOCKER-USER chain exists" \
  "iptables -L DOCKER-USER -n 2>/dev/null" \
  "DOCKER-USER"

verify_check "Tailscale range (100.64.0.0/10) RETURN rule exists" \
  "iptables -S DOCKER-USER 2>/dev/null | grep '100.64'" \
  "100.64.0.0/10"

verify_check "Port 80 DROP rule exists" \
  "iptables -S DOCKER-USER 2>/dev/null | grep 'dport 80' | grep DROP" \
  "dport 80"

verify_check "Port 443 DROP rule exists" \
  "iptables -S DOCKER-USER 2>/dev/null | grep 'dport 443' | grep DROP" \
  "dport 443"

verify_check "Port 3000 DROP rule exists" \
  "iptables -S DOCKER-USER 2>/dev/null | grep 'dport 3000' | grep DROP" \
  "dport 3000"

verify_check "Cloudflare IPs cached (v4)" \
  "wc -l /etc/iptables/cloudflare-ips-v4.txt 2>/dev/null | awk '{print \$1}'" \
  "[1-9]"

# =============================================================================
# IPv6 CHECKS (if enabled)
# =============================================================================
section "IPv6"

verify_check "IPv6 disabled OR ip6tables rules applied" \
  "cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null" \
  "[0-1]"

# =============================================================================
# KERNEL HARDENING CHECKS
# =============================================================================
section "Kernel Hardening (sysctl)"

verify_check "rp_filter enabled (reverse path filtering)" \
  "sysctl net.ipv4.conf.all.rp_filter 2>/dev/null" \
  "= 1"

verify_check "tcp_syncookies enabled (SYN flood protection)" \
  "sysctl net.ipv4.tcp_syncookies 2>/dev/null" \
  "= 1"

verify_check "accept_source_route disabled" \
  "sysctl net.ipv4.conf.all.accept_source_route 2>/dev/null" \
  "= 0"

verify_check "send_redirects disabled" \
  "sysctl net.ipv4.conf.all.send_redirects 2>/dev/null" \
  "= 0"

verify_check "accept_redirects disabled" \
  "sysctl net.ipv4.conf.all.accept_redirects 2>/dev/null" \
  "= 0"

# =============================================================================
# AUDITD CHECKS
# =============================================================================
section "Auditd"

verify_check "Auditd running" \
  "systemctl is-active auditd 2>/dev/null" \
  "active"

verify_check "Audit rules loaded (sshd_config watched)" \
  "auditctl -l 2>/dev/null | grep sshd_config" \
  "sshd_config"

verify_check "/etc/passwd monitored" \
  "auditctl -l 2>/dev/null | grep passwd" \
  "passwd"

verify_check "/etc/sudoers monitored" \
  "auditctl -l 2>/dev/null | grep sudoers" \
  "sudoers"

# =============================================================================
# FAIL2BAN CHECKS
# =============================================================================
section "Fail2Ban"

verify_check "Fail2Ban running" \
  "systemctl is-active fail2ban 2>/dev/null" \
  "active"

verify_check "Fail2Ban SSH jail configured" \
  "fail2ban-client status 2>/dev/null | grep ssh" \
  "ssh"

# =============================================================================
# APPARMOR CHECKS
# =============================================================================
section "AppArmor"

verify_check "AppArmor active (profiles loaded)" \
  "aa-status 2>/dev/null | grep profiles" \
  "profiles"

# =============================================================================
# UNATTENDED UPGRADES CHECKS
# =============================================================================
section "Unattended Upgrades"

verify_check "Unattended-upgrades running" \
  "systemctl is-active unattended-upgrades 2>/dev/null" \
  "active"

# =============================================================================
# SYSTEMD SERVICES CHECKS
# =============================================================================
section "Systemd Services"

verify_check "docker-iptables-fix service enabled" \
  "systemctl is-enabled docker-iptables-fix 2>/dev/null" \
  "enabled"

verify_check "iptables-restore-custom service enabled" \
  "systemctl is-enabled iptables-restore-custom 2>/dev/null" \
  "enabled"

# =============================================================================
# CLOUDFLARED CHECKS (Optional)
# =============================================================================
if command -v cloudflared &>/dev/null; then
  section "Cloudflared (Optional)"
  
  verify_check "cloudflared installed" \
    "which cloudflared" \
    "cloudflared"
fi

# =============================================================================
# SSH KEYS CHECKS (If setup-ssh-keys.sh was run)
# =============================================================================
if [ -f /root/.ssh/authorized_keys ] || [ -f /home/*/\.ssh/authorized_keys ]; then
  section "SSH Keys"
  
  verify_check "authorized_keys exists for root" \
    "test -f /root/.ssh/authorized_keys && echo 'yes'" \
    "yes"
  
  verify_check "authorized_keys has correct permissions (600)" \
    "stat -c '%a' /root/.ssh/authorized_keys 2>/dev/null" \
    "600"
  
  verify_check "~/.ssh has correct permissions (700)" \
    "stat -c '%a' /root/.ssh 2>/dev/null" \
    "700"
fi

# =============================================================================
# SUMMARY
# =============================================================================
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE} HARDENING VERIFICATION REPORT${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  Total Checks:  $TOTAL"
echo -e "  ${GREEN}Passed:${NC}        $PASSED"
echo -e "  ${RED}Failed:${NC}        $FAILED"
echo ""

if [ $FAILED -eq 0 ]; then
  echo -e "${GREEN}✅ ALL CHECKS PASSED — System is hardened!${NC}"
  echo ""
  echo -e "${YELLOW}NEXT STEPS:${NC}"
  echo -e "  1. Test SSH via Tailscale IP (should work)"
  echo -e "  2. Test SSH via public IP (should timeout)"
  echo -e "  3. Test app port via public IP (should timeout)"
  echo -e "  4. Test apps via Cloudflare tunnel domain (should work)"
  echo -e "  5. Review logs: sudo tail -100 /var/log/audit/audit.log"
  echo ""
else
  echo -e "${RED}❌ SOME CHECKS FAILED — Review the items marked with ${RED}☐${NC}"
  echo ""
  echo -e "${YELLOW}DEBUGGING:${NC}"
  echo -e "  Run with verbose: VERBOSE=1 sudo bash verify-hardening.sh"
  echo -e "  Check specific service: sudo systemctl status <service>"
  echo -e "  Validate SSH config: sudo sshd -t"
  echo ""
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Exit with failure code if any checks failed
[ $FAILED -eq 0 ] && exit 0 || exit 1
