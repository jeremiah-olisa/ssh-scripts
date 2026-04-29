# Contributing to harden-node.sh

Thank you for your interest in contributing! This document provides guidelines for reporting bugs, suggesting features, and submitting code.

---

## 🐛 Reporting Bugs

### Before Reporting

1. Check existing [Issues](../../issues) — your bug might already be reported
2. Verify the issue is reproducible on Ubuntu 24.04 LTS
3. Gather relevant information:
   - OS version and environment
   - Exact command you ran
   - Full output (including errors)
   - `harden-node.sh` version

### How to Report

1. Open a [New Issue](../../issues/new)
2. Use a descriptive title (e.g., "UFW reset wipes custom rules")
3. Provide steps to reproduce
4. Share expected vs actual behavior
5. Attach logs or screenshots if helpful

### Example Bug Report

```
Title: SSH key setup fails for non-root users

Environment:
- Ubuntu 24.04 LTS
- harden-node.sh v2.1.0

Steps to Reproduce:
1. sudo bash setup-ssh-keys.sh --generate --user devops
2. Script fails at Step 3

Expected:
SSH key should be generated for devops user

Actual:
Error: mkdir: cannot create directory '/root/.ssh': Permission denied

Logs:
[full error output here]
```

---

## 💡 Suggesting Features

### Before Suggesting

1. Check existing [Issues & Discussions](../../issues)
2. Ensure feature aligns with script's purpose (hardening, not general admin tools)
3. Think about security implications

### How to Suggest

1. Open a [New Discussion](../../discussions) or Issue with label `enhancement`
2. Explain the use case and why it would help
3. Provide examples of how it would work

### Example Feature Suggestion

```
Title: Add support for disabling IPv6 completely

Use Case:
Some infrastructure doesn't use IPv6 and wants it fully disabled
for reduced attack surface.

Suggestion:
Add --disable-ipv6 flag or environment variable DISABLE_IPV6=1

Expected Behavior:
- Sets net.ipv6.conf.all.disable_ipv6=1
- Disables IPv6 in UFW
- Clears IPv6 iptables rules
```

---

## 💻 Contributing Code

### Before Starting

1. Check [Issues](../../issues) for related work
2. Fork the repository
3. Create a feature branch: `git checkout -b fix/your-issue-name`
4. Keep commits focused and descriptive

### Code Guidelines

#### Bash Style

```bash
# Use proper shebang
#!/bin/bash

# Enable strict mode
set -euo pipefail

# Use meaningful variable names
SSH_PORT=22  # Good
sp=22        # Bad

# Add comments for complex logic
if [ "$DISABLE_IPV6" -eq 1 ]; then
  # Disable IPv6 system-wide
  sysctl net.ipv6.conf.all.disable_ipv6=1
fi

# Use consistent quoting
"$variable"  # Good
$variable    # Risky (globbing, word-splitting)
```

#### Functions & Structure

```bash
# Use descriptive function names
validate_ssh_key() { :; }   # Good
check_key() { :; }          # Too vague

# Log output consistently
log "Success message"        # Use existing log functions
info "Informational message"
warn "Warning message"
err "Error and exit"

# Fail fast
[ -f "$file" ] || err "File not found: $file"
```

#### Comments & Documentation

```bash
# Add section headers for major steps
# =============================================================================
# STEP 5: HARDEN SSH CONFIG
# =============================================================================

# Explain non-obvious decisions
# We use 700 instead of 755 to prevent other users from reading SSH keys
chmod 700 ~/.ssh

# Explain what commands do if not obvious
# -w = watch file for writes, -p wa = permissions + writes, -k = key name
auditctl -w /etc/passwd -p wa -k identity
```

### Testing Your Changes

1. **Test on Ubuntu 24.04** (or compatible Debian system)
2. **Run as root**: `sudo bash harden-node.sh`
3. **Verify all checks pass**: Look for `Passed: X   Failed: 0`
4. **Test idempotency**: Run twice, ensure same result
5. **Check SSH still works**: `ssh user@node`
6. **Review logs**: `sudo tail -50 /var/log/auth.log`

### Submitting a Pull Request

1. Push your branch to your fork
2. Open a [Pull Request](../../pulls)
3. Provide:
   - Clear description of changes
   - Link to related Issue (if any)
   - Testing results (what you tested, how)
   - Any breaking changes or migration notes

#### PR Template

```markdown
## Description
What does this PR do? Why is it needed?

## Related Issue
Closes #123

## Changes
- [ ] Change 1
- [ ] Change 2

## Testing
- [ ] Tested on Ubuntu 24.04
- [ ] Ran full script — all checks passed
- [ ] Tested idempotency (ran twice)
- [ ] No regressions detected

## Breaking Changes
None / Describe any breaking changes

## Additional Notes
Any other information reviewers should know
```

---

## 📝 Commit Message Guidelines

Use clear, descriptive commit messages:

```bash
# Good
git commit -m "Fix SSH port detection for non-standard ports"
git commit -m "Add IPv6 hardening rules to iptables"
git commit -m "Improve Cloudflare IP validation with regex"

# Bad
git commit -m "Fix bug"
git commit -m "Updates"
git commit -m "asdf"
```

Format: `<type>: <description>`

Types:
- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation
- `refactor:` Code refactoring
- `test:` Testing additions
- `chore:` Maintenance

---

## 🔒 Security Contributions

Found a security issue? **Do not open a public issue.** See [SECURITY.md](SECURITY.md) for responsible disclosure.

---

## 📖 Documentation Contributions

Help improve docs:

1. Typos and grammar: Open an issue or PR
2. Unclear sections: Open a Discussion explaining what's confusing
3. Missing information: Suggest additions

Examples:
- Better examples for edge cases
- Troubleshooting for common errors
- Architecture diagrams
- Video walkthrough scripts

---

## 🚀 Release Process

Maintainers use:
- Semantic versioning: `MAJOR.MINOR.PATCH`
- Changelog in `CHANGELOG.md`
- Git tags for releases

Contributors don't need to manage this — just focus on code quality.

---

## ❓ Questions?

- Ask in [Discussions](../../discussions)
- Open an [Issue](../../issues) with label `question`
- Check [USAGE.md](USAGE.md) and [SETUP-SSH-KEYS.md](SETUP-SSH-KEYS.md) first

---

## 📋 Code of Conduct

Be respectful, inclusive, and professional. We're all here to improve security.

**Unacceptable behavior:**
- Harassment, discrimination
- Spam or off-topic posts
- Spam or promotional content
- Malicious contributions

**Consequences:**
- First offense: Warning
- Repeated: Temporary mute/ban
- Severe: Permanent ban

---

## License

By contributing, you agree your code will be licensed under the [MIT License](LICENSE).

---

**Thank you for contributing to a more secure internet! 🔒**
