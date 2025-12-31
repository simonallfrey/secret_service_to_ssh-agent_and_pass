# Moving from Secret Service to ssh-agent + pass on Ubuntu

***TL;DR:***  *Ubuntu's default GNOME Keyring/Secret Service breaks in headless environments (servers, SSH, WSL) — unreliable SSH agent and Git credential storage without GUI. This script fixes it with a secure, CLI-only workflow: keychain for ssh-agent, pass + GPG for encrypted storage, and Git Credential Manager using the GPG backend. Result: automatic SSH key loading and silent Git operations (SSH & HTTPS) with no GUI ever needed. Set it up yourself with `./install.sh`; verify everything works with `./sanity_check.sh`.*

## Introduction

This report explains the rationale and process for transitioning from the GNOME Keyring (which implements the freedesktop.org Secret Service API) to a combination of OpenSSH's `ssh-agent` and the `pass` password manager (backed by GPG) for managing SSH keys and Git credentials on Ubuntu, particularly in headless environments. This move addresses limitations in GUI-dependent tools like GNOME Keyring, improving compatibility, security, and usability for server or CLI-only setups.

The "Secret Service" refers to the secure storage system used by GNOME Keyring for passwords, tokens, and SSH key passphrases. We'll cover why this shift is beneficial, step-by-step instructions, and whether `ssh-agent + pass` aligns with industry best practices based on research from sources like Arch Wiki, Git documentation, and community discussions (e.g., Stack Exchange, Reddit).

## Why Move from Secret Service (GNOME Keyring)?

GNOME Keyring is excellent for desktop environments but falls short in headless scenarios:

- **GUI Dependency**: It relies on a graphical session (e.g., X11/Wayland) for passphrase prompts and automatic unlocking via PAM. In headless Ubuntu Server or SSH-only sessions, prompts fail, leading to errors like "Connection refused" or repeated manual entries. The daemon expects D-Bus activation in a desktop context, making it unreliable without a display manager.

- **Security and Reliability Issues**: Keys remain in memory without proper session locking, vulnerable to attacks (e.g., DMA). Conflicts arise with other agents (e.g., overriding `SSH_AUTH_SOCK`), and it's prone to bugs in non-GNOME setups. Upstream changes (e.g., separating SSH functionality into `gcr-ssh-agent` in GNOME 46+) have made it less default-friendly.

- **Headless Limitations**: For servers, cron jobs, or containers, CLI tools are preferable. GNOME Keyring doesn't integrate well without forwarding (e.g., `ssh -X`), which isn't practical for automation.

- **Performance and Flexibility**: `ssh-agent` is lightweight and scriptable, with features like key timeouts (`-t`) and confirmations (`-c`). `pass` adds GPG-encrypted storage for passphrases and credentials, enabling secure, automated unlocking without GUI prompts.

This move enhances security (encrypted storage, no plain-text), portability (works across logins/sessions), and compatibility for developers using SSH/Git in mixed environments.

## How to Move: For SSH Keys

Transition to `ssh-agent` for in-memory key management, with `pass` storing passphrases for automatic unlocking.

### Step 1: Disable GNOME Keyring SSH Integration
Prevent conflicts:
```bash
systemctl --user mask gcr-ssh-agent.socket gcr-ssh-agent.service gnome-keyring-daemon.socket
unset SSH_AUTH_SOCK  # Add to ~/.bashrc for persistence
```

### Step 2: Set Up ssh-agent
For automatic startup in headless sessions, add to `~/.bashrc`:
```bash
if ! pgrep -u "$USER" ssh-agent > /dev/null; then
    ssh-agent -t 1h > "$XDG_RUNTIME_DIR/ssh-agent.env"  # 1-hour key lifetime
fi
if [ ! -f "$SSH_AUTH_SOCK" ]; then
    source "$XDG_RUNTIME_DIR/ssh-agent.env" >/dev/null
fi
```
Source your shell: `source ~/.bashrc`.

### Step 3: Integrate with pass for Passphrase Management
Install `pass` and dependencies:
```bash
sudo apt install pass gnupg
```

Initialize `pass` with a GPG key (generate one if needed):
```bash
gpg --full-generate-key  # Follow prompts for a strong key
pass init your-gpg-key-id-or-email
```

Store your SSH key passphrase in `pass` (e.g., for `~/.ssh/id_ed25519`):
```bash
pass insert ssh/my-key-passphrase
```

Create a script for automatic unlocking (e.g., `~/unlock-ssh.sh`):
```bash
#!/bin/bash
export SSH_ASKPASS=/usr/bin/pass
ssh-add -t 1h ~/.ssh/id_ed25519 <<< $(pass ssh/my-key-passphrase)
```
Make executable: `chmod +x ~/unlock-ssh.sh`. Run on demand or add to startup.

For persistence across sessions, use `keychain` (wraps `ssh-agent`):
```bash
sudo apt install keychain
```
Add to `~/.bashrc`:
```bash
eval $(keychain --eval --quiet --nogui id_ed25519)  # --nogui for terminal prompts
```
This prompts once per boot, using `pass` for retrieval if scripted.

Verify: `ssh-add -l` should list keys.

## How to Move: For Git Credentials

Git Credential Manager (GCM) defaults to `secretservice` on desktops but fails headless. Switch to GPG with `pass`.

### Step 1: Install and Configure
```bash
sudo apt install git-credential-manager pass  # Assuming GCM is installed
pass init  # If not done
```

### Step 2: Switch Credential Store
```bash
git config --global credential.credentialStore gpg
```
This uses GPG-encrypted storage via `pass` (in `~/.password-store/`).

For temporary in-memory caching (less persistent):
```bash
git config --global credential.helper cache --timeout=3600  # 1 hour
```

Store credentials: On first `git push/pull` over HTTPS, enter once; `pass` encrypts them.

Custom helper for `pass`: Use `git-credential-pass` (from AUR/contribs) or script:
```bash
git config --global credential.helper '!f() { pass git/credentials; }; f'
```

## Is ssh-agent + pass Industry Best Practice?

Yes, `ssh-agent + pass` is widely regarded as an industry best practice for security-conscious developers on Linux, especially in headless environments. Research highlights:

- **Community Endorsement**: Tools like `pass` (the "standard Unix password manager") are praised for geek/developer workflows (e.g., Reddit discussions on self-hosting and API key management). Integrations with `ssh-agent` for unlocking are common in Stack Exchange and personal blogs, providing automated, encrypted access without GUI.

- **Security Benefits**: SSH keys over passwords are standard (Git docs, Atlassian tutorials). `pass` uses GPG for encryption, avoiding plain-text storage—superior to GNOME Keyring's memory vulnerabilities. Best practices include key rotation, strong algorithms (Ed25519), and timeouts (BeyondTrust, Teleport guides).

- **Headless Suitability**: Arch Wiki recommends standalone `ssh-agent` with `keychain` or `pass` for servers, explicitly noting GNOME Keyring's unsuitability. Git docs advocate GPG/`pass` for credential storage over unencrypted options.

- **Adoption**: Used in DevOps (e.g., automating SSH in scripts), with alternatives like KeePassXC for similar integration. While enterprise tools (e.g., Keeper, Bitwarden) offer SSH agents, `pass` is lightweight and FOSS-preferred for individual developers.

It's not universal (e.g., desktops may stick with Keyring), but for headless Ubuntu, it's efficient and secure.

## Conclusion

This transition streamlines your workflow for headless Ubuntu 24.04+, resolving GUI dependencies while enhancing security. Test in a non-production environment first. For further customization, refer to [[Arch Wiki SSH Keys]] or Git docs.

--- 

*Last updated: December 31, 2025*
