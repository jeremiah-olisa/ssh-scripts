# harden-node.sh — Ubuntu 24.04 Security Hardening Script

A **production-grade, idempotent bash script** for hardening Ubuntu 24.04 LTS nodes with comprehensive security controls. Designed for nodes running Docker, Tailscale, and Cloudflare tunnel.

## ✨ Features

- **Firewall hardening**: UFW + iptables DOCKER-USER rules with Cloudflare IP allowlisting
- **SSH lockdown**: Key-only auth, rate limiting, Tailscale-only access
- **Container security**: Docker-aware iptables rules that survive restarts
- **Kernel hardening**: sysctl parameters for network & memory protections
- **Supply chain safety**: Signed package repos (no `curl | sh`)
- **Dynamic IP management**: Live Cloudflare IP fetching with validation & caching
- **Audit logging**: auditd rules for compliance (CIS-aligned)
- **Unattended upgrades**: Automatic security updates
- **Idempotent**: Safe to re-run at any time
- **IPv6 support**: Optional IPv6 disabling or hardening

## 📋 What Gets Hardened

| Component | Script | Action |
|-----------|--------|--------|
| **UFW** | harden-node.sh | Reset to deny-by-default, SSH via Tailscale only |
| **iptables** | harden-node.sh | DOCKER-USER chain persists across Docker restarts |
| **SSH** | harden-node.sh | Initial hardening; can be enhanced with setup-ssh-keys.sh |
| **SSH Keys** | setup-ssh-keys.sh | Generate or import SSH keys, disable root & password login |
| **Fail2Ban** | harden-node.sh | SSH rate limiting with exponential backoff |
| **Kernel** | harden-node.sh | SYN cookies, source routing disabled, IPv6 (optional) |
| **AppArmor** | harden-node.sh | Enabled system-wide |
| **Auditd** | harden-node.sh | File integrity & command logging |
| **Unattended Upgrades** | harden-node.sh | Daily security patches |
| **Cloudflare** | harden-node.sh | Live IP list fetching with validation |
| **Tailscale** | harden-node.sh | Signed APT repo (secure installation) |

## 🔧 Requirements

- **OS**: Ubuntu 24.04 LTS (other Debian derivatives may work but untested)
- **Privileges**: Must run as `root` or via `sudo`
- **Network**: Internet connectivity (for package + IP list downloads)
- **Docker**: Optional but recommended (required for DOCKER-USER rules)
- **Tailscale**: Installed separately (script automates installation)

## 📥 Installation

### Option 1: Quick One-Liner (Recommended for Owners/Trusted Users)

```bash
sudo bash <(curl -fsSL https://raw.githubusercontent.com/jeremiah-olisa/ssh-scripts/main/harden-node.sh)
```

### Option 2: Download, Review, Then Run (Most Secure)

```bash
# Download
curl -fsSL https://raw.githubusercontent.com/jeremiah-olisa/ssh-scripts/main/harden-node.sh -o harden-node.sh

# Review (always recommended for security scripts!)
cat harden-node.sh | less

# Run
sudo bash harden-node.sh
```

### Option 3: Clone the Full Repository

```bash
git clone https://github.com/jeremiah-olisa/ssh-scripts.git
cd ssh-scripts
sudo bash harden-node.sh
```

## ⚡ Quick Start

### 1. Harden the Node (Pick One Method Above)

**Fastest:**
```bash
sudo bash <(curl -fsSL https://raw.githubusercontent.com/jeremiah-olisa/ssh-scripts/main/harden-node.sh)
```

**Or manually:**
```bash
git clone https://github.com/jeremiah-olisa/ssh-scripts.git
cd ssh-scripts
sudo bash harden-node.sh
```

The script will:
1. Auto-detect your SSH port
2. Fetch live Cloudflare IP ranges
3. Install/configure Tailscale (with browser auth prompt)
4. Apply all hardening steps
5. Run a security checklist
6. Display next steps

### 2. Set Up SSH Key Authentication (Recommended)

```bash
# Generate new SSH keys
sudo bash setup-ssh-keys.sh --generate

# Or import existing keys
sudo bash setup-ssh-keys.sh --key-path ~/.ssh/id_rsa.pub
```

This disables root login and password authentication. See [SETUP-SSH-KEYS.md](SETUP-SSH-KEYS.md) for details.

For detailed options on main hardening, see [USAGE.md](USAGE.md).

## 📦 Installed Services & Tools

| Package | Purpose |
|---------|---------|
| `ufw` | Host firewall |
| `fail2ban` | SSH rate limiting |
| `auditd` | Audit logging |
| `apparmor` | MAC framework |
| `unattended-upgrades` | Auto security patches |
| `tailscale` | VPN access |
| `cloudflared` | Cloudflare tunnel |
| `iptables` | Kernel firewall |

## 🔐 Security Highlights

- **No root SSH**: PermitRootLogin disabled
- **No passwords**: PubkeyAuthentication only
- **Signed repos**: Tailscale & cloudflared from official GPG-signed repos
- **IP validation**: Cloudflare ranges fetched & regex-validated before applying
- **Audit trail**: All security events logged via auditd
- **Kernel hardening**: Mitigates SYN floods, spoofing, ICMP redirects
- **IPv6 optional**: Disable to eliminate whole attack surface, or hardened if enabled

## 🎯 Network Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Internet / Cloudflare                     │
└─────────────────────────────────────────────────────────────┘
  ↓ ports 80/443                  ↓ SSH
┌────────────────────────────────────────┐
│   UFW (host INPUT)                     │
│   - Allow 80/443 from CF IPs only      │
│   - Deny all else                      │
└────────────────────────────────────────┘
  ↓
┌────────────────────────────────────────┐
│  Docker (FORWARD chain)                │
│  - DOCKER-USER: CF + Tailscale only    │
│  - Blocks ports 80/443/3000 from web   │
└────────────────────────────────────────┘
  ↓ via tailscale0
┌────────────────────────────────────────┐
│   SSH (Tailscale access only)          │
│   - No root login                      │
│   - Keys only, max 2 sessions          │
└────────────────────────────────────────┘
```

## 📝 Configuration

Key configs are in `/etc/iptables/` and managed systemd services. Edit cautiously — incorrect rules will block traffic.

**Do not manually edit UFW while the script runs** — idempotency will reset all changes.

For environment variables, see [USAGE.md](USAGE.md).

## 🔄 Updating Cloudflare IPs

The script automatically fetches Cloudflare IP ranges monthly via cron. To update manually:

```bash
sudo /usr/local/sbin/update-cloudflare-ips.sh
sudo bash /etc/iptables/apply-docker-rules.sh
```

## 📊 Verification

After running, check the security checklist output. All items should show `✓`. If any show `✗`:

```bash
sudo bash /etc/iptables/apply-docker-rules.sh
sudo systemctl restart docker-iptables-fix
sudo ufw status verbose
sudo iptables -L DOCKER-USER -n
```

## 🛠️ Troubleshooting

| Issue | Solution |
|-------|----------|
| Cloudflare IP fetch fails | Set `ALLOW_STATIC_CF_IPS=1` or check internet |
| Tailscale won't auth | Check browser window, ensure port 443 open to CF |
| SSH port mismatch | Script auto-detects; confirm via `sshd -T \| grep port` |
| UFW blocks legitimate IPs | Inspect rules: `sudo ufw status verbose` |
| Audit rules not loading | Check `/etc/audit/rules.d/`: `sudo auditctl -l` |

## 📚 File Locations

```
/etc/iptables/
├── apply-docker-rules.sh              # Main iptables logic
├── cloudflare-ips-v4.txt              # Live IPv4 list (cached)
└── cloudflare-ips-v6.txt              # Live IPv6 list (cached)

/etc/systemd/system/
├── docker-iptables-fix.service        # Runs after Docker restart
└── iptables-restore-custom.service    # Runs at boot before Docker

/etc/ssh/sshd_config.d/
└── hardening.conf                     # SSH hardening (drop-in)

/etc/audit/rules.d/
└── hardening.rules                    # Audit rules

/etc/sysctl.d/
└── 99-hardening.conf                  # Kernel parameters

/usr/local/sbin/
└── update-cloudflare-ips.sh            # Manual IP updater

/var/backups/
└── ufw-rules-*.bak                    # UFW backups (dated)

/var/log/
└── cf-iptables-update.log             # Monthly cron log
```

## 🔄 Idempotency

The script is **fully idempotent** — it's safe to run multiple times:

```bash
sudo bash harden-node.sh      # 1st run: applies all rules
sudo bash harden-node.sh      # 2nd run: verifies + re-applies
sudo bash harden-node.sh      # 3rd run: same as 2nd
```

Repeated runs skip already-configured services and re-validate firewall rules.

## ⚠️ Breaking Changes (v2.1.0)

- **Cloudflare IPs now fetched live** instead of hardcoded → requires internet on first run
- **Tailscale installation** via signed repo (no `curl | sh`)
- **IPv6 hardening/disabling** added (disabled by default)
- **Auditd rules** now applied (CIS-aligned)
- **Sysctl hardening** rules added
- **PartOf→BindsTo**: systemd service binding fixed

See [USAGE.md](USAGE.md) for migration notes.

## 🤝 Compliance

This script aligns with:
- **CIS Docker Benchmark** v1.6
- **CIS Ubuntu Linux Benchmark** v2.0
- **NIST SP 800-53** SI-7 (audit), AC-3 (access control)
- **ISO 27001** A.12 (operations security)

## 📄 License

This project is licensed under the **MIT License** — see [LICENSE](LICENSE) for details.

**You are free to:**
- ✅ Use for any purpose (personal, commercial)
- ✅ Modify and fork without permission
- ✅ Distribute and sublicense
- ✅ Use privately or publicly

**You must:**
- ✅ Include a copy of the license
- ✅ Provide attribution to the original author

---

## 🐛 Issues & Contributions

Found a bug? Want to contribute? See [CONTRIBUTING.md](CONTRIBUTING.md).

### 🔒 Security Issues

**Do not open public GitHub issues for security vulnerabilities.** See [SECURITY.md](SECURITY.md) for responsible disclosure.

---

## 📚 Documentation

- [USAGE.md](USAGE.md) — Detailed guide for `harden-node.sh`
- [SETUP-SSH-KEYS.md](SETUP-SSH-KEYS.md) — SSH key setup & authentication
- [SECURITY.md](SECURITY.md) — Responsible disclosure & security policy
- [CONTRIBUTING.md](CONTRIBUTING.md) — How to contribute
- [LICENSE](LICENSE) — MIT License

---


