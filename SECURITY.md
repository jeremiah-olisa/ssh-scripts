# Security Policy

## Reporting Security Vulnerabilities

If you discover a security vulnerability in this project, **please do not open a public GitHub issue**. Instead, email your findings to the project maintainers.

### How to Report

1. **Email**: ____________
2. **Include**:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)
3. **Wait**: Allow 90 days for a fix before public disclosure

### What We'll Do

- Acknowledge receipt within 48 hours
- Investigate and validate the issue
- Release a fix and security advisory
- Credit you in the advisory (if desired)

---

## Scope

This security policy covers:
- Remote code execution risks
- Authentication/authorization bypass
- Privilege escalation
- Data exposure (SSH keys, credentials, logs)
- Firewall rule bypass

---

## Out of Scope

- Social engineering
- Denial of service (flooding, etc.)
- Low-impact issues (typos, minor UX bugs)
- Information already public or widely known

---

## Security Best Practices

When using these scripts:

1. **Always review** the scripts before running with sudo
2. **Keep systems updated** — regularly run `apt-get update && apt-get upgrade`
3. **Use strong SSH keys** — 4096-bit RSA or Ed25519
4. **Rotate keys** — annually or when devices are decommissioned
5. **Monitor logs** — regularly check `/var/log/audit/audit.log`
6. **Test changes** — use a staging environment first
7. **Backup configs** — keep copies of UFW rules, SSH configs
8. **Use Tailscale** — for secure, encrypted VPN access

---

## Versioning

Security fixes are released as patch versions (e.g., 2.1.1 → 2.1.2).

Check the [CHANGELOG](CHANGELOG.md) for security-related updates.

---

## Questions?

Open an issue for non-security questions or general support.

For security concerns, email directly instead.

Thank you for helping keep this project secure! 🔒
