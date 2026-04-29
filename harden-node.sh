#!/bin/bash
# =============================================================================
# harden-node.sh — Full node security hardening script
# Version: 2.1.0
# Supports: Ubuntu 24.04 LTS
# Hardens UFW, iptables (survives Docker restarts), Tailscale, cloudflared
# Idempotent — safe to re-run at any time on any node
# Usage: sudo bash harden-node.sh
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
[ "$(id -u)" -ne 0 ] && err "Run as root: sudo bash harden-node.sh"

# === CONFIG ===
CLOUDFLARE_IPS_V4_URL="https://www.cloudflare.com/ips-v4"
CLOUDFLARE_IPS_V6_URL="https://www.cloudflare.com/ips-v6"
CF_IPS_DIR="/etc/iptables"
CF_IPS_V4_FILE="${CF_IPS_DIR}/cloudflare-ips-v4.txt"
CF_IPS_V6_FILE="${CF_IPS_DIR}/cloudflare-ips-v6.txt"
CF_IPS_MIN_LINES=10
DISABLE_IPV6=1

# === CLOUDFLARE IP RANGES (FALLBACK) ===
# Source: https://www.cloudflare.com/ips/
# Used only if ALLOW_STATIC_CF_IPS=1 and live fetch fails
CLOUDFLARE_IPS_V4_FALLBACK=(
  "173.245.48.0/20"
  "103.21.244.0/22"
  "103.22.200.0/22"
  "103.31.4.0/22"
  "141.101.64.0/18"
  "108.162.192.0/18"
  "190.93.240.0/20"
  "188.114.96.0/20"
  "197.234.240.0/22"
  "198.41.128.0/17"
  "162.158.0.0/15"
  "104.16.0.0/13"
  "104.24.0.0/14"
  "172.64.0.0/13"
  "131.0.72.0/22"
)

fetch_cloudflare_ips() {
  local tmp_v4 tmp_v6
  tmp_v4=$(mktemp)
  tmp_v6=$(mktemp)

  if ! curl -fsSL --proto '=https' --tlsv1.2 "$CLOUDFLARE_IPS_V4_URL" -o "$tmp_v4"; then
    rm -f "$tmp_v4" "$tmp_v6"
    return 1
  fi

  if ! curl -fsSL --proto '=https' --tlsv1.2 "$CLOUDFLARE_IPS_V6_URL" -o "$tmp_v6"; then
    rm -f "$tmp_v4" "$tmp_v6"
    return 1
  fi

  if [ "$(wc -l < "$tmp_v4")" -lt "$CF_IPS_MIN_LINES" ]; then
    rm -f "$tmp_v4" "$tmp_v6"
    return 1
  fi

  if ! grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}/[0-9]{1,2}$' "$tmp_v4"; then
    rm -f "$tmp_v4" "$tmp_v6"
    return 1
  fi

  if [ -s "$tmp_v6" ] && ! grep -Eq '^[0-9a-fA-F:]+/[0-9]{1,3}$' "$tmp_v6"; then
    rm -f "$tmp_v4" "$tmp_v6"
    return 1
  fi

  mkdir -p "$CF_IPS_DIR"
  mv "$tmp_v4" "$CF_IPS_V4_FILE"
  mv "$tmp_v6" "$CF_IPS_V6_FILE"
  return 0
}

# =============================================================================
# STEP 0: DETECT SSH PORT
# =============================================================================
section "Detecting SSH port"
SSH_PORT=$(sshd -T 2>/dev/null | grep "^port " | awk '{print $2}' | head -1)
if [ -z "$SSH_PORT" ]; then
  SSH_PORT=$(ss -tlnp | grep sshd | awk '{print $4}' | grep -oP ':\K[0-9]+' | head -1)
fi
if [ -z "$SSH_PORT" ]; then
  warn "Could not auto-detect SSH port. Using 22 as fallback."
  SSH_PORT=22
fi
log "Detected SSH port: $SSH_PORT"

# =============================================================================
# STEP 1: SYSTEM UPDATE
# =============================================================================
section "System update"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
log "System updated"

# =============================================================================
# STEP 2: INSTALL REQUIRED PACKAGES
# =============================================================================
section "Installing required packages"
apt-get install -y -qq \
  ufw fail2ban apparmor apparmor-utils auditd gnupg \
  unattended-upgrades curl wget iptables
log "Packages installed"

# =============================================================================
# STEP 3: FETCH CLOUDFLARE IP RANGES
# =============================================================================
section "Cloudflare IP ranges"

if fetch_cloudflare_ips; then
  log "Cloudflare IPs fetched and validated"
else
  if [ "${ALLOW_STATIC_CF_IPS:-0}" -eq 1 ]; then
    warn "Cloudflare IP fetch failed — using static fallback list"
    mkdir -p "$CF_IPS_DIR"
    printf "%s\n" "${CLOUDFLARE_IPS_V4_FALLBACK[@]}" > "$CF_IPS_V4_FILE"
    : > "$CF_IPS_V6_FILE"
  else
    err "Cloudflare IP fetch failed — aborting (set ALLOW_STATIC_CF_IPS=1 to override)"
  fi
fi

# =============================================================================
# STEP 4: INSTALL TAILSCALE (if not installed)
# =============================================================================
section "Tailscale"
if ! command -v tailscale &>/dev/null; then
  info "Installing Tailscale..."
  mkdir -p /usr/share/keyrings
  curl -fsSL --proto '=https' --tlsv1.2 https://pkgs.tailscale.com/stable/ubuntu/noble.gpg \
    | gpg --dearmor -o /usr/share/keyrings/tailscale-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] \
https://pkgs.tailscale.com/stable/ubuntu noble main" \
    | tee /etc/apt/sources.list.d/tailscale.list > /dev/null
  apt-get update -qq
  apt-get install -y -qq tailscale
  log "Tailscale installed"
else
  log "Tailscale already installed"
fi

if ! tailscale status &>/dev/null; then
  info "Starting Tailscale — authenticate in your browser:"
  tailscale up
else
  log "Tailscale already connected: $(tailscale ip -4)"
fi

TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "")
[ -z "$TAILSCALE_IP" ] && warn "Tailscale IP not available yet — SSH rules will use tailscale0 interface"

# =============================================================================
# STEP 5: INSTALL CLOUDFLARED (if not installed)
# =============================================================================
section "Cloudflared"
if ! command -v cloudflared &>/dev/null; then
  info "Installing cloudflared..."
  mkdir -p /usr/share/keyrings
  curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg \
    | tee /usr/share/keyrings/cloudflare-main.gpg > /dev/null
  echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] \
https://pkg.cloudflare.com/cloudflared any main" \
    | tee /etc/apt/sources.list.d/cloudflared.list > /dev/null
  apt-get update -qq
  apt-get install -y -qq cloudflared
  log "cloudflared installed"
else
  log "cloudflared already installed: $(cloudflared --version)"
fi

# =============================================================================
# STEP 6: WRITE THE DOCKER-USER RULES SCRIPT
# This is the single source of truth for all iptables rules.
# It is called:
#   - At boot via iptables-restore-custom.service (before Docker)
#   - After every Docker start/restart via docker-iptables-fix.service
#   - Monthly via cron to pick up new Cloudflare IP ranges
#   - Manually: sudo bash /etc/iptables/apply-docker-rules.sh
# NOTE: DOCKER-USER affects forwarded container traffic. UFW below covers host INPUT.
# =============================================================================
section "Writing DOCKER-USER rules script"

mkdir -p /etc/iptables

cat > /etc/iptables/apply-docker-rules.sh << 'RULES_SCRIPT'
#!/bin/bash
# =============================================================================
# apply-docker-rules.sh — DOCKER-USER iptables rules
# Safe to run multiple times (idempotent).
# =============================================================================

set -euo pipefail

CF_IPS_V4_FILE="/etc/iptables/cloudflare-ips-v4.txt"
CF_IPS_V6_FILE="/etc/iptables/cloudflare-ips-v6.txt"

CF_IPS_V4_FALLBACK=(
  "173.245.48.0/20" "103.21.244.0/22" "103.22.200.0/22"
  "103.31.4.0/22"   "141.101.64.0/18" "108.162.192.0/18"
  "190.93.240.0/20" "188.114.96.0/20" "197.234.240.0/22"
  "198.41.128.0/17" "162.158.0.0/15"  "104.16.0.0/13"
  "104.24.0.0/14"   "172.64.0.0/13"   "131.0.72.0/22"
)

if [ -s "$CF_IPS_V4_FILE" ]; then
  mapfile -t CF_IPS_V4 < "$CF_IPS_V4_FILE"
else
  echo "[!] Cloudflare v4 list missing — using fallback"
  CF_IPS_V4=("${CF_IPS_V4_FALLBACK[@]}")
fi

if [ -s "$CF_IPS_V6_FILE" ]; then
  mapfile -t CF_IPS_V6 < "$CF_IPS_V6_FILE"
else
  CF_IPS_V6=()
fi

# Wait for Docker to create the DOCKER-USER chain (up to 30s)
for i in $(seq 1 15); do
  iptables -L DOCKER-USER -n &>/dev/null && break
  echo "[>>] Waiting for DOCKER-USER chain... attempt $i/15"
  sleep 2
done

if ! iptables -L DOCKER-USER -n &>/dev/null; then
  echo "[!] DOCKER-USER chain not found — Docker may not be running"
  exit 0
fi

# --- Clean ALL previous custom rules (idempotent) ---
# Remove DROP rules for our ports
for port in 80 443 3000; do
  while iptables -D DOCKER-USER -p tcp --dport "$port" -j DROP 2>/dev/null; do :; done
done
# Remove Tailscale RETURN rule
while iptables -D DOCKER-USER -s 100.64.0.0/10 -j RETURN 2>/dev/null; do :; done
# Remove Cloudflare RETURN rules
for ip in "${CF_IPS_V4[@]}"; do
  for port in 80 443; do
    while iptables -D DOCKER-USER -p tcp --dport "$port" -s "$ip" -j RETURN 2>/dev/null; do :; done
  done
done

# --- Allow Tailscale range (100.64.0.0/10 covers all 100.x.x.x addresses) ---
iptables -I DOCKER-USER 1 -s 100.64.0.0/10 -j RETURN

# --- Allow all Cloudflare IP ranges for ports 80 and 443 ---
for ip in "${CF_IPS_V4[@]}"; do
  iptables -I DOCKER-USER 1 -p tcp --dport 443 -s "$ip" -j RETURN
  iptables -I DOCKER-USER 1 -p tcp --dport 80  -s "$ip" -j RETURN
done

# --- Drop everything else on 80, 443, 3000 ---
iptables -A DOCKER-USER -p tcp --dport 80   -j DROP
iptables -A DOCKER-USER -p tcp --dport 443  -j DROP
iptables -A DOCKER-USER -p tcp --dport 3000 -j DROP

# IPv6 rules (if Docker IPv6 is enabled)
if command -v ip6tables &>/dev/null && ip6tables -L DOCKER-USER -n &>/dev/null; then
  for port in 80 443 3000; do
    while ip6tables -D DOCKER-USER -p tcp --dport "$port" -j DROP 2>/dev/null; do :; done
  done
  while ip6tables -D DOCKER-USER -s fd7a:115c:a1e0::/48 -j RETURN 2>/dev/null; do :; done
  for ip in "${CF_IPS_V6[@]}"; do
    for port in 80 443; do
      while ip6tables -D DOCKER-USER -p tcp --dport "$port" -s "$ip" -j RETURN 2>/dev/null; do :; done
    done
  done

  ip6tables -I DOCKER-USER 1 -s fd7a:115c:a1e0::/48 -j RETURN
  for ip in "${CF_IPS_V6[@]}"; do
    ip6tables -I DOCKER-USER 1 -p tcp --dport 443 -s "$ip" -j RETURN
    ip6tables -I DOCKER-USER 1 -p tcp --dport 80  -s "$ip" -j RETURN
  done
  ip6tables -A DOCKER-USER -p tcp --dport 80   -j DROP
  ip6tables -A DOCKER-USER -p tcp --dport 443  -j DROP
  ip6tables -A DOCKER-USER -p tcp --dport 3000 -j DROP
fi

echo "[OK] DOCKER-USER rules applied at $(date)"
RULES_SCRIPT

chmod +x /etc/iptables/apply-docker-rules.sh
log "Rules script written → /etc/iptables/apply-docker-rules.sh"

# =============================================================================
# STEP 7: SYSTEMD SERVICE — fires AFTER Docker starts or restarts
# =============================================================================
section "Creating docker-iptables-fix.service"

cat > /etc/systemd/system/docker-iptables-fix.service << 'EOF'
[Unit]
Description=Re-apply DOCKER-USER iptables rules after Docker starts
After=docker.service
Requires=docker.service
BindsTo=docker.service

[Service]
Type=oneshot
ExecStart=/bin/bash /etc/iptables/apply-docker-rules.sh
RemainAfterExit=yes
Restart=on-failure
RestartSec=5
StartLimitBurst=3

[Install]
WantedBy=multi-user.target docker.service
EOF

log "docker-iptables-fix.service created"

# =============================================================================
# STEP 8: SYSTEMD SERVICE — fires at boot BEFORE Docker
# Ensures rules are in place before Docker rewrites chains on boot
# =============================================================================
section "Creating iptables-restore-custom.service"

cat > /etc/systemd/system/iptables-restore-custom.service << 'EOF'
[Unit]
Description=Apply iptables rules on boot before Docker starts
Before=network-pre.target docker.service
Wants=network-pre.target
DefaultDependencies=no

[Service]
Type=oneshot
ExecStart=/bin/bash /etc/iptables/apply-docker-rules.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

log "iptables-restore-custom.service created"

# =============================================================================
# STEP 9: CONFIGURE DOCKER DAEMON
# =============================================================================
section "Configuring Docker daemon"

if [ ! -f /etc/docker/daemon.json ]; then
  mkdir -p /etc/docker
  cat > /etc/docker/daemon.json << 'EOF'
{
  "iptables": true,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
  log "Docker daemon.json created"
else
  log "Docker daemon.json already exists — skipping"
fi

# =============================================================================
# STEP 10: UFW FIREWALL
# =============================================================================
section "Configuring UFW"

mkdir -p /var/backups
ufw status verbose > "/var/backups/ufw-rules-$(date +%Y%m%d-%H%M%S).bak" || true

if [ "$DISABLE_IPV6" -eq 1 ]; then
  if [ -f /etc/default/ufw ]; then
    sed -i.bak 's/^IPV6=yes/IPV6=no/' /etc/default/ufw
  fi
fi

ufw --force reset  > /dev/null
ufw default deny incoming  > /dev/null
ufw default allow outgoing > /dev/null
ufw default deny routed    > /dev/null

# SSH via Tailscale interface only
ufw allow in on tailscale0 to any port "$SSH_PORT" proto tcp > /dev/null
log "SSH allowed via tailscale0 only (port $SSH_PORT)"

# Deny Docker Swarm ports
ufw deny 2377 > /dev/null
ufw deny 7946 > /dev/null
log "Docker Swarm ports 2377/7946 denied"

# Cloudflare IPs only for 80/443 (host INPUT rules)
while read -r ip; do
  [ -z "$ip" ] && continue
  ufw allow from "$ip" to any port 80  proto tcp > /dev/null
  ufw allow from "$ip" to any port 443 proto tcp > /dev/null
done < "$CF_IPS_V4_FILE"
log "Port 80/443 restricted to Cloudflare IPs only"

# Explicitly deny 3000 at the host level
ufw deny 3000 > /dev/null
log "Port 3000 denied at host firewall"

ufw --force enable > /dev/null
log "UFW enabled"

# =============================================================================
# STEP 11: ENABLE SERVICES AND APPLY RULES NOW
# =============================================================================
section "Enabling services and applying rules"

systemctl daemon-reload
systemctl enable docker-iptables-fix          > /dev/null
systemctl enable iptables-restore-custom      > /dev/null

if systemctl is-active docker &>/dev/null; then
  bash /etc/iptables/apply-docker-rules.sh
  systemctl restart docker-iptables-fix 2>/dev/null || true
  log "DOCKER-USER rules applied"
else
  warn "Docker not running — rules will apply automatically when Docker starts"
fi

# =============================================================================
# STEP 12: SSH HARDENING
# =============================================================================
section "SSH hardening"

SSHD_CONF="/etc/ssh/sshd_config.d/hardening.conf"
if ! grep -q "PermitRootLogin no" "$SSHD_CONF" 2>/dev/null; then
  cat > "$SSHD_CONF" << EOF
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
KbdInteractiveAuthentication no
MaxAuthTries 3
MaxSessions 2
LoginGraceTime 30
X11Forwarding no
AllowTcpForwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
LogLevel VERBOSE
UseDNS no
EOF
  sshd -t && systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
  log "SSH hardened"
else
  log "SSH already hardened — skipping"
fi

# =============================================================================
# STEP 13: FAIL2BAN
# =============================================================================
section "Fail2Ban"

cat > /etc/fail2ban/jail.local << EOF
[sshd]
enabled = true
port = $SSH_PORT
filter = sshd
backend = systemd
maxretry = 3
bantime = 86400
findtime = 600
bantime.increment = true
bantime.factor = 2
EOF

systemctl enable fail2ban > /dev/null
systemctl restart fail2ban
log "Fail2Ban configured (port $SSH_PORT)"

# =============================================================================
# STEP 14: APPARMOR
# =============================================================================
section "AppArmor"
if aa-status &>/dev/null; then
  log "AppArmor already active"
else
  systemctl enable apparmor > /dev/null
  systemctl start apparmor
  log "AppArmor enabled"
fi

# =============================================================================
# STEP 15: KERNEL HARDENING (sysctl)
# =============================================================================
section "Kernel hardening"

cat > /etc/sysctl.d/99-hardening.conf << 'EOF'
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
fs.suid_dumpable = 0
EOF

if [ "$DISABLE_IPV6" -eq 1 ]; then
  cat >> /etc/sysctl.d/99-hardening.conf << 'EOF'
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF
fi

sysctl --system > /dev/null
log "Kernel hardening applied"

# =============================================================================
# STEP 16: AUDITD RULES
# =============================================================================
section "Auditd rules"

cat > /etc/audit/rules.d/hardening.rules << 'EOF'
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/ssh/sshd_config -p wa -k sshd_config
-w /etc/ssh/sshd_config.d/ -p wa -k sshd_config
-w /etc/sudoers -p wa -k sudoers
-w /etc/sudoers.d/ -p wa -k sudoers
-a always,exit -F arch=b64 -S execve -k exec_commands
EOF

augenrules --load > /dev/null
systemctl restart auditd
log "Auditd rules installed"

# =============================================================================
# STEP 17: UNATTENDED UPGRADES
# =============================================================================
section "Unattended security upgrades"

cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

systemctl enable unattended-upgrades > /dev/null
systemctl restart unattended-upgrades
log "Unattended upgrades enabled"

# =============================================================================
# STEP 18: CLOUDFLARE IP AUTO-UPDATE SCRIPT
# =============================================================================
section "Cloudflare IP update script"

cat > /usr/local/sbin/update-cloudflare-ips.sh << 'EOF'
#!/bin/bash
set -euo pipefail

CLOUDFLARE_IPS_V4_URL="https://www.cloudflare.com/ips-v4"
CLOUDFLARE_IPS_V6_URL="https://www.cloudflare.com/ips-v6"
CF_IPS_DIR="/etc/iptables"
CF_IPS_V4_FILE="${CF_IPS_DIR}/cloudflare-ips-v4.txt"
CF_IPS_V6_FILE="${CF_IPS_DIR}/cloudflare-ips-v6.txt"
CF_IPS_MIN_LINES=10

tmp_v4=$(mktemp)
tmp_v6=$(mktemp)

curl -fsSL --proto '=https' --tlsv1.2 "$CLOUDFLARE_IPS_V4_URL" -o "$tmp_v4"
curl -fsSL --proto '=https' --tlsv1.2 "$CLOUDFLARE_IPS_V6_URL" -o "$tmp_v6"

if [ "$(wc -l < "$tmp_v4")" -lt "$CF_IPS_MIN_LINES" ]; then
  echo "[ERR] Cloudflare v4 list too small"
  exit 1
fi

if ! grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}/[0-9]{1,2}$' "$tmp_v4"; then
  echo "[ERR] Cloudflare v4 list invalid"
  exit 1
fi

if [ -s "$tmp_v6" ] && ! grep -Eq '^[0-9a-fA-F:]+/[0-9]{1,3}$' "$tmp_v6"; then
  echo "[ERR] Cloudflare v6 list invalid"
  exit 1
fi

mkdir -p "$CF_IPS_DIR"
mv "$tmp_v4" "$CF_IPS_V4_FILE"
mv "$tmp_v6" "$CF_IPS_V6_FILE"

echo "[OK] Cloudflare IP lists updated"
EOF

chmod +x /usr/local/sbin/update-cloudflare-ips.sh
log "Cloudflare IP update script installed"

# =============================================================================
# STEP 19: MONTHLY CLOUDFLARE IP AUTO-UPDATE CRON
# =============================================================================
section "Cloudflare IP auto-update cron"

cat > /etc/cron.monthly/update-cloudflare-iptables << 'EOF'
#!/bin/bash
# Refreshes DOCKER-USER rules monthly in case Cloudflare updates their IPs
# To update CF IPs manually: /usr/local/sbin/update-cloudflare-ips.sh
/usr/local/sbin/update-cloudflare-ips.sh >> /var/log/cf-iptables-update.log 2>&1
bash /etc/iptables/apply-docker-rules.sh >> /var/log/cf-iptables-update.log 2>&1
EOF

chmod +x /etc/cron.monthly/update-cloudflare-iptables
log "Monthly Cloudflare IP refresh cron installed"

# =============================================================================
# STEP 20: LOG ROTATION
# =============================================================================
section "Log rotation"

cat > /etc/logrotate.d/cf-iptables-update << 'EOF'
/var/log/cf-iptables-update.log {
  weekly
  rotate 12
  compress
  missingok
  notifempty
  create 0640 root adm
}
EOF

log "Log rotation configured for Cloudflare update log"

# =============================================================================
# STEP 21: SECURITY CHECKLIST VERIFICATION
# =============================================================================
section "Running security checklist"

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

check "UFW is active"                        "ufw status"                               "Status: active"
check "UFW default deny incoming"            "ufw status verbose"                       "deny (incoming)"
check "SSH locked to Tailscale only"         "ufw status | grep $SSH_PORT"              "tailscale0"
check "Port 2377 denied"                     "ufw status | grep 2377"                   "DENY"
check "Port 7946 denied"                     "ufw status | grep 7946"                   "DENY"
check "Tailscale installed"                  "tailscale version"                        "tailscale"
check "Tailscale connected"                  "tailscale status"                         "100\."
check "cloudflared installed"                "cloudflared --version"                    "cloudflared"
check "Fail2Ban running"                     "systemctl is-active fail2ban"             "active"
check "AppArmor active"                      "aa-status"                                "profiles are loaded"
check "Unattended upgrades enabled"          "systemctl is-active unattended-upgrades"  "active"
check "Root login disabled"                  "sshd -T | grep permitrootlogin"           "no"
check "Password auth disabled"               "sshd -T | grep passwordauthentication"    "no"
check "docker-iptables-fix enabled"          "systemctl is-enabled docker-iptables-fix" "enabled"
check "iptables-restore-custom enabled"      "systemctl is-enabled iptables-restore-custom" "enabled"
check "DOCKER-USER chain exists"             "iptables -L DOCKER-USER -n"               "DOCKER-USER"
check "Port 3000 DROP in DOCKER-USER"        "iptables -S DOCKER-USER"                  "--dport 3000 -j DROP"
check "Monthly CF cron installed"            "ls /etc/cron.monthly/"                    "update-cloudflare-iptables"
check "Rules script exists"                  "ls /etc/iptables/"                        "apply-docker-rules.sh"
check "Cloudflare IPs cached"                "wc -l $CF_IPS_V4_FILE"                    "[1-9]"
check "Audit rules loaded"                   "auditctl -l"                             "sshd_config"

if [ "$DISABLE_IPV6" -eq 1 ]; then
  check "IPv6 disabled"                       "sysctl net.ipv6.conf.all.disable_ipv6"   "= 1"
fi

echo ""
echo -e "${BLUE}━━━ Results ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${GREEN}Passed: $PASS${NC}   ${RED}Failed: $FAIL${NC}"

# =============================================================================
# FINAL SUMMARY
# =============================================================================
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN} HARDENING COMPLETE — v2.1.0${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e " Hostname      : $(hostname)"
echo -e " SSH Port      : $SSH_PORT (Tailscale only)"
echo -e " Tailscale IP  : $(tailscale ip -4 2>/dev/null || echo 'not connected')"
echo ""
echo -e "${YELLOW} KEY FILES:${NC}"
echo -e "  /etc/iptables/apply-docker-rules.sh        ← edit to update rules"
echo -e "  /etc/iptables/cloudflare-ips-v4.txt"
echo -e "  /etc/iptables/cloudflare-ips-v6.txt"
echo -e "  /usr/local/sbin/update-cloudflare-ips.sh"
echo -e "  /etc/systemd/system/docker-iptables-fix.service"
echo -e "  /etc/systemd/system/iptables-restore-custom.service"
echo -e "  /etc/cron.monthly/update-cloudflare-iptables"
echo ""
echo -e "${YELLOW} NEXT STEPS:${NC}"
echo -e " 1. Set up Cloudflare tunnel:"
echo -e "    ${CYAN}sudo cloudflared service install <YOUR_TUNNEL_TOKEN>${NC}"
echo -e " 2. Test SSH via Tailscale from your Mac:"
echo -e "    ${CYAN}ssh -p $SSH_PORT devops@$(tailscale ip -4 2>/dev/null || echo '100.x.x.x')${NC}"
echo -e " 3. Reboot to apply pending kernel upgrades:"
echo -e "    ${CYAN}sudo reboot${NC}"
echo -e " 4. To manually re-apply Docker iptables rules:"
echo -e "    ${CYAN}sudo bash /etc/iptables/apply-docker-rules.sh${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"