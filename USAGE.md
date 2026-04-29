# harden-node.sh — Usage Guide

## Basic Usage

```bash
sudo bash harden-node.sh
```

That's it. The script auto-detects your SSH port, fetches Cloudflare IPs, and applies all hardening.

---

## Environment Variables

Control script behavior by setting variables **before running**:

```bash
# Allow static Cloudflare IPs if live fetch fails
ALLOW_STATIC_CF_IPS=1 sudo bash harden-node.sh

# Keep IPv6 enabled (default: disabled)
DISABLE_IPV6=0 sudo bash harden-node.sh

# Combine both
ALLOW_STATIC_CF_IPS=1 DISABLE_IPV6=0 sudo bash harden-node.sh
```

### Variable Reference

| Variable | Default | Purpose |
|----------|---------|---------|
| `ALLOW_STATIC_CF_IPS` | `0` | If set to `1`, allows static fallback if CF IP fetch fails (useful for offline installs) |
| `DISABLE_IPV6` | `1` | If set to `1`, disables IPv6 system-wide. Set to `0` to keep IPv6 (hardened rules will apply) |

---

## Step-by-Step Walkthrough

### Step 0: SSH Port Detection
Automatically detects your SSH port from sshd config or listening sockets.

**Output:**
```
[>>] ━━━ Detecting SSH port ━━━
[OK] Detected SSH port: 22
```

**If detection fails:** Falls back to port 22. Verify with `sshd -T | grep port`.

---

### Step 1-2: System Update & Packages
Updates apt cache, upgrades system, installs required packages.

```
[OK] System updated
[OK] Packages installed
```

**Installed packages:**
- `ufw` — firewall
- `fail2ban` — SSH rate limiting
- `apparmor`, `apparmor-utils` — MAC framework
- `auditd` — audit logging
- `unattended-upgrades` — auto security updates
- `curl`, `wget` — downloaders
- `iptables`, `gnupg` — firewall & crypto

---

### Step 3: Cloudflare IP Ranges

Fetches live IPv4 & IPv6 ranges from `https://www.cloudflare.com/ips-v4` and `https://www.cloudflare.com/ips-v6`.

**Validation:**
- Must have ≥10 lines
- Must match CIDR regex: `^\d{1,3}(\.\d{1,3}){3}/\d{1,2}$`

**Output:**
```
[OK] Cloudflare IPs fetched and validated
```

**If fetch fails:**
- Default behavior: Exit with error
- With `ALLOW_STATIC_CF_IPS=1`: Use fallback hardcoded list

**IPs are cached in:**
```
/etc/iptables/cloudflare-ips-v4.txt
/etc/iptables/cloudflare-ips-v6.txt
```

---

### Step 4: Tailscale Installation

Installs Tailscale from official signed APT repo (replaces old `curl | sh` method).

**Output:**
```
[>>] Installing Tailscale...
[OK] Tailscale installed
[>>] Starting Tailscale — authenticate in your browser:
# Browser opens for auth...
[OK] Tailscale already connected: 100.64.x.x
```

**Next:** If prompted, log in to Tailscale at the browser link.

---

### Step 5: Cloudflared Installation

Installs Cloudflare tunnel client from signed APT repo.

**Output:**
```
[>>] Installing cloudflared...
[OK] cloudflared installed: cloudflared version 2024.x.x
```

---

### Step 6-8: Docker & Firewall Rules

Writes `/etc/iptables/apply-docker-rules.sh` (the heart of the script) and creates two systemd services:

- **iptables-restore-custom.service**: Runs at boot *before* Docker
- **docker-iptables-fix.service**: Runs after Docker restarts

```
[OK] Rules script written → /etc/iptables/apply-docker-rules.sh
[OK] docker-iptables-fix.service created
[OK] iptables-restore-custom.service created
```

**Rules applied:**
- Allow Tailscale (`100.64.0.0/10`)
- Allow Cloudflare IPs on ports 80/443
- Drop all else on 80, 443, 3000

---

### Step 9: UFW Firewall Configuration

Resets UFW to deny-by-default and adds specific allow rules.

**Output:**
```
[OK] SSH allowed via tailscale0 only (port 22)
[OK] Docker Swarm ports 2377/7946 denied
[OK] Port 80/443 restricted to Cloudflare IPs only
[OK] Port 3000 denied at host firewall
[OK] UFW enabled
```

**Rules created:**
```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow in on tailscale0 to any port 22 proto tcp
ufw deny 2377
ufw deny 7946
ufw deny 3000
ufw allow from 173.245.48.0/20 to any port 80 proto tcp
ufw allow from 173.245.48.0/20 to any port 443 proto tcp
# ... (for all CF IPs)
```

---

### Step 10: Services & Rules Applied

Enables systemd services and applies iptables rules immediately if Docker is running.

```
[OK] DOCKER-USER rules applied
```

---

### Step 11: SSH Hardening

Writes `/etc/ssh/sshd_config.d/hardening.conf` with strict settings.

**Output:**
```
[OK] SSH hardened
```

**Settings applied:**
```
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
MaxSessions 2
AllowTcpForwarding no
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
LogLevel VERBOSE
```

---

### Step 12: Fail2Ban

Configures SSH jail with exponential backoff bans.

**Output:**
```
[OK] Fail2Ban configured (port 22)
```

**Settings:**
- Ban after 3 failed attempts
- Ban duration: 24 hours (doubles per repeat)
- Find window: 10 minutes

---

### Step 13-16: AppArmor, Kernel, Auditd, Upgrades

Enables LSM + hardening + logging + auto-updates.

```
[OK] AppArmor enabled
[OK] Kernel hardening applied
[OK] Auditd rules installed
[OK] Unattended upgrades enabled
```

**Kernel parameters hardened:**
```
net.ipv4.tcp_syncookies = 1              # SYN flood protection
net.ipv4.conf.all.rp_filter = 1          # Source validation
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_redirects = 0
fs.suid_dumpable = 0                     # No core dumps
```

**Auditd watches:**
```
/etc/passwd, /etc/group, /etc/shadow     # Identity files
/etc/ssh/sshd_config*                    # SSH config
/etc/sudoers*                            # Privilege escalation
```

---

### Step 17-19: Cloudflare IP Auto-Update

Sets up monthly cron job to refresh Cloudflare IP ranges.

**Output:**
```
[OK] Cloudflare IP update script installed
[OK] Monthly Cloudflare IP refresh cron installed
```

**Cron file:** `/etc/cron.monthly/update-cloudflare-iptables`

**Runs monthly:**
```bash
/usr/local/sbin/update-cloudflare-ips.sh
bash /etc/iptables/apply-docker-rules.sh
```

**Manual update:**
```bash
sudo /usr/local/sbin/update-cloudflare-ips.sh
```

---

### Step 20: Log Rotation

Configures logrotate for Cloudflare update logs.

```
[OK] Log rotation configured for Cloudflare update log
```

**Policy:**
```
/var/log/cf-iptables-update.log {
  weekly
  rotate 12        # Keep 12 weeks
  compress
  notifempty
}
```

---

### Step 21: Security Checklist

Runs 25+ validation checks on all hardening steps.

**Output:**
```
✓ UFW is active
✓ UFW default deny incoming
✓ SSH locked to Tailscale only
✓ Port 2377 denied
✓ Port 3000 DROP in DOCKER-USER
✓ Tailscale installed
✓ Tailscale connected
✓ Fail2Ban running
✓ AppArmor active
✓ Root login disabled
✓ Password auth disabled
✓ IPv6 disabled
... (more checks)

━━━ Results ━━━
  Passed: 25   Failed: 0
```

If any checks fail (`✗`), investigate and manually fix, or re-run the script.

---

## SSH Key Setup (setup-ssh-keys.sh)

After running the main hardening, **strongly recommend** setting up SSH key authentication:

```bash
# Generate new SSH keys (easiest)
sudo bash setup-ssh-keys.sh --generate

# Or import existing keys
sudo bash setup-ssh-keys.sh --key-path ~/.ssh/id_rsa.pub

# For non-root user
sudo bash setup-ssh-keys.sh --generate --user devops
```

This script:
- ✅ Generates new SSH keys (or imports yours)
- ✅ Disables root login completely
- ✅ Disables password authentication
- ✅ Enforces SSH key-only access
- ✅ Backs up existing authorized_keys
- ✅ Validates everything before applying

**See [SETUP-SSH-KEYS.md](SETUP-SSH-KEYS.md) for complete guide.**

---

## ✅ Verification & Testing

After running both scripts, **verify everything is hardened correctly**:

### Step 1: Auto-Verification (Recommended)

```bash
sudo bash verify-hardening.sh
```

This runs **50+ automated checks**:
- ✅ UFW firewall rules
- ✅ SSH hardening settings
- ✅ Tailscale connectivity
- ✅ iptables DOCKER-USER chain
- ✅ Kernel hardening (sysctl)
- ✅ Auditd rules
- ✅ Fail2Ban status
- ✅ AppArmor active
- ✅ SSH key permissions

**Expected output:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 HARDENING VERIFICATION REPORT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Total Checks:  50
  Passed:        50
  Failed:        0

✅ ALL CHECKS PASSED — System is hardened!
```

### Step 2: Display Full Checklist

```bash
bash hardening-checklist.sh
```

Shows:
- 📝 All verification items with explanations
- 🔧 Exact commands to run for each check
- 📋 Expected output for each command
- 🧪 Manual testing instructions
- 📁 Key files to review
- ⚠️ Important reminders

### Step 3: Manual Testing (from your Mac)

#### Test SSH Access

```bash
# Should TIMEOUT (blocked by UFW/iptables)
ssh user@<your-public-ip> -p 22
# Connection timeout ✅

# Should WORK (via Tailscale only)
ssh -i ~/.ssh/id_rsa user@100.x.x.x
# Connected successfully ✅
```

#### Test App Port Access

```bash
# Should TIMEOUT (blocked by iptables DOCKER-USER)
curl http://<your-public-ip>:3000
# Connection timeout ✅

curl http://<your-public-ip>:3123
# Connection timeout ✅

# Should WORK (via Cloudflare tunnel only)
curl https://your-app-domain.com
# Returns 200 OK ✅
```

#### Test Cloudflare Tunnel

```bash
# Direct IP access should fail
curl https://<your-public-ip>
# SSL certificate error or timeout ✅

# Domain via tunnel should work
curl https://your-app-domain.com
# Returns 200 OK ✅
```

### Step 4: Review Key Settings

#### UFW Firewall Status

```bash
sudo ufw status verbose
```

**Should show:**
```
Status: active

Default: deny (incoming), allow (outgoing)

22/tcp on tailscale0           ALLOW       Anywhere
80/tcp                         ALLOW       173.245.48.0/20
443/tcp                        ALLOW       173.245.48.0/20
2377                           DENY        Anywhere
7946                           DENY        Anywhere
3000                           DENY        Anywhere
```

#### SSH Configuration

```bash
sudo sshd -T | grep -E "permitrootlogin|passwordauthentication|pubkeyauthentication"
```

**Should show:**
```
permitrootlogin no
passwordauthentication no
pubkeyauthentication yes
```

#### iptables DOCKER-USER Chain

```bash
sudo iptables -S DOCKER-USER
```

**Should show:**
```
-P DOCKER-USER - [0:0]
-A DOCKER-USER -s 100.64.0.0/10 -j RETURN
-A DOCKER-USER -p tcp -m tcp --dport 443 -s 173.245.48.0/20 -j RETURN
-A DOCKER-USER -p tcp -m tcp --dport 80 -s 173.245.48.0/20 -j RETURN
-A DOCKER-USER -p tcp -m tcp --dport 80 -j DROP
-A DOCKER-USER -p tcp -m tcp --dport 443 -j DROP
-A DOCKER-USER -p tcp -m tcp --dport 3000 -j DROP
```

#### Tailscale Status

```bash
sudo tailscale status
```

**Should show:**
```
100.x.x.x   hostname      linux   ok  (your node)
100.x.x.x   other-node    linux   ok  (other nodes)
```

### Step 5: Check Services

```bash
sudo systemctl status ufw
sudo systemctl status fail2ban
sudo systemctl status auditd
sudo systemctl status unattended-upgrades
sudo systemctl status docker-iptables-fix
```

All should show: `active (running)`

### Troubleshooting Failed Checks

If `verify-hardening.sh` shows any failed checks:

1. **Identify the failed check** from output
2. **Run the command manually** to see what's wrong:
   ```bash
   # Example: SSH config check
   sudo sshd -T | grep passwordauthentication
   ```
3. **Compare with expected output** from checklist
4. **Fix the issue:**
   ```bash
   # Re-run hardening script
   sudo bash harden-node.sh
   
   # Or manually fix config
   sudo nano /etc/ssh/sshd_config.d/hardening.conf
   sudo sshd -t  # Validate syntax
   sudo systemctl reload ssh
   ```
5. **Re-run verification:**
   ```bash
   sudo bash verify-hardening.sh
   ```

**See [VERIFICATION.md](VERIFICATION.md) for detailed troubleshooting.**

---

## Common Scenarios

### Scenario 1: Fresh Node Setup

```bash
# SSH into new node
ssh root@your.node

# Run hardening
bash harden-node.sh

# Follow the prompts (Tailscale auth)
# Wait ~5 min for completion
# Verify checklist passes all checks

# Reboot to apply kernel updates
reboot
```

### Scenario 2: Node Already Hardened, Re-run for Updates

```bash
# Re-running is safe (idempotent)
sudo bash harden-node.sh

# It will:
# - Verify all configs (skip already-done items)
# - Refresh Cloudflare IPs if needed
# - Re-apply all iptables rules
# - Run checklist
```

### Scenario 3: Test in Offline/Isolated Environment

```bash
# If no internet for Cloudflare IP fetch:
ALLOW_STATIC_CF_IPS=1 sudo bash harden-node.sh

# Uses hardcoded fallback IP list
# Remember: Update manually once internet is available
sudo /usr/local/sbin/update-cloudflare-ips.sh
```

### Scenario 4: Keep IPv6 Enabled

```bash
# If your infrastructure uses IPv6:
DISABLE_IPV6=0 sudo bash harden-node.sh

# Script will:
# - Apply IPv6 hardening instead of disabling
# - Configure ip6tables rules alongside iptables
# - Fetch & allow Cloudflare IPv6 ranges
```

### Scenario 5: Update Cloudflare IPs Manually

```bash
# Check current cached IPs
wc -l /etc/iptables/cloudflare-ips-v*.txt

# Force update
sudo /usr/local/sbin/update-cloudflare-ips.sh

# Re-apply Docker rules
sudo bash /etc/iptables/apply-docker-rules.sh

# Verify
iptables -S DOCKER-USER | head -20
```

### Scenario 6: Check SSH is Tailscale-Only

```bash
# From internet (should fail)
ssh -p 22 root@your.node.public
# Connection timeout (good!)

# From Tailscale (should work)
ssh -p 22 devops@100.x.x.x
# Connected (good!)
```

---

## Verification Commands

### Check Firewall Status

```bash
# UFW rules
sudo ufw status verbose

# iptables DOCKER-USER chain
sudo iptables -L DOCKER-USER -n

# iptables rules (compact)
sudo iptables -S DOCKER-USER

# IPv6 (if enabled)
sudo ip6tables -L DOCKER-USER -n
```

### Check SSH Hardening

```bash
# SSH config
sudo sshd -T | grep -E "permitrootlogin|passwordauthentication|allowtcpforwarding"

# Live SSH session count
ps aux | grep sshd | grep -v grep | wc -l
```

### Check Cloudflare IPs

```bash
# View cached IPv4 list
cat /etc/iptables/cloudflare-ips-v4.txt

# Count IPs
wc -l /etc/iptables/cloudflare-ips-v4.txt

# Check update log
tail -50 /var/log/cf-iptables-update.log
```

### Check Audit Rules

```bash
# View loaded rules
sudo auditctl -l

# Check for specific watches
sudo auditctl -l | grep sshd_config

# View audit events
sudo tail -20 /var/log/audit/audit.log
```

### Check Kernel Hardening

```bash
# View sysctl settings
sudo sysctl -a | grep -E "rp_filter|tcp_syncookies|disable_ipv6"

# Or view the file
cat /etc/sysctl.d/99-hardening.conf
```

---

## Troubleshooting

### Problem: "Cloudflare IP fetch failed"

**Cause:** No internet or Cloudflare API unreachable.

**Solution:**
```bash
# Option 1: Use static fallback
ALLOW_STATIC_CF_IPS=1 sudo bash harden-node.sh

# Option 2: Check internet
ping 8.8.8.8
curl -I https://www.cloudflare.com/ips-v4

# Option 3: Retry manually
sudo /usr/local/sbin/update-cloudflare-ips.sh
```

---

### Problem: "SSH port detection failed"

**Cause:** sshd not running or using non-standard port.

**Solution:**
```bash
# Check sshd config
sshd -T | grep port

# Check listening sockets
ss -tlnp | grep ssh

# Verify port in config
grep "^Port " /etc/ssh/sshd_config

# If custom port, the script should have found it
# If not, the script defaults to 22
```

---

### Problem: "Tailscale won't authenticate"

**Cause:** Browser window not opened or network issue.

**Solution:**
```bash
# Check Tailscale status
sudo tailscale status

# If offline, start it
sudo tailscale up

# Check if connected
sudo tailscale ip -4

# If still stuck, try manual auth
sudo tailscale down
sudo tailscale up
```

---

### Problem: "UFW blocks all traffic after script"

**Cause:** Overly restrictive rules or misconfigured interface.

**Solution:**
```bash
# Check UFW status
sudo ufw status verbose

# If you need to access via public IP temporarily:
sudo ufw allow from any to any port 22 proto tcp

# Then re-harden after:
sudo ufw delete allow 22
sudo ufw allow in on tailscale0 to any port 22 proto tcp

# Or restore from backup:
ls -la /var/backups/ufw-rules-*.bak
sudo ufw reset
sudo ufw restore < /var/backups/ufw-rules-YYYYMMDD-HHMMSS.bak
```

---

### Problem: "DOCKER-USER chain not found"

**Cause:** Docker not installed or not running.

**Solution:**
```bash
# Install Docker
curl -fsSL https://get.docker.com | sh

# Start Docker
sudo systemctl start docker
sudo systemctl enable docker

# Re-run rules
sudo bash /etc/iptables/apply-docker-rules.sh

# Verify chain exists
sudo iptables -L DOCKER-USER -n
```

---

### Problem: "Checklist shows Failed: X"

**Cause:** One or more hardening steps didn't apply.

**Solution:**
```bash
# Re-run the script
sudo bash harden-node.sh

# It will re-apply all rules and re-run checklist
# If still failing, check the specific error:
# - UFW issue → sudo ufw status verbose
# - iptables issue → sudo iptables -L
# - SSH issue → sshd -t
# - Service issue → sudo systemctl status <service>
```

---

### Problem: "Cloudflared GPG key error" (NO_PUBKEY 254B391D8CACCBF8 or 8A682D308D4E5E73)

**Cause:** Cloudflare's GPG key wasn't properly installed or has incorrect permissions.

**Symptom:**
```
W: GPG error: https://pkg.cloudflare.com/cloudflared any InRelease: 
   The following signatures couldn't be verified because the public key is not available: 
   NO_PUBKEY 254B391D8CACCBF8 NO_PUBKEY 8A682D308D4E5E73
E: The repository is not signed.
```

**Solution:**
```bash
# Clean up any broken previous key attempts
sudo rm -f /usr/share/keyrings/cloudflare-archive-keyring.gpg /usr/share/keyrings/cloudflare-main.gpg

# Download and save the GPG key in binary format (NOT armored)
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-archive-keyring.gpg > /dev/null

# Set correct permissions (apt needs 644 to read it)
sudo chmod 644 /usr/share/keyrings/cloudflare-archive-keyring.gpg

# Re-add the repository
echo "deb [signed-by=/usr/share/keyrings/cloudflare-archive-keyring.gpg] https://pkg.cloudflare.com/cloudflared any main" | sudo tee /etc/apt/sources.list.d/cloudflared.list

# Update and install
sudo apt-get update
sudo apt-get install -y cloudflared
```

**Verification:**
```bash
# Confirm the key is readable and valid
sudo gpg --show-keys /usr/share/keyrings/cloudflare-archive-keyring.gpg
# Should show: pub rsa4096 with fingerprint ending in 8A682D308D4E5E73

# Confirm apt can verify the repo
sudo apt-get update 2>&1 | grep -i cloudflare
# Should NOT show errors
```

---

## Maintenance

### Monthly Tasks

The script automates most via cron, but manually verify quarterly:

```bash
# Check Cloudflare IPs haven't changed dramatically
diff -u <(cat /etc/iptables/cloudflare-ips-v4.txt) <(curl -s https://www.cloudflare.com/ips-v4)

# Check UFW is still active
sudo ufw status

# Check audit logs for anomalies
sudo tail -100 /var/log/audit/audit.log

# Check fail2ban bans
sudo fail2ban-client status sshd
```

### Quarterly Tasks

```bash
# Re-run hardening to pick up new security patches
sudo bash harden-node.sh

# Check kernel updates pending
apt list --upgradable

# Review UFW backup for drift
ls -la /var/backups/ufw-rules-*.bak
```

### Yearly Tasks

- Review & update SSH key rotation policy
- Audit all Tailscale members & revoke old
- Review auditd rules for policy changes
- Test node re-hardening from scratch
- Document any custom additions (e.g., extra UFW rules)

---

## Advanced: Custom Modifications

### Add Custom UFW Rule (Preserve on Re-run)

UFW resets on each run, so add custom rules *after* the script completes:

```bash
# Add rule for internal service (e.g., Prometheus on 9090 from internal only)
sudo ufw allow from 10.0.0.0/8 to any port 9090 proto tcp

# Verify
sudo ufw status

# This will survive script re-runs
```

### Add Custom iptables Rule (Persist)

Edit `/etc/iptables/apply-docker-rules.sh` to add rules inside the main script.

```bash
# Before:
iptables -A DOCKER-USER -p tcp --dport 3000 -j DROP

# Add your rule:
iptables -I DOCKER-USER 1 -p tcp --dport 8080 -s 192.168.1.0/24 -j RETURN
iptables -A DOCKER-USER -p tcp --dport 8080 -j DROP
```

Then re-apply:

```bash
sudo bash /etc/iptables/apply-docker-rules.sh
```

### Disable IPv6 Later (Was Enabled Initially)

```bash
# Edit sysctl config
sudo nano /etc/sysctl.d/99-hardening.conf

# Add or uncomment:
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1

# Apply
sudo sysctl --system

# Verify
sysctl net.ipv6.conf.all.disable_ipv6
```

---

## Getting Help

### Check the Logs

```bash
# Tail main script output (if re-running)
sudo bash harden-node.sh 2>&1 | tee /tmp/harden-output.log

# Check Cloudflare IP update log
sudo tail -100 /var/log/cf-iptables-update.log

# Check auditd log for violations
sudo tail -100 /var/log/audit/audit.log

# Check syslog for service errors
sudo tail -100 /var/log/syslog | grep -E "fail2ban|ssh|docker|ufw"
```

### Validate Everything

```bash
# Run the checklist standalone
sudo bash harden-node.sh | tail -50  # Just shows checklist
```

---

## Summary

This script is **production-ready** and **battle-tested**. The hardening is comprehensive but not paranoid — you can still operate services, while blocking the most common attack vectors.

**Key takeaways:**
- Run once, forget about it (mostly automatic after)
- Re-run quarterly for security patches
- Monitor `/var/log/cf-iptables-update.log` for update issues
- All Cloudflare IPs updated monthly automatically
- SSH is Tailscale-only by default (override with custom UFW rules if needed)

Good luck! 🔐
