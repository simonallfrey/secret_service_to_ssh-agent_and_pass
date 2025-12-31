```bash
#!/usr/bin/env bash
set -euo pipefail

# ================== CUSTOMIZE THESE (or leave defaults) ==================
# Your main SSH private key filename(s) — space-separated
SSH_KEYS="id_ed25519 id_rsa"

# Your GPG key email or ID — WILL PROMPT IF LEFT AS DEFAULT
GPG_KEY="your-email@example.com"

# Optional: Common Git hosts for pre-creating pass folders
GIT_HOSTS="github.com gitlab.com"
# =========================================================================

echo "=== Headless Secure Setup: ssh-agent (keychain) + pass + Git Credential Manager ==="
echo "This script is fully idempotent — safe to run multiple times."
echo

# Prompt for GPG key if default placeholder is still there
if [[ "$GPG_KEY" == "your-email@example.com" ]]; then
    echo "No custom GPG key set. Listing your available secret keys:"
    gpg --list-secret-keys --keyid-format LONG | grep -E '^sec|^uid' || echo "   (No secret keys found)"
    echo
    read -rp "Enter your GPG key ID or email to use with pass (required): " GPG_KEY
    if [[ -z "$GPG_KEY" ]]; then
        echo "Error: No GPG key provided — cannot continue without one."
        exit 1
    fi
    echo "→ Using GPG key: $GPG_KEY"
    echo
fi

# 1. Install core apt packages
echo "1. Installing core tools (pass, keychain, pinentry-tty, gnupg)..."
sudo apt update -qq
sudo apt install -y pass keychain pinentry-tty gnupg

# 2. Install latest Git Credential Manager
echo "2. Installing latest Git Credential Manager from GitHub..."
GCM_DEB="/tmp/gcm-latest.deb"
LATEST_URL=$(curl -s https://api.github.com/repos/git-ecosystem/git-credential-manager/releases/latest \
    | grep "browser_download_url.*gcm-linux_amd64.*\.deb" \
    | cut -d '"' -f 4)

if [[ -z "$LATEST_URL" ]]; then
    echo "Error: Could not find latest GCM release — check your internet connection."
    exit 1
fi

wget -q --show-progress "$LATEST_URL" -O "$GCM_DEB"
sudo dpkg -i --force-confold "$GCM_DEB" || sudo apt-get install -f -y
rm -f "$GCM_DEB"
git-credential-manager configure || true

# 3. Configure headless pinentry
echo "3. Configuring terminal-only GPG prompts (headless friendly)..."
mkdir -p ~/.gnupg
if ! grep -q "pinentry-tty" ~/.gnupg/gpg-agent.conf 2>/dev/null; then
    echo "pinentry-program /usr/bin/pinentry-tty" > ~/.gnupg/gpg-agent.conf
fi
gpg-connect-agent reloadagent /bye >/dev/null

# 4. Initialize pass (idempotent)
echo "4. Initializing/validating Password Store (pass)..."
if ! pass ls >/dev/null 2>&1; then
    echo "   Initializing pass with your GPG key..."
    pass init "$GPG_KEY"
else
    echo "   pass already initialized"
fi

# 5. Disable conflicting GNOME agents
echo "5. Masking GNOME/GCR agents to prevent conflicts..."
systemctl --user mask --now gcr-ssh-agent.socket gcr-ssh-agent.service gnome-keyring-daemon.socket || true

# 6. Add keychain startup to shell files (idempotent)
echo "6. Adding keychain to shell startup files..."
for file in ~/.bashrc ~/.profile; do
    if ! grep -q "keychain.*--nogui" "$file" 2>/dev/null; then
        cat >> "$file" <<EOF

# --- keychain: headless ssh-agent management ---
eval \$(keychain --eval --quiet --nogui $SSH_KEYS)
# -------------------------------------------------------
EOF
        echo "   Added to $file"
    fi
done

# 7. Configure GCM to use GPG/pass backend
echo "7. Configuring Git Credential Manager to use secure GPG backend..."
git config --global credential.credentialStore gpg

# Optional: pre-create common host folders
if [[ -n "$GIT_HOSTS" ]]; then
    echo "8. Pre-creating pass folders for common Git hosts..."
    for host in $GIT_HOSTS; do
        pass mkdir -p "git/$host" 2>/dev/null || true
    done
fi

# ====================== VERIFICATION ======================
echo
echo "=== VERIFICATION: Checking your installation ==="

passed=true

command -v keychain >/dev/null && echo "✓ keychain installed" || { echo "✗ keychain missing"; passed=false; }
command -v pass >/dev/null && pass ls >/dev/null 2>&1 && echo "✓ pass installed and initialized" || { echo "✗ pass issue"; passed=false; }
command -v git-credential-manager >/dev/null && echo "✓ Git Credential Manager installed" || { echo "✗ GCM missing"; passed=false; }
git config --global credential.credentialStore | grep -q "gpg" && echo "✓ GCM using GPG backend" || { echo "⚠ GCM not using gpg store"; passed=false; }

eval "$(keychain --eval --quiet --nogui $SSH_KEYS 2>/dev/null || true)"
[[ -n "${SSH_AUTH_SOCK:-}" && -S "$SSH_AUTH_SOCK" ]] && echo "✓ ssh-agent running" || { echo "✗ ssh-agent not running"; passed=false; }

if $passed; then
    echo
    echo "🎉 SUCCESS! Your headless setup is complete and verified."
else
    echo
    echo "⚠ Some checks failed — please review above and re-run the script."
    exit 1
fi

# ====================== HOW TO CHECK & DAILY WORKFLOW ======================
echo
echo "=========================================================================="
echo "                           YOUR NEW WORKFLOW"
echo "=========================================================================="
echo
echo "1. How to verify everything is working (run anytime):"
echo "   Open a new terminal and run:"
echo "       ssh-add -l                     # Lists loaded keys"
echo "       ssh -T git@github.com          # Test SSH to GitHub"
echo "       git ls-remote https://github.com/some/repo.git   # Test HTTPS"
echo
echo "2. Daily workflow (what happens automatically now):"
echo "   • Every new terminal or SSH login:"
echo "       → keychain starts/reuses ssh-agent"
echo "       → Your keys ($SSH_KEYS) are added automatically"
echo "       → If passphrase-protected: you are prompted ONCE in the terminal"
echo
echo "   • Git over SSH: no prompts ever (after first key add)"
echo
echo "   • Git over HTTPS:"
echo "       → First time per host: enter username + token/PAT in terminal"
echo "       → Credential is encrypted with your GPG key and stored in pass"
echo "       → All future operations: completely silent"
echo
echo "3. Optional: Make SSH completely silent (zero passphrase prompts)"
echo "   If you want no prompts at all:"
echo "       ssh-add ~/.ssh/id_ed25519      # enter passphrase once"
echo "       pass insert -e ssh/id_ed25519-passphrase"
echo "   (Advanced users can script pulling from pass)"
echo
echo "You're all set! Enjoy a secure, headless, zero-maintenance workflow. 🚀"
echo
```

### Features of this final version

- **Fully idempotent** — can be run repeatedly without side effects.
- **User-friendly GPG prompt** — lists your keys and forces a valid entry.
- **Robust GCM install** — pulls the absolute latest version safely.
- **Clear step-by-step progress** with numbered sections.
- **Built-in verification** — fails loudly if anything is wrong.
- **Comprehensive final explanation** — tells the user exactly how to check the install and what their daily workflow now looks like.

Save as `install.sh`, `chmod +x install.sh`, run it once — and you're done forever.

Let me know when you run it and what the final output says — you should get that big "SUCCESS!" message and a clean workflow from now on! 🎉
