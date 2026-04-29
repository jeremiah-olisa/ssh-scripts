# Verification Guide

Comprehensive guide for verifying your hardened Ubuntu nodes are secure and properly configured.

---

## Table of Contents

1. [Quick Verification](#quick-verification)
2. [Automated Checks](#automated-checks)
3. [Manual Checklist](#manual-checklist)
4. [Security Controls](#security-controls)
5. [Testing from Mac](#testing-from-mac)
6. [Common Issues](#common-issues)
7. [Maintenance](#maintenance)

---

## Quick Verification

### 1-Minute Check

```bash
# SSH into your node
ssh user@100.x.x.x

# Run auto-verification
sudo bash verify-hardening.sh

# Done!
```

**Look for:**
```
✅ ALL CHECKS PASSED — System is hardened!
```

---

## Automated Checks

### Run verify-hardening.sh

```bash
sudo bash verify-hardening.sh
```

This automated script tests **50+ security controls**:

#### ✅ UFW Firewall (7 checks)
- [ ] Status is active
- [ ] Default incoming policy is DENY
- [ ] SSH locked to tailscale0 only (no public rule)
- [ ] Port 80/443 allows only Cloudflare IPs
- [ ] Docker Swarm port 2377 DENY
- [ ] Docker Swarm port 7946 DENY
- [ ] Port 3000 DENY (no public access)

#### ✅ SSH Hardening (8 checks)
- [ ] SSH allowed via tailscale0 only
- [ ] PermitRootLogin disabled
- [ ] PasswordAuthentication disabled
- [ ] PubkeyAuthentication enabled
- [ ] MaxAuthTries 3 (not 6)
- [ ] MaxSessions 2 (not unlimited)
- [ ] AllowTcpForwarding disabled
- [ ] SSH key file permissions 0600/0700

#### ✅ Tailscale (4 checks)
- [ ] Installed
- [ ] Running/connected
- [ ] Correct IP range (100.x.x.x)
- [ ] All nodes connected in network

#### ✅ iptables (7 checks)
- [ ] DOCKER-USER chain exists
- [ ] Tailscale traffic (100.64.0.0/10) RETURN rule
- [ ] Cloudflare IPs RETURN rules
- [ ] Port 80 DROP rule
- [ ] Port 443 DROP rule
- [ ] Port 3000 DROP rule
- [ ] Cloudflare IPs cached to file

#### ✅ IPv6 Hardening (4 checks)
- [ ] IPv6 disabled globally OR
- [ ] ip6tables DOCKER-USER chain exists
- [ ] IPv6 source routing disabled
- [ ] IPv6 ICMP redirects disabled

#### ✅ Kernel Hardening (8 checks)
- [ ] SYN cookies enabled
- [ ] Source address validation enabled
- [ ] ICMP redirects disabled
- [ ] Source routing disabled
- [ ] ICMP echo broadcasts ignored
- [ ] Kexec disabled
- [ ] Magic sysrq disabled
- [ ] Core dumps disabled

#### ✅ Services (7 checks)
- [ ] Auditd running
- [ ] Fail2Ban running
- [ ] Unattended-upgrades running
- [ ] AppArmor active
- [ ] iptables-restore-custom.service enabled
- [ ] docker-iptables-fix.service enabled
- [ ] Cloudflare auto-update cron installed

#### ✅ Auditd Logging (5 checks)
- [ ] Auditd running
- [ ] /etc/passwd monitored
- [ ] /etc/group monitored
- [ ] /etc/ssh/sshd_config monitored
- [ ] /etc/sudoers monitored

---

## Manual Checklist

### Display the full checklist

```bash
bash hardening-checklist.sh
```

Then manually verify each item.

### UFW Firewall

#### 1. Status is active

```bash
sudo ufw status
```

**Expected output:**
```
Status: active
```

#### 2. Default incoming policy is DENY

```bash
sudo ufw status verbose | grep -i "default:"
```

**Expected output:**
```
Default: deny (incoming), allow (outgoing), reject (routed)
```

#### 3. SSH locked to Tailscale only

```bash
sudo ufw status | grep -i ssh
```

**Expected output (should show tailscale0):**
```
22/tcp on tailscale0        ALLOW       Anywhere
```

**Bad output (public SSH):**
```
22/tcp                      ALLOW       Anywhere
```

#### 4. Cloudflare IPs allowed on 80/443

```bash
sudo ufw status | grep -E '(80|443).*ALLOW'
```

**Expected output:**
```
80/tcp                      ALLOW       173.245.48.0/20
443/tcp                     ALLOW       173.245.48.0/20
80/tcp                      ALLOW       103.21.244.0/22
443/tcp                     ALLOW       103.21.244.0/22
... (more Cloudflare IP ranges)
```

#### 5. Docker Swarm ports blocked

```bash
sudo ufw status | grep -E '(2377|7946)'
```

**Expected output:**
```
2377                        DENY        Anywhere
7947                        DENY        Anywhere
```

#### 6. Port 3000 blocked

```bash
sudo ufw status | grep 3000
```

**Expected output:**
```
3000                        DENY        Anywhere
```

### SSH Hardening

#### 1. PermitRootLogin disabled

```bash
sudo sshd -T | grep permitrootlogin
```

**Expected output:**
```
permitrootlogin no
```

#### 2. PasswordAuthentication disabled

```bash
sudo sshd -T | grep passwordauthentication
```

**Expected output:**
```
passwordauthentication no
```

#### 3. PubkeyAuthentication enabled

```bash
sudo sshd -T | grep pubkeyauthentication
```

**Expected output:**
```
pubkeyauthentication yes
```

#### 4. Check hardening config file

```bash
sudo cat /etc/ssh/sshd_config.d/hardening.conf
```

**Should include:**
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

#### 5. SSH key file permissions

```bash
ls -la ~/.ssh/
sudo ls -la /root/.ssh/
```

**Expected permissions:**
```
.ssh directory:        drwx------  (700)
authorized_keys:       -rw-------  (600)
id_rsa:                -rw-------  (600)
id_rsa.pub:            -rw-r--r--  (644)
```

#### 6. Test SSH access

```bash
# From Mac, try public IP (should timeout)
timeout 5 ssh user@<public-ip> -p 22

# From Mac, try Tailscale IP (should work)
ssh -i ~/.ssh/id_rsa user@100.x.x.x
```

### Tailscale

#### 1. Installed

```bash
which tailscale
tailscale version
```

**Expected output:**
```
/usr/bin/tailscale
tailscale version 1.x.x
```

#### 2. Running and connected

```bash
sudo tailscale status
```

**Expected output:**
```
     100.x.x.x   hostname            linux   ok  (this node)
     100.x.x.x   other-node          linux   ok
```

#### 3. Correct IP range

```bash
sudo tailscale ip -4
```

**Expected output (should be 100.x.x.x):**
```
100.64.x.x
```

#### 4. Account verification

```bash
sudo tailscale account
```

**Expected output:**
```
Logged in as techcourtltd@gmail.com
```

### iptables

#### 1. DOCKER-USER chain exists

```bash
sudo iptables -S DOCKER-USER | head -10
```

**Expected output:**
```
-P DOCKER-USER - [0:0]
-A DOCKER-USER -s 100.64.0.0/10 -j RETURN
-A DOCKER-USER -p tcp -m tcp --dport 443 ...
... (more rules)
```

#### 2. Tailscale traffic allowed

```bash
sudo iptables -S DOCKER-USER | grep "100.64"
```

**Expected output:**
```
-A DOCKER-USER -s 100.64.0.0/10 -j RETURN
```

#### 3. Cloudflare IPs allowed

```bash
sudo iptables -S DOCKER-USER | grep "RETURN" | grep -E "(173|103)"
```

**Expected output:**
```
-A DOCKER-USER -p tcp -m tcp --dport 443 -s 173.245.48.0/20 -j RETURN
-A DOCKER-USER -p tcp -m tcp --dport 80 -s 173.245.48.0/20 -j RETURN
... (more Cloudflare IPs)
```

#### 4. Public traffic blocked

```bash
sudo iptables -S DOCKER-USER | grep "DROP"
```

**Expected output:**
```
-A DOCKER-USER -p tcp -m tcp --dport 80 -j DROP
-A DOCKER-USER -p tcp -m tcp --dport 443 -j DROP
-A DOCKER-USER -p tcp -m tcp --dport 3000 -j DROP
```

#### 5. Check IPv6 rules (if not disabled)

```bash
sudo ip6tables -S DOCKER-USER | head -10
```

**Should have similar rules for IPv6.**

#### 6. Verify Cloudflare IPs are cached

```bash
sudo cat /etc/iptables/cloudflare-ips-v4.txt
```

**Should show IPs like:**
```
173.245.48.0/20
103.21.244.0/22
103.22.200.0/22
... (many more)
```

### Kernel Hardening

#### 1. Check all sysctl parameters

```bash
sudo cat /etc/sysctl.d/99-hardening.conf
```

**Should include all these:**
```
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_redirects = 0
fs.suid_dumpable = 0
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
```

#### 2. Verify they're loaded

```bash
sudo sysctl net.ipv4.tcp_syncookies
sudo sysctl net.ipv4.conf.all.rp_filter
```

**Expected output:**
```
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
```

---

## Security Controls

### Defense-in-Depth Layers

```
┌─────────────────────────────────────────────┐
│ PUBLIC INTERNET                             │
└────────────────┬────────────────────────────┘
                 │
      ┌──────────┴──────────┐
      │                     │
  Cloudflare            SSH Brute Force
  (Tunnel)             (Public IP)
      │                     │
      └──────────┬──────────┘
                 │
    ┌────────────▼────────────┐
    │ UFW Firewall            │
    │ - SSH: Tailscale only   │
    │ - 80/443: CF IPs only   │
    │ - App ports: DENY       │
    └────────────┬────────────┘
                 │
    ┌────────────▼────────────┐
    │ iptables (DOCKER-USER)  │
    │ - Tailscale RETURN      │
    │ - CF IPs RETURN         │
    │ - Everything else DROP  │
    └────────────┬────────────┘
                 │
    ┌────────────▼────────────┐
    │ Docker/App Layer        │
    │ - Processes in container│
    │ - Limited capabilities  │
    └─────────────────────────┘
```

### Test Each Layer

#### Layer 1: Cloudflare Tunnel
- ✅ Domain resolves to tunnel
- ✅ HTTPS connection works
- ✅ Direct IP access fails

```bash
# From Mac
dig your-domain.com
curl https://your-domain.com
curl https://<public-ip>  # Should timeout
```

#### Layer 2: UFW + iptables
- ✅ Public SSH attempts timeout
- ✅ Public app ports timeout
- ✅ Tailscale access works

```bash
# From Mac
timeout 5 ssh user@<public-ip>          # Timeout ✅
curl http://<public-ip>:3000             # Timeout ✅
ssh -i key user@100.x.x.x                # Works ✅
```

#### Layer 3: SSH Hardening
- ✅ Password login fails
- ✅ Root login fails
- ✅ Key login works

```bash
# From Mac
ssh -o PasswordAuthentication=yes user@100.x.x.x  # Fails ✅
ssh root@100.x.x.x                               # Fails ✅
ssh -i ~/.ssh/id_rsa user@100.x.x.x              # Works ✅
```

---

## Testing from Mac

### SSH Tests

```bash
# Test public IP (should timeout or refuse)
timeout 5 ssh -v user@<public-ip>

# Test Tailscale IP (should work)
ssh -i ~/.ssh/id_rsa user@100.x.x.x

# Test with password (should be denied)
ssh -o PasswordAuthentication=yes user@100.x.x.x

# Test as root (should be denied)
ssh root@100.x.x.x
```

### Port Scanning

```bash
# Scan public IP (all ports should be closed/filtered)
nmap <public-ip>
# Should see: All 1000 scanned ports are filtered

# Scan from Tailscale (specific ports should be open)
nmap -p 22,80,443,3000,3123 100.x.x.x
# Ports 22,80,443 should be open, 3000/3123 closed
```

### Curl Tests

```bash
# Test direct IP:port (should timeout)
timeout 5 curl -v http://<public-ip>:3000
timeout 5 curl -v https://<public-ip>:443

# Test via tunnel domain (should work)
curl https://your-domain.com

# Test via Tailscale
curl -v http://100.x.x.x:3000   # Or internal app port
```

---

## Common Issues

### SSH Connection Timeout

**Symptom:** `ssh user@100.x.x.x` hangs or times out.

**Checklist:**
```bash
# 1. Is Tailscale running?
sudo tailscale status

# 2. Is SSH service running?
sudo systemctl status ssh

# 3. Is UFW rule correct?
sudo ufw status | grep tailscale0

# 4. Can you ping from Mac?
ping 100.x.x.x

# 5. Check SSH logs
sudo tail -20 /var/log/auth.log
```

**Solutions:**
```bash
# Restart SSH
sudo systemctl restart ssh

# Reload UFW
sudo ufw reload

# Or add temporary SSH rule from your Mac IP
sudo ufw allow from <your-mac-ip> to any port 22
```

### UFW Rule Not Taking Effect

**Symptom:** UFW shows rule but traffic still gets through.

**Checklist:**
```bash
# 1. Is UFW actually active?
sudo ufw status
# Should say "Status: active"

# 2. Do rules show correctly?
sudo ufw status verbose

# 3. Are iptables rules there?
sudo iptables -S DOCKER-USER

# 4. Is Docker running?
docker ps
```

**Solutions:**
```bash
# Reload UFW
sudo ufw reload

# Reapply Docker rules if container changed
sudo bash /etc/iptables/apply-docker-rules.sh

# Restart Docker
sudo systemctl restart docker
```

### App Port Still Reachable

**Symptom:** `curl http://<public-ip>:3000` works (should timeout).

**Checklist:**
```bash
# 1. Is iptables DROP rule present?
sudo iptables -S DOCKER-USER | grep "3000.*DROP"

# 2. Is the container exposing ports?
docker ps --format "table {{.Names}}\t{{.Ports}}"

# 3. Is there a firewall rule allowing 3000?
sudo ufw status | grep 3000
```

**Solutions:**
```bash
# Ensure DOCKER-USER chain is active
sudo bash /etc/iptables/apply-docker-rules.sh

# Verify Docker didn't override rules
sudo iptables -L DOCKER-USER -n

# Restart Docker
sudo systemctl restart docker
sudo bash /etc/iptables/apply-docker-rules.sh
```

### Auditd Rules Not Loaded

**Symptom:** `sudo auditctl -l` shows no rules.

**Checklist:**
```bash
# 1. Is auditd running?
sudo systemctl status auditd

# 2. Are rules defined?
ls -la /etc/audit/rules.d/

# 3. Try loading manually
sudo auditctl -R /etc/audit/rules.d/hardening.rules

# 4. Check for errors
sudo auditctl -l 2>&1 | head -20
```

**Solutions:**
```bash
# Load rules
sudo auditctl -R /etc/audit/rules.d/hardening.rules

# Make persistent
sudo service auditd restart

# Verify
sudo auditctl -l | wc -l  # Should show many rules
```

### Fail2Ban Jail Not Working

**Symptom:** `sudo fail2ban-client status sshd` shows empty jail.

**Checklist:**
```bash
# 1. Is fail2ban running?
sudo systemctl status fail2ban

# 2. Is jail enabled?
sudo fail2ban-client status

# 3. Check config
sudo cat /etc/fail2ban/jail.d/hardening.conf

# 4. Check logs
sudo tail -20 /var/log/fail2ban.log
```

**Solutions:**
```bash
# Restart fail2ban
sudo systemctl restart fail2ban

# Verify
sudo fail2ban-client status sshd

# Monitor in real-time
sudo tail -f /var/log/fail2ban.log
```

### Cloudflare IPs Not Updated

**Symptom:** `cat /etc/iptables/cloudflare-ips-v4.txt` shows old date.

**Checklist:**
```bash
# 1. Is cron job installed?
cat /etc/cron.monthly/update-cloudflare-iptables

# 2. When did it last run?
ls -la /var/log/cf-iptables-update.log

# 3. Any errors?
sudo tail -20 /var/log/cf-iptables-update.log
```

**Solutions:**
```bash
# Update manually
sudo /usr/local/sbin/update-cloudflare-ips.sh

# Reapply iptables
sudo bash /etc/iptables/apply-docker-rules.sh

# Check next scheduled run
sudo grep -r "update-cloudflare" /var/spool/cron/
```

---

## Maintenance

### Monthly Tasks

- [ ] Review UFW logs: `sudo grep UFW /var/log/syslog | tail -50`
- [ ] Check Fail2Ban bans: `sudo fail2ban-client status sshd`
- [ ] Review auth logs: `sudo tail -100 /var/log/auth.log | grep -i fail`
- [ ] Audit log review: `sudo ausearch -k hardening | tail -20`
- [ ] Verify Cloudflare IPs: `ls -la /etc/iptables/cloudflare-ips-v4.txt`

### Quarterly Tasks

- [ ] Full verification: `sudo bash verify-hardening.sh`
- [ ] Review SSH keys: `sudo ls -la ~/.ssh/ /root/.ssh/`
- [ ] Update kernel: `sudo apt update && sudo apt install linux-image-generic`
- [ ] Update packages: `sudo apt upgrade`
- [ ] Check AppArmor: `sudo aa-status`

### Annual Tasks

- [ ] Security audit: Review all hardening settings
- [ ] Key rotation: Generate new SSH keys if needed
- [ ] Firewall review: Ensure rules still align with requirements
- [ ] Documentation update: Review and update this guide

---

## Additional Resources

- [SECURITY.md](SECURITY.md) — Responsible disclosure & security policy
- [USAGE.md](USAGE.md) — Detailed hardening walkthrough
- [SETUP-SSH-KEYS.md](SETUP-SSH-KEYS.md) — SSH key management

---

**Last Updated:** April 2026
**Version:** 1.0.0
