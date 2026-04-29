#!/bin/bash
# =============================================================================
# hardening-checklist.sh — Manual Hardening Verification Checklist
# =============================================================================
#
# WHAT THIS SCRIPT DOES:
#   Displays a comprehensive checklist of ALL hardening items with:
#     ✓ Exact commands to run for each check
#     ✓ Expected output for each command
#     ✓ Manual testing procedures
#     ✓ Common configuration files to review
#     ✓ Important security reminders
#
# WHY USE THIS:
#   While verify-hardening.sh automates testing, sometimes you need to:
#     • Understand what's being checked
#     • Run commands manually to see output
#     • Review configurations by hand
#     • Test from another machine (Mac)
#     • Deep-dive into specific security control
#
# USAGE:
#   # Display the full checklist
#   bash hardening-checklist.sh
#
#   Then manually run commands shown in the checklist
#
# STRUCTURE:
#   The checklist is organized by security layer:
#     1. UFW Firewall - host-level packet filtering
#     2. SSH - remote access security
#     3. Tailscale - VPN connectivity
#     4. Docker / App Ports - container traffic
#     5. Cloudflare - public access tunnel
#     6. System Hardening - kernel & services
#     7. Audit Logging - security event records
#
# TESTING FROM MAC:
#   This checklist also includes commands to run from your Mac to test:
#     • SSH public IP (should timeout)
#     • SSH Tailscale IP (should work)
#     • App ports via IP (should timeout)
#     • Apps via Cloudflare tunnel (should work)
#
# VERSION: 1.0.0 | Last Updated: 2026-04-29
# =============================================================================

set -euo pipefail

# === COLORS ===
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

section() { echo -e "\n${BLUE}━━━ $1 ━━━${NC}"; }
item()    { echo -e "  ${CYAN}[ ]${NC}  $1"; }
cmd()     { echo -e "      ${YELLOW}→${NC}  $1"; }

# =============================================================================
# MAIN CHECKLIST
# =============================================================================

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN} HARDENING VERIFICATION CHECKLIST${NC}"
echo -e "${GREEN} harden-node.sh v2.1.0 + setup-ssh-keys.sh v1.0.0${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# UFW FIREWALL
section "UFW Firewall"
item "Status is active"
cmd "sudo ufw status → look for 'Status: active'"

item "Default incoming policy is DENY"
cmd "sudo ufw status verbose | grep 'Default:' → should show 'deny (incoming)'"

item "SSH port has NO 'ALLOW Anywhere' rule (Tailscale only)"
cmd "sudo ufw status | grep -i ssh → should only show 'tailscale0' interface"

item "Port 80/443 → only Cloudflare IP ranges allowed"
cmd "sudo ufw status | grep -E '80|443' → should show '173.245.48.0/20', '103.21.244.0/22', etc."

item "Docker Swarm ports 2377/7946 → DENY"
cmd "sudo ufw status | grep -E '2377|7946' → should show 'DENY'"

item "Port 3000 → no public rule (app port protected)"
cmd "sudo ufw status | grep 3000 → should show 'DENY' or no public rule"

# SSH HARDENING
section "SSH Hardening"
item "SSH only allowed via tailscale0 interface"
cmd "sudo ufw status | grep tailscale0 → should show SSH rule"

item "PermitRootLogin disabled"
cmd "sudo sshd -T | grep permitrootlogin → should output 'permitrootlogin no'"

item "PasswordAuthentication disabled"
cmd "sudo sshd -T | grep passwordauthentication → should output 'passwordauthentication no'"

item "SSH on custom port (if not 22)"
cmd "sudo sshd -T | grep port → note the port number"

item "SSH via public IP times out (test from Mac)"
cmd "ssh user@<public-ip> -p 22 → should timeout or refuse connection"

item "SSH via Tailscale IP works (test from Mac)"
cmd "ssh -i ~/.ssh/id_rsa user@100.x.x.x → should connect successfully"

# TAILSCALE
section "Tailscale"
item "Installed on all nodes"
cmd "which tailscale → should show /usr/bin/tailscale"

item "All nodes connected and showing in tailscale status"
cmd "sudo tailscale status → should show 'ok' and list of nodes"

item "All nodes on same account (techcourtltd@)"
cmd "sudo tailscale account → should show account email"

item "Each node has a 100.x.x.x IP"
cmd "sudo tailscale ip -4 → should show IP like '100.64.x.x'"

# DOCKER / APP PORTS
section "Docker / App Ports"
item "All app ports blocked via iptables DOCKER-USER chain"
cmd "sudo iptables -S DOCKER-USER | grep DROP → should show DROP rules for 80, 443, 3000"

item "No app port reachable via public IP (test from Mac)"
cmd "curl http://<public-ip>:3000 → should timeout or refuse"
cmd "curl http://<public-ip>:3123 → should timeout or refuse"

item "Apps only reachable via Cloudflare tunnel domain"
cmd "curl https://your-app-domain.com → should load successfully"

item "Inter-node traffic uses Tailscale IPs (not public)"
cmd "docker logs <container> → look for 100.x.x.x in connection logs, NOT public IPs"

# CLOUDFLARE
section "Cloudflare"
item "Cloudflare tunnel running"
cmd "sudo cloudflared tunnel list → should show tunnel(s)"
cmd "sudo systemctl status cloudflared → should show 'active (running)'"

item "All public-facing apps have a tunnel route"
cmd "sudo cloudflared tunnel info → should list routes for each app"

item "Direct IP access to 80/443 times out (test from Mac)"
cmd "curl http://<public-ip> → should timeout"
cmd "curl https://<public-ip> → should timeout or SSL error"

item "Domains resolve and load correctly over HTTPS"
cmd "curl https://your-app-domain.com → should return 200 OK"

# SYSTEM HARDENING
section "System Hardening (per node)"
item "Kernel upgraded and rebooted"
cmd "uname -r → check kernel version"
cmd "uptime → check last reboot time"

item "Unattended security upgrades enabled"
cmd "sudo systemctl status unattended-upgrades → should show 'active (running)'"

item "Fail2Ban running"
cmd "sudo systemctl status fail2ban → should show 'active (running)'"
cmd "sudo fail2ban-client status sshd → should show 'jail' status"

item "AppArmor active"
cmd "sudo aa-status → should show 'X profiles loaded'"

item "No unnecessary packages installed"
cmd "apt list --installed | grep -E 'games|xfce|gnome' → should return nothing"

# AUDIT LOGGING
section "Audit Logging"
item "Auditd running and rules loaded"
cmd "sudo systemctl status auditd → should show 'active (running)'"
cmd "sudo auditctl -l | wc -l → should show many rules (>20)"

item "SSH config changes monitored"
cmd "sudo auditctl -l | grep sshd_config → should show audit rule"

item "/etc/passwd changes monitored"
cmd "sudo auditctl -l | grep passwd → should show audit rule"

item "/etc/sudoers changes monitored"
cmd "sudo auditctl -l | grep sudoers → should show audit rule"

# AUTOMATED VERIFICATION
echo ""
section "Automated Verification"
echo -e "${CYAN}To automatically verify all checks, run:${NC}"
echo ""
echo -e "  ${YELLOW}sudo bash verify-hardening.sh${NC}"
echo ""
echo -e "This will test all items above and show:"
echo -e "  ${GREEN}✅ Passed checks${NC}"
echo -e "  ${RED}❌ Failed checks${NC}"
echo ""

# TESTING INSTRUCTIONS
section "Manual Testing (from Mac)"
echo ""
echo -e "${CYAN}Test SSH access:${NC}"
echo "  # Should TIMEOUT (public IP is blocked)"
echo "  ssh user@<your-public-ip> -p 22"
echo ""
echo "  # Should WORK (Tailscale is allowed)"
echo "  ssh -i ~/.ssh/id_rsa user@100.x.x.x"
echo ""
echo -e "${CYAN}Test app port access:${NC}"
echo "  # Should TIMEOUT (blocked by iptables)"
echo "  curl http://<your-public-ip>:3000"
echo "  curl http://<your-public-ip>:3123"
echo ""
echo "  # Should WORK (via Cloudflare tunnel)"
echo "  curl https://your-app-domain.com"
echo ""
echo -e "${CYAN}Test Tailscale connectivity:${NC}"
echo "  ssh user@100.x.x.x → from any node to any node"
echo ""

# FILES TO REVIEW
section "Key Files to Review"
echo ""
echo -e "${CYAN}Firewall:${NC}"
echo "  /etc/default/ufw                       (UFW settings)"
echo "  /etc/ufw/rules.v4                      (UFW rules IPv4)"
echo "  /etc/ufw/rules.v6                      (UFW rules IPv6)"
echo ""
echo -e "${CYAN}iptables:${NC}"
echo "  /etc/iptables/apply-docker-rules.sh   (DOCKER-USER rules)"
echo "  /etc/iptables/cloudflare-ips-v4.txt   (Cloudflare IPs cached)"
echo ""
echo -e "${CYAN}SSH:${NC}"
echo "  /etc/ssh/sshd_config                   (Main SSH config)"
echo "  /etc/ssh/sshd_config.d/hardening.conf (Hardening settings)"
echo "  ~/.ssh/authorized_keys                 (Authorized keys)"
echo ""
echo -e "${CYAN}Kernel:${NC}"
echo "  /etc/sysctl.d/99-hardening.conf       (Kernel parameters)"
echo ""
echo -e "${CYAN}Audit:${NC}"
echo "  /etc/audit/rules.d/hardening.rules    (Audit rules)"
echo "  /var/log/audit/audit.log              (Audit log)"
echo ""
echo -e "${CYAN}Services:${NC}"
echo "  /etc/systemd/system/docker-iptables-fix.service"
echo "  /etc/systemd/system/iptables-restore-custom.service"
echo ""

# FINAL NOTES
section "Notes"
echo ""
echo -e "${YELLOW}⚠️  Important Reminders:${NC}"
echo ""
echo "  1. SSH is Tailscale-only by default"
echo "     → Connect via Tailscale VPN first"
echo "     → Or add manual UFW rule temporarily: sudo ufw allow from <your-ip> to any port 22"
echo ""
echo "  2. App ports (3000, 3123, etc.) are NOT directly accessible"
echo "     → Only reachable via Cloudflare tunnel domain"
echo "     → iptables DOCKER-USER chain blocks all direct access"
echo ""
echo "  3. Cloudflare tunnel is required for public access"
echo "     → Must be configured: sudo cloudflared service install <TOKEN>"
echo "     → DNS must point to Cloudflare tunnel IP"
echo ""
echo "  4. All changes are logged"
echo "     → UFW: /var/log/syslog"
echo "     → Audit: /var/log/audit/audit.log"
echo "     → SSH: /var/log/auth.log"
echo ""
echo -e "${YELLOW}✅ Review both checklists and test all connections!${NC}"
echo ""

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
