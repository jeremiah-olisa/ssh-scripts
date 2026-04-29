#!/bin/bash
# =============================================================================
# verify-hardening.sh — Comprehensive Hardening Verification Checklist
# Version: 1.0.0
# Verifies all hardening steps from harden-node.sh + setup-ssh-keys.sh
# Usage: sudo bash verify-hardening.sh
# =============================================================================

set -euo pipefail

# === COLORS ===
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

log()     { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
err()     { echo -e "${RED}[ERR]${NC} $1"; }
info()    { echo -e "${CYAN}[>>]${NC} $1"; }
section() { echo -e "\n${BLUE}━━━ $1 ━━━${NC}"; }
check()   { echo -e "  ${GREEN}☑${NC}  $1"; }
fail()    { echo -e "  ${RED}☐${NC}  $1"; }

# === ROOT CHECK ===
[ "$(id -u)" -ne 0 ] && err "Run as root: sudo bash verify-hardening.sh"

# === COUNTERS ===
TOTAL=0; PASSED=0; FAILED=0

# === TEST FUNCTION ===
verify_check() {
  local label="$1" cmd="$2" expect="$3"
  local result
  
  ((TOTAL++))
  result=$(eval "$cmd" 2>/dev/null || echo "")
  
  if echo "$result" | grep -q "$expect"; then
    check "$label"
    ((PASSED++))
  else
    fail "$label"
    ((FAILED++))
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
  "sudo ufw status" \
  "Status: active"

verify_check "Default incoming policy is DENY" \
  "sudo ufw status verbose | grep -A1 'Default:'" \
  "deny (incoming)"

verify_check "SSH locked to tailscale0 only (no public rule)" \
  "sudo ufw status | grep -v tailscale0 | grep -i ssh" \
  "^$"

verify_check "Port 80/443 has Cloudflare IP rules" \
  "sudo ufw status | grep -E '80|443'" \
  "173.245"

verify_check "Docker Swarm port 2377 DENY" \
  "sudo ufw status | grep 2377" \
  "DENY"

verify_check "Docker Swarm port 7946 DENY" \
  "sudo ufw status | grep 7946" \
  "DENY"

verify_check "Port 3000 DENY (no public rule)" \
  "sudo ufw status | grep 3000" \
  "DENY"

# =============================================================================
# SSH HARDENING CHECKS
# =============================================================================
section "SSH Hardening"

verify_check "SSH via tailscale0 allowed" \
  "sudo ufw status | grep tailscale0" \
  "tailscale0"

verify_check "PermitRootLogin disabled" \
  "sudo sshd -T | grep permitrootlogin" \
  "no"

verify_check "PasswordAuthentication disabled" \
  "sudo sshd -T | grep passwordauthentication" \
  "no"

verify_check "PubkeyAuthentication enabled" \
  "sudo sshd -T | grep pubkeyauthentication" \
  "yes"

verify_check "MaxSessions restricted (2)" \
  "sudo sshd -T | grep maxsessions" \
  "2"

verify_check "AllowTcpForwarding disabled" \
  "sudo sshd -T | grep allowtcpforwarding" \
  "no"

verify_check "X11Forwarding disabled" \
  "sudo sshd -T | grep x11forwarding" \
  "no"

verify_check "MaxAuthTries restricted (3)" \
  "sudo sshd -T | grep maxauthtries" \
  "3"

# =============================================================================
# TAILSCALE CHECKS
# =============================================================================
section "Tailscale"

verify_check "Tailscale installed" \
  "which tailscale" \
  "tailscale"

verify_check "Tailscale connected (has 100.x.x.x IP)" \
  "sudo tailscale status 2>/dev/null | grep -i 'ok\\|connected'" \
  "ok"

verify_check "Tailscale IP assigned (100.64.0.0/10 range)" \
  "sudo tailscale ip -4 2>/dev/null | grep -E '^100\\.'" \
  "100\\."

# =============================================================================
# IPTABLES / DOCKER-USER CHECKS
# =============================================================================
section "iptables (DOCKER-USER Chain)"

verify_check "DOCKER-USER chain exists" \
  "sudo iptables -L DOCKER-USER -n" \
  "DOCKER-USER"

verify_check "Tailscale range (100.64.0.0/10) RETURN rule exists" \
  "sudo iptables -S DOCKER-USER | grep '100.64'" \
  "100.64.0.0/10"

verify_check "Port 80 DROP rule exists" \
  "sudo iptables -S DOCKER-USER | grep 'dport 80' | grep DROP" \
  "dport 80"

verify_check "Port 443 DROP rule exists" \
  "sudo iptables -S DOCKER-USER | grep 'dport 443' | grep DROP" \
  "dport 443"

verify_check "Port 3000 DROP rule exists" \
  "sudo iptables -S DOCKER-USER | grep 'dport 3000' | grep DROP" \
  "dport 3000"

verify_check "Cloudflare IPs cached (v4)" \
  "wc -l /etc/iptables/cloudflare-ips-v4.txt 2>/dev/null | awk '{print \$1}'" \
  "[1-9]"

# =============================================================================
# IPv6 CHECKS (if enabled)
# =============================================================================
if [ "$(sysctl net.ipv6.conf.all.disable_ipv6 2>/dev/null | awk '{print $NF}')" == "0" ]; then
  section "IPv6 Hardening"
  
  verify_check "ip6tables DOCKER-USER chain exists (if IPv6 enabled)" \
    "sudo ip6tables -L DOCKER-USER -n 2>/dev/null" \
    "DOCKER-USER"
else
  section "IPv6"
  check "IPv6 disabled (IPv6 disable_ipv6=1)"
  ((PASSED++))
  ((TOTAL++))
fi

# =============================================================================
# KERNEL HARDENING CHECKS
# =============================================================================
section "Kernel Hardening (sysctl)"

verify_check "rp_filter enabled (reverse path filtering)" \
  "sudo sysctl net.ipv4.conf.all.rp_filter 2>/dev/null" \
  "= 1"

verify_check "tcp_syncookies enabled (SYN flood protection)" \
  "sudo sysctl net.ipv4.tcp_syncookies 2>/dev/null" \
  "= 1"

verify_check "accept_source_route disabled" \
  "sudo sysctl net.ipv4.conf.all.accept_source_route 2>/dev/null" \
  "= 0"

verify_check "send_redirects disabled" \
  "sudo sysctl net.ipv4.conf.all.send_redirects 2>/dev/null" \
  "= 0"

verify_check "accept_redirects disabled" \
  "sudo sysctl net.ipv4.conf.all.accept_redirects 2>/dev/null" \
  "= 0"

# =============================================================================
# AUDITD CHECKS
# =============================================================================
section "Auditd"

verify_check "Auditd running" \
  "sudo systemctl is-active auditd" \
  "active"

verify_check "Audit rules loaded (sshd_config watched)" \
  "sudo auditctl -l 2>/dev/null | grep sshd_config" \
  "sshd_config"

verify_check "/etc/passwd monitored" \
  "sudo auditctl -l 2>/dev/null | grep passwd" \
  "passwd"

verify_check "/etc/sudoers monitored" \
  "sudo auditctl -l 2>/dev/null | grep sudoers" \
  "sudoers"

# =============================================================================
# FAIL2BAN CHECKS
# =============================================================================
section "Fail2Ban"

verify_check "Fail2Ban running" \
  "sudo systemctl is-active fail2ban" \
  "active"

verify_check "Fail2Ban SSH jail enabled" \
  "sudo fail2ban-client status sshd 2>/dev/null | grep -i 'jail'" \
  "sshd"

# =============================================================================
# APPARMOR CHECKS
# =============================================================================
section "AppArmor"

verify_check "AppArmor active (profiles loaded)" \
  "sudo aa-status 2>/dev/null | grep profiles" \
  "profiles"

# =============================================================================
# UNATTENDED UPGRADES CHECKS
# =============================================================================
section "Unattended Upgrades"

verify_check "Unattended-upgrades running" \
  "sudo systemctl is-active unattended-upgrades" \
  "active"

verify_check "Auto-upgrade config present" \
  "cat /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null | grep 'Unattended-Upgrade'" \
  "Unattended-Upgrade"

# =============================================================================
# SYSTEMD SERVICES CHECKS
# =============================================================================
section "Systemd Services"

verify_check "docker-iptables-fix enabled" \
  "sudo systemctl is-enabled docker-iptables-fix 2>/dev/null" \
  "enabled"

verify_check "iptables-restore-custom enabled" \
  "sudo systemctl is-enabled iptables-restore-custom 2>/dev/null" \
  "enabled"

# =============================================================================
# CLOUDFLARED CHECKS (Optional)
# =============================================================================
if command -v cloudflared &>/dev/null; then
  section "Cloudflared (Optional)"
  
  verify_check "cloudflared installed" \
    "which cloudflared" \
    "cloudflared"
  
  if sudo systemctl is-active cloudflared &>/dev/null; then
    verify_check "Cloudflare tunnel running" \
      "sudo systemctl is-active cloudflared" \
      "active"
  else
    warn "cloudflared installed but not running (optional)"
  fi
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
