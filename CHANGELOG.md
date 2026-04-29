# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

---

## [2.1.0] — 2026-04-29

### Added

- **Live Cloudflare IP fetching** — Fetches current IPv4 & IPv6 ranges from authoritative source with validation
- **IPv6 support** — Full IPv6 hardening via ip6tables (optional disable)
- **Kernel hardening (sysctl)** — SYN cookies, source routing protection, redirect handling, core dump disable
- **Auditd rules** — CIS-aligned audit logging for files & commands
- **UFW backup before reset** — Automatic dated backups of existing rules
- **Cloudflare IP updater script** — `/usr/local/sbin/update-cloudflare-ips.sh` for manual updates
- **Log rotation** — Weekly rotation of Cloudflare IP update logs
- **Port 3000 explicit deny** — Added to both UFW host rules and iptables DOCKER-USER
- **SSH hardening tightened** — `MaxSessions 2`, `AllowTcpForwarding no`
- **Enhanced security checklist** — 25+ validation checks including IPv6 & audit rules
- **Documentation** — Comprehensive USAGE.md, README.md with architecture diagrams
- **setup-ssh-keys.sh** — Separate script for SSH key generation & authentication hardening
- **License & community files** — LICENSE (MIT), SECURITY.md, CONTRIBUTING.md, .gitignore
- **Gnupg package** — Added to dependencies for GPG signature verification

### Changed

- **Tailscale installation** — Now uses signed APT repo instead of `curl | sh` (breaking change for security)
- **Cloudflare IP management** — Moved from static embedded list to dynamic fetched list
- **systemd service binding** — Changed `PartOf=` to `BindsTo=` for correct Docker restart semantics
- **Script numbering** — Increased from 16 to 21+ steps (added kernel, audit, updater steps)
- **Version number** — Bumped to 2.1.0 for security-focused release

### Fixed

- **Supply chain security** — Removed direct `curl | sh` vulnerability in Tailscale installation
- **Cloudflare IP staleness** — IPs now refresh monthly instead of never
- **IPv6 bypass** — Previously no IPv6 rules existed (full bypass); now hardened
- **Kernel attack vectors** — Added sysctl rules for SYN floods, IP spoofing, redirects
- **Auditd theater** — Installed but unconfigured; now has functional CIS-aligned rules
- **SSH consistency** — `AllowTcpForwarding local` changed to `no` for zero-trust
- **Fail2Ban cosmetic** — Still configured even though SSH is Tailscale-only; noted in docs
- **Heredoc error handling** — Added `set -euo pipefail` to apply-docker-rules.sh

### Security

- ⚠️ **Breaking**: Root & password login no longer allowed after step 11 (use setup-ssh-keys.sh to configure keys first)
- ⚠️ **Breaking**: Tailscale installation requires GPG verification (no unsigned script execution)
- ✅ IPv6 fully hardened or disabled
- ✅ Kernel parameters hardened
- ✅ Auditd provides compliance logging
- ✅ Firewall rules validated with regex before applying
- ✅ Log rotation prevents disk exhaustion

### Deprecated

- Static Cloudflare IP list in main script (still exists as fallback with `ALLOW_STATIC_CF_IPS=1`)
- Direct curl-to-sh installation pattern (replaced with signed repos)

### Removed

- Direct piping of install scripts to shell (replaced with signed packages)

### Documentation

- Added step-by-step walkthrough (USAGE.md)
- Added SSH key setup guide (SETUP-SSH-KEYS.md)
- Added architecture diagram in README
- Added troubleshooting matrix
- Added common scenarios & workflows
- Added verification commands
- Added maintenance checklist

---

## [2.0.0] — 2026-04-01

### Added

- Full node security hardening script
- UFW firewall configuration
- DOCKER-USER iptables rules with Cloudflare IP allowlisting
- SSH hardening (key-based auth, root login disabled)
- Fail2Ban configuration
- AppArmor enablement
- Auditd installation (unconfigured)
- Unattended security upgrades
- Tailscale integration (curl | sh)
- Cloudflare tunnel support
- Idempotent design
- Security checklist validation
- Systemd services for iptables persistence

### Documentation

- Initial README with feature list
- Usage instructions
- Next steps & key files

---

## [1.0.0] — 2026-03-15

### Initial Release

- Basic SSH hardening script
- UFW firewall setup
- iptables rules (not Docker-aware)
- Manual IP allowlisting

---

## [Unreleased]

### Planned

- [ ] Automated rollback mechanism
- [ ] Interactive mode (--interactive flag)
- [ ] AIDE/Tripwire file integrity monitoring
- [ ] Custom AppArmor profiles for containers
- [ ] Prometheus/Grafana metrics export
- [ ] Cloud provider hardening (AWS, GCP, Azure)
- [ ] Multi-user management script
- [ ] Performance optimization for large rulesets
- [ ] Integration tests & CI/CD pipeline

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on reporting bugs, suggesting features, and submitting code.

## Security

For security issues, see [SECURITY.md](SECURITY.md).

## License

All versions are licensed under the MIT License — see [LICENSE](LICENSE).
