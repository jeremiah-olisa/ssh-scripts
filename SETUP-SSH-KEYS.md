# setup-ssh-keys.sh — SSH Key Setup & Authentication Hardening Guide

A **standalone, idempotent bash script** that generates SSH key pairs or imports existing keys, then hardens SSH to disable root login and password authentication. Works with any Unix system (Ubuntu, macOS, etc.).

## 🎯 Purpose

Simplifies SSH hardening after initial node setup:

1. **Generate new SSH keys** for you (or import your existing key)
2. **Configure authorized_keys** with correct permissions
3. **Harden SSH config** (disable root, disable passwords)
4. **Validate everything** before restarting SSH
5. **Display next steps** with connection info

## 📋 Requirements

- **Local**: SSH key pair (generated or existing)
- **Remote**: Root access (to run script)
- **Remote**: Ubuntu 24.04 LTS (or any Debian-based system)
- **Network**: Access to the node during setup

## ⚡ Quick Start

### Option 1: Generate New SSH Keys (Easiest)

```bash
sudo bash setup-ssh-keys.sh --generate
```

The script will:
1. Generate a new 4096-bit RSA key
2. Display the **private key** (copy & save it)
3. Add the public key to `~/.ssh/authorized_keys`
4. Harden SSH configuration
5. Test everything

Then save the private key to your workstation:

```bash
# On your local machine, create ~/.ssh/id_rsa with the key from above
vim ~/.ssh/id_rsa
chmod 600 ~/.ssh/id_rsa

# Test connection
ssh root@your.node
```

### Option 2: Import Your Existing SSH Key

```bash
# From the node, run:
sudo bash setup-ssh-keys.sh --key-path ~/.ssh/id_rsa.pub
```

Or provide the path to your key:

```bash
sudo bash setup-ssh-keys.sh --key-path /home/user/.ssh/id_rsa.pub
```

### Option 3: Set Up for Non-Root User (Devops User)

```bash
# Generate key for devops user
sudo bash setup-ssh-keys.sh --generate --user devops

# Or import for devops user
sudo bash setup-ssh-keys.sh --key-path ~/.ssh/id_rsa.pub --user devops
```

## 📖 Usage Reference

### Full Help

```bash
sudo bash setup-ssh-keys.sh --help
```

### All Options

| Option | Default | Purpose |
|--------|---------|---------|
| `--generate` | — | Generate new 4096-bit RSA key |
| `--key-path PATH` | — | Import existing public key from PATH |
| `--user USER` | `root` | Target user for SSH hardening |
| `--help` | — | Show help message |

### Examples

```bash
# Generate for root
sudo bash setup-ssh-keys.sh --generate

# Generate for devops user
sudo bash setup-ssh-keys.sh --generate --user devops

# Import from ~/.ssh/id_rsa.pub for root
sudo bash setup-ssh-keys.sh --key-path ~/.ssh/id_rsa.pub

# Import for devops user
sudo bash setup-ssh-keys.sh --key-path /home/myuser/.ssh/id_rsa.pub --user devops

# Chain with main hardening script
sudo bash harden-node.sh && sudo bash setup-ssh-keys.sh --generate
```

## 🔄 Step-by-Step Walkthrough

### Step 0: Validate Target User

Checks that the target user exists on the system.

```
[>>] ━━━ Validating target user ━━━
[OK] Target user: root (home: /root)
```

---

### Step 1: Generate or Import SSH Key

#### Generate Mode
```
[>>] ━━━ Generating SSH key pair ━━━
[>>] Generating 4096-bit RSA key...
[OK] SSH key generated

━━━ SAVE THIS PRIVATE KEY SECURELY ━━━

-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEA1z+...
...base64 encoded key...
...
-----END RSA PRIVATE KEY-----

━━━ END PRIVATE KEY ━━━

[!] ⚠️  IMPORTANT: Copy the private key above and save it somewhere safe.
[!] ⚠️  You will need it to SSH into root@your-hostname
[!] ⚠️  This key will NOT be displayed again.

Press Enter once you've saved the private key...
```

#### Import Mode
```
[>>] ━━━ Importing SSH public key ━━━
[OK] Public key imported from ~/.ssh/id_rsa.pub
```

---

### Step 2: Validate Public Key Format

Verifies the key is in a recognized format (ssh-rsa, ssh-ed25519, ecdsa-sha2-*).

```
[>>] ━━━ Validating public key ━━━
[OK] Public key valid
```

---

### Step 3: Set Up ~/.ssh Directory

Creates or verifies `~/.ssh` with correct permissions (700).

```
[>>] ━━━ Setting up ~/.ssh for root ━━━
[OK] ~/.ssh already exists
```

---

### Step 4: Add Public Key

Backs up existing `authorized_keys` (if present) and adds the new public key.

```
[>>] ━━━ Adding public key to authorized_keys ━━━
[!] Backed up existing authorized_keys
[OK] Public key added to authorized_keys
```

---

### Step 5: Harden SSH Config

Writes `/etc/ssh/sshd_config.d/harden-keys.conf` with:
- `PermitRootLogin no`
- `PasswordAuthentication no`
- `PubkeyAuthentication yes`
- Session limits, logging, and other hardening

```
[>>] ━━━ Hardening SSH configuration ━━━
[OK] SSH hardening config written to /etc/ssh/sshd_config.d/harden-keys.conf
```

---

### Step 6: Validate SSH Config

Runs `sshd -t` to verify syntax before reloading.

```
[>>] ━━━ Validating SSH configuration ━━━
[OK] SSH config syntax valid
```

---

### Step 7: Reload SSH Daemon

Reloads SSH service (no disconnects for existing sessions).

```
[>>] ━━━ Reloading SSH daemon ━━━
[OK] SSH daemon reloaded (ssh)
```

---

### Step 8: Verification Checklist

Runs 8 checks to verify everything is configured correctly.

```
[>>] ━━━ Verifying SSH hardening ━━━
  ✓ Public key in authorized_keys
  ✓ authorized_keys owned by root
  ✓ authorized_keys has 600 perms
  ✓ ~/.ssh owned by root
  ✓ ~/.ssh has 700 perms
  ✓ PermitRootLogin disabled
  ✓ PasswordAuthentication disabled
  ✓ PubkeyAuthentication enabled

━━━ Verification Results ━━━
  Passed: 8   Failed: 0
```

---

### Final Summary

Displays next steps and key file locations.

```
SSH KEY SETUP COMPLETE — v1.0.0

🔑 NEXT STEPS:
 1. Save the private key you displayed above to your local machine:
    ~/.ssh/id_rsa (on your workstation)

 2. Set correct permissions on local private key:
    chmod 600 ~/.ssh/id_rsa

 3. Test SSH connection:
    ssh -i ~/.ssh/id_rsa root@your-hostname

 4. Password login is now DISABLED for all users
 5. Root login is now DISABLED
 6. Only SSH key authentication works
```

---

## 📖 Workflows

### Workflow 1: Fresh Node Setup (Generate Keys)

```bash
# 1. SSH as root (temporary, via password)
ssh root@new.node

# 2. Run main hardening
sudo bash harden-node.sh

# 3. Generate & install SSH key
sudo bash setup-ssh-keys.sh --generate

# 4. Save the displayed private key to ~/.ssh/id_rsa on your machine

# 5. Exit and reconnect via SSH key
exit

# 6. Test new connection (password now disabled)
ssh -i ~/.ssh/id_rsa root@new.node

# 7. ✅ Done! Root SSH is now key-only, no password allowed
```

### Workflow 2: Secure Existing Devops User

```bash
# 1. Create devops user (if not exists)
sudo useradd -m -s /bin/bash devops

# 2. Add devops to sudo group
sudo usermod -aG sudo devops

# 3. Set up SSH keys for devops
sudo bash setup-ssh-keys.sh --key-path ~/.ssh/id_rsa.pub --user devops

# 4. Test connection
ssh -i ~/.ssh/id_rsa devops@node

# 5. ✅ Now use devops for all SSH access
```

### Workflow 3: Import Multiple SSH Keys

```bash
# For user with multiple devices/keys:

# 1. Generate SSH key on device 1
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa_laptop -N ""

# 2. Generate SSH key on device 2
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa_desktop -N ""

# 3. On the node, add first key
sudo bash setup-ssh-keys.sh --key-path /path/to/id_rsa_laptop.pub

# 4. Manually add second key to authorized_keys
sudo bash -c 'cat /path/to/id_rsa_desktop.pub >> ~/.ssh/authorized_keys'

# 5. Now both devices can SSH
ssh -i ~/.ssh/id_rsa_laptop devops@node
ssh -i ~/.ssh/id_rsa_desktop devops@node
```

### Workflow 4: Re-run for Updates

```bash
# If SSH config drifts or you need to re-harden:
sudo bash setup-ssh-keys.sh --user root

# Idempotent — will verify existing key & re-apply hardening
```

---

## 🔐 What Gets Hardened

### SSH Configuration Applied

```bash
# Disable root login
PermitRootLogin no

# Require public key auth
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
KbdInteractiveAuthentication no

# Session limits
MaxAuthTries 3
MaxSessions 2
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2

# Security
LogLevel VERBOSE
AllowTcpForwarding no
X11Forwarding no
UseDNS no
```

### File Permissions

```bash
~/.ssh/authorized_keys     # 600 (rw-------)
~/.ssh/                    # 700 (rwx------)
```

### Backups

Existing `authorized_keys` is backed up before modification:

```
/root/.ssh/authorized_keys.backup-20260429-143022
/root/.ssh/authorized_keys.backup-20260429-150145
```

---

## 🛠️ Troubleshooting

### Problem: "User 'devops' does not exist"

**Cause:** Target user hasn't been created yet.

**Solution:**
```bash
# Create the user first
sudo useradd -m -s /bin/bash devops

# Then run setup-ssh-keys
sudo bash setup-ssh-keys.sh --generate --user devops
```

---

### Problem: "Invalid public key format"

**Cause:** The file doesn't contain an SSH public key.

**Solution:**
```bash
# Verify it's the public key (ends in .pub)
cat ~/.ssh/id_rsa.pub

# Should start with: ssh-rsa, ssh-ed25519, or ecdsa-sha2-

# If you have the private key instead, generate the public key:
ssh-keygen -y -f ~/.ssh/id_rsa > ~/.ssh/id_rsa.pub

# Then re-run the script
sudo bash setup-ssh-keys.sh --key-path ~/.ssh/id_rsa.pub
```

---

### Problem: "SSH config validation failed"

**Cause:** SSH config has a syntax error.

**Solution:**
```bash
# Check what's wrong
sshd -t

# Review the hardening config
cat /etc/ssh/sshd_config.d/harden-keys.conf

# Restore from backup if needed
sudo sshd -t < /etc/ssh/sshd_config

# Re-run setup
sudo bash setup-ssh-keys.sh
```

---

### Problem: "Can't connect via SSH after running"

**Cause:** Key not in authorized_keys or permissions wrong.

**Solution:**
```bash
# From another terminal with root access:

# Verify key is in authorized_keys
sudo cat ~/.ssh/authorized_keys

# Check permissions
sudo stat ~/.ssh/authorized_keys    # Should be 600
sudo stat ~/.ssh/                   # Should be 700

# Restore from backup if needed
sudo cp ~/.ssh/authorized_keys.backup-* ~/.ssh/authorized_keys

# Fix permissions
sudo chmod 600 ~/.ssh/authorized_keys
sudo chmod 700 ~/.ssh/

# Try SSH again
ssh -i ~/.ssh/id_rsa root@node
```

---

### Problem: "Private key displayed but I didn't save it"

**Cause:** Key generation completed and you missed copying the private key.

**Solution:**
```bash
# The private key is GONE (secure by design)
# You must regenerate:

# Backup old authorized_keys
sudo mv ~/.ssh/authorized_keys ~/.ssh/authorized_keys.old

# Generate new key
sudo bash setup-ssh-keys.sh --generate

# Save the new private key
# This time it's displayed only once
```

---

## 📊 Verification Commands

### Check SSH Hardening Applied

```bash
# Check PermitRootLogin
sudo sshd -T | grep permitrootlogin
# Output: permitrootlogin no

# Check PasswordAuthentication
sudo sshd -T | grep passwordauthentication
# Output: passwordauthentication no

# Check config file
cat /etc/ssh/sshd_config.d/harden-keys.conf
```

### Check Key Is in authorized_keys

```bash
# View all keys
sudo cat ~/.ssh/authorized_keys

# Count keys
sudo wc -l ~/.ssh/authorized_keys

# Check for specific key
sudo grep "your-key-comment" ~/.ssh/authorized_keys
```

### Check Permissions

```bash
# Should show 600
sudo stat ~/.ssh/authorized_keys | grep Access

# Should show 700
sudo stat ~/.ssh/ | grep Access
```

### Test SSH Connection

```bash
# With verbose output
ssh -vvv -i ~/.ssh/id_rsa root@your-node

# List available identities
ssh-add -l
```

---

## 🔄 Idempotency

The script is **fully idempotent** — safe to run multiple times:

```bash
# 1st run: generates key, sets up SSH
sudo bash setup-ssh-keys.sh --generate

# 2nd run: verifies key exists, re-applies hardening
sudo bash setup-ssh-keys.sh --generate

# 3rd run: same as 2nd (no changes needed)
sudo bash setup-ssh-keys.sh --generate
```

Each run:
1. Checks if user exists
2. Validates or generates key
3. Verifies key format
4. Backs up (if changes needed)
5. Applies SSH hardening
6. Tests SSH config
7. Reloads SSH (no impact if already correct)

---

## 📁 File Locations

```
/root/.ssh/authorized_keys              # Public keys for root
/root/.ssh/authorized_keys.backup-*     # Backups (timestamped)
/home/devops/.ssh/authorized_keys       # Public keys for devops user

/etc/ssh/sshd_config                    # Main SSH config
/etc/ssh/sshd_config.d/harden-keys.conf # Hardening settings (drop-in)

~/.ssh/id_rsa                           # Your private key (local)
~/.ssh/id_rsa.pub                       # Your public key (local)
```

---

## 🔐 Security Notes

### Private Key Safety

- **Never commit private keys** to git
- **Never share private keys** over email
- **Only store locally** on your machine
- **Use a passphrase** if possible
- **Backup securely** (encrypted)

### Public Key vs Private Key

- **Public key** → goes on the server in `authorized_keys`
- **Private key** → stays on your machine only
- **Public key** → can be shared freely
- **Private key** → keep secret always

### Recovering Lost Private Key

If you lose your private key:

```bash
# Generate a NEW key (old one won't work)
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa_new -N ""

# Update the server
sudo bash setup-ssh-keys.sh --key-path ~/.ssh/id_rsa_new.pub
```

---

## 🎓 Best Practices

1. **Use strong keys:** 4096-bit RSA minimum (script uses this)
2. **One key per device:** Don't reuse across machines
3. **Rotate periodically:** Generate new keys yearly
4. **Backup private keys:** Encrypt & store offsite
5. **Use SSH agent:** Avoid typing passphrase repeatedly
6. **Disable password SSH:** Once keys are working (this script does it)
7. **Monitor authorized_keys:** Review quarterly for unexpected keys
8. **Remove old keys:** Delete from authorized_keys when decommissioning devices

---

## Summary

| Before | After |
|--------|-------|
| Root login allowed | Root login disabled |
| Password login allowed | Password login disabled |
| No SSH keys | SSH keys configured |
| Manual hardening needed | Hardening applied automatically |

---

**For the main hardening script, see [README.md](README.md) and [USAGE.md](USAGE.md).**
