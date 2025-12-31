#!/usr/bin/env bash
set -euo pipefail

echo "=== Sanity Check: Headless ssh-agent + pass + GCM Setup ==="
echo "Running as user: $(whoami) on $(hostname)"
echo "Date: $(date)"
echo

# 1. Check keychain
echo "1. Checking keychain..."
if command -v keychain >/dev/null 2>&1; then
    echo "   ✓ keychain is installed ($(which keychain))"
else
    echo "   ✗ keychain NOT found"
    exit 1
fi

# 2. Check pass
echo "2. Checking pass (Password Store)..."
if command -v pass >/dev/null 2>&1; then
    echo "   ✓ pass is installed ($(which pass))"
    if pass ls >/dev/null 2>&1; then
        echo "   ✓ pass is initialized and accessible"
    else
        echo "   ⚠ pass installed but not initialized (run 'pass init <gpg-id>')"
    fi
else
    echo "   ✗ pass NOT found"
    exit 1
fi

# 3. Check Git Credential Manager
echo "3. Checking Git Credential Manager..."
if command -v git-credential-manager >/dev/null 2>&1; then
    echo "   ✓ git-credential-manager is installed ($(which git-credential-manager))"
    if git config --global credential.credentialStore | grep -q "gpg"; then
        echo "   ✓ GCM configured to use GPG backend (headless-friendly)"
    else
        echo "   ⚠ GCM installed but not using 'gpg' store (run: git config --global credential.credentialStore gpg)"
    fi
else
    echo "   ✗ git-credential-manager NOT found"
    exit 1
fi

# 4. Check pinentry (headless prompt)
echo "4. Checking pinentry-tty..."
if [ -f ~/.gnupg/gpg-agent.conf ] && grep -q "pinentry-tty" ~/.gnupg/gpg-agent.conf; then
    echo "   ✓ pinentry-tty configured for headless use"
else
    echo "   ⚠ pinentry-tty not configured (~/.gnupg/gpg-agent.conf missing or wrong)"
fi

# 5. Check ssh-agent via keychain
echo "5. Testing ssh-agent startup..."
echo "   Running keychain evaluation..."
eval "$(keychain --eval --quiet --nogui id_ed25519 id_rsa 2>/dev/null || true)"

if [ -n "${SSH_AUTH_SOCK:-}" ] && [ -S "$SSH_AUTH_SOCK" ]; then
    echo "   ✓ ssh-agent is running (SSH_AUTH_SOCK=$SSH_AUTH_SOCK)"
else
    echo "   ✗ ssh-agent failed to start or socket missing"
    exit 1
fi

# 6. List loaded keys
echo "6. Currently loaded SSH keys:"
if ssh-add -l >/dev/null 2>&1; then
    ssh-add -l
else
    echo "   No keys loaded yet (normal if not added)"
    echo "   To add: ssh-add ~/.ssh/id_ed25519"
fi

# 7. Check startup files
echo "7. Checking shell startup files..."
for file in ~/.bashrc ~/.profile; do
    if [ -f "$file" ] && grep -q "keychain" "$file"; then
        echo "   ✓ keychain line present in $file"
    else
        echo "   ⚠ keychain missing from $file"
    fi
done

echo
echo "=== SUMMARY ==="
if [ -n "${SSH_AUTH_SOCK:-}" ] && command -v keychain >/dev/null && command -v pass >/dev/null && command -v git-credential-manager >/dev/null; then
    echo "✓ OVERALL: Your headless setup looks SANE and READY!"
    echo "  Next: Try 'ssh -T git@github.com' and 'git ls-remote https://github.com/some/repo'"
else
    echo "✗ Issues detected — review the checks above"
    exit 1
fi
