# OAuth2-Proxy Setup Guide

## Overview

The OAuth2-proxy integration is now implemented! This guide will help you set up the required secrets and deploy the authentication system.

## What Was Implemented

✅ **Module changes**: `modules/services/surmhosting/default.nix` now supports OAuth2 authentication  
✅ **Secret definitions**: Added to `secrets/config.nix`  
✅ **Pylon configuration**: Auth configured in `machines/pylon/default.nix`  
✅ **Gitea proxy**: Added to pylon as a proxy to nexus with `allowedGitHubUsers = ["surma"]`  
✅ **Build validation**: Assertions ensure all required secrets are configured  

**Important**: Auth runs on **pylon**, not nexus. Gitea is proxied from nexus through pylon with auth protection.

## Architecture

```
Internet → pylon (Traefik + OAuth2-proxy) → nexus (Gitea)
           ↓
           auth-gitea.surma.technology (OAuth2-proxy container)
           ↓
           GitHub OAuth
```

- **One oauth2-proxy container per protected app** on pylon (e.g., `oauth2-proxy-gitea`)
- **IP range**: `10.202.*` for auth containers on pylon
- **Auth subdomains**: `auth-gitea.surma.technology` (on pylon)
- **Shared cookie**: `_oauth2_proxy` @ `.surma.technology` for SSO
- **GitHub-only** authentication with user allowlists
- **Proxy pattern**: Like music, gitea is proxied from nexus through pylon

## Setup Steps

### Step 1: Create GitHub OAuth App

1. Go to https://github.com/settings/developers
2. Click **"New OAuth App"**
3. Fill in:
   - **Application name**: `Pylon Auth`
   - **Homepage URL**: `https://surma.technology`
   - **Authorization callback URL**: `https://auth-*.surma.technology/oauth2/callback`
     - ⚠️ Use the wildcard pattern `auth-*` to support all apps
4. Click **"Register application"**
5. Copy the **Client ID**
6. Click **"Generate a new client secret"**
7. Copy the **Client Secret** (you won't be able to see it again!)

### Step 2: Generate Cookie Secret

Run this command to generate a secure 32-byte cookie secret:

```bash
python -c 'import os,base64; print(base64.urlsafe_b64encode(os.urandom(32)).decode())'
```

Copy the output - you'll need it in the next step.

### Step 3: Get Pylon's Age Public Key

You need pylon's age public key to encrypt the secrets. It's already in your config:

```bash
# From secrets/config.nix line 9:
age1qqgm5u0g6h4xmqnlvvh8xqmgvjxcvgdxjrk6aqvmgxhvlsn9luh
```

Or convert from SSH key:
```bash
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINRS1TLlaWODfefGUvk0mYZEx6pE6Gr2xhsVGbsn91Uh" | ssh-to-age
```

### Step 4: Encrypt and Save Secrets

⚠️ **IMPORTANT**: Replace the placeholder files with real encrypted secrets!

```bash
cd ~/src/github.com/surma/nixenv

# Get pylon's age public key (from secrets/config.nix or convert from SSH)
PYLON_AGE_KEY="age1qqgm5u0g6h4xmqnlvvh8xqmgvjxcvgdxjrk6aqvmgxhvlsn9luh"

# Encrypt GitHub Client ID
echo -n "YOUR_GITHUB_CLIENT_ID" | \
  age -r "$PYLON_AGE_KEY" -o secrets/oauth2-proxy-github-client-id.age

# Encrypt GitHub Client Secret
echo -n "YOUR_GITHUB_CLIENT_SECRET" | \
  age -r "$PYLON_AGE_KEY" -o secrets/oauth2-proxy-github-client-secret.age

# Encrypt Cookie Secret (from Step 2)
echo -n "YOUR_GENERATED_COOKIE_SECRET" | \
  age -r "$PYLON_AGE_KEY" -o secrets/oauth2-proxy-cookie-secret.age
```

**Note**: The current placeholder files are NOT encrypted and will NOT work in production!

### Step 5: Verify DNS Configuration

Ensure you have wildcard DNS configured:

```
*.surma.technology  A  <pylon-ip>
```

Or add individual records:
```
gitea.surma.technology       A  <pylon-ip>
auth-gitea.surma.technology  A  <pylon-ip>
```

### Step 6: Deploy to Pylon

```bash
cd ~/src/github.com/surma/nixenv

# Deploy to pylon (this will decrypt secrets and configure auth)
nixos-rebuild switch --flake .#pylon --target-host pylon --use-remote-sudo
```

### Step 7: Deploy to Nexus

```bash
# Deploy to nexus (this will enable auth on gitea)
nixos-rebuild switch --flake .#nexus --target-host nexus --use-remote-sudo
```

## Testing

### Test 1: Access Gitea

1. Visit `https://gitea.surma.technology`
2. Should redirect to `https://auth-gitea.surma.technology`
3. Should redirect to GitHub OAuth
4. Login with @surma account
5. Should redirect back to gitea
6. Should be able to access gitea

### Test 2: Unauthorized User

1. Logout from GitHub
2. Visit `https://gitea.surma.technology`
3. Login with different GitHub account (not @surma)
4. Should see 403 Forbidden

### Test 3: Container Health

```bash
ssh pylon
nixos-container list  # Should show oauth2-proxy-gitea
nixos-container status oauth2-proxy-gitea  # Should be "up"
```

## Troubleshooting

### Build fails with "clientIdFile is not set"

**Cause**: Auth is enabled but secrets not configured  
**Fix**: Ensure `services.surmhosting.auth.github.clientIdFile` is set in pylon config (already done)

### 502 Bad Gateway on auth-gitea.surma.technology

**Cause**: oauth2-proxy container not running  
**Debug**:
```bash
ssh pylon
nixos-container status oauth2-proxy-gitea
nixos-container run oauth2-proxy-gitea -- systemctl status oauth2-proxy
```

### Redirect loop (keeps redirecting to GitHub)

**Cause**: Cookie not being set properly  
**Debug**: Check browser dev tools → Application → Cookies  
**Expected**: Should see `_oauth2_proxy` cookie for `.surma.technology`

### "Invalid callback URL" from GitHub

**Cause**: Callback URL mismatch  
**Fix**: Ensure GitHub OAuth app has `https://auth-*.surma.technology/oauth2/callback`

### 403 Forbidden even with correct user

**Cause**: Username mismatch or oauth2-proxy config issue  
**Debug**:
```bash
ssh pylon
nixos-container run oauth2-proxy-gitea -- journalctl -u oauth2-proxy -n 50
```
**Check**: Ensure GitHub username matches exactly (case-sensitive)

## Adding More Protected Apps

**Important**: Auth must be configured on **pylon** (where Traefik runs), not on the backend machines.

### For Apps Running on Pylon

Simply add `allowedGitHubUsers` to the exposed app:

```nix
# In machines/pylon/default.nix
services.surmhosting.exposedApps.myapp = {
  target.container = { /* ... */ };
  
  # Add this line:
  allowedGitHubUsers = [ "surma" "stimhub" ];
};
```

### For Apps Running on Other Machines (like Gitea on Nexus)

Create a **proxy service on pylon** that forwards to the backend:

```nix
# In machines/pylon/default.nix
services.surmhosting.exposedApps.myapp = {
  # Proxy to backend machine
  target.host = "myapp.nexus.hosts.100.83.198.90.nip.io";
  target.port = 8080;
  rule = "Host(`myapp.surma.technology`)";
  
  # Enable auth on the proxy
  allowedGitHubUsers = [ "surma" ];
};
```

Then rebuild pylon:
```bash
nixos-rebuild switch --flake .#pylon --target-host pylon --use-remote-sudo
```

## Current Status

- ✅ **Module implemented**: OAuth2-proxy integration complete
- ✅ **Pylon configured**: Auth settings in place
- ✅ **Gitea protected**: Requires @surma authentication
- ⚠️ **Secrets needed**: Replace placeholder files with real encrypted secrets
- ⚠️ **Not deployed**: Waiting for real secrets before deployment

## Next Steps

1. **Create GitHub OAuth App** (Step 1)
2. **Generate cookie secret** (Step 2)
3. **Encrypt secrets** (Step 4)
4. **Deploy to pylon** (Step 6)
5. **Deploy to nexus** (Step 7)
6. **Test authentication** (Testing section)

## Files Modified

- `modules/services/surmhosting/default.nix` - Added OAuth2-proxy support
- `secrets/config.nix` - Added secret definitions
- `machines/pylon/default.nix` - Configured auth + added gitea proxy with auth
- `machines/nexus/default.nix` - No changes (gitea runs without auth, proxied through pylon)
- `secrets/oauth2-proxy-*.age` - Placeholder secret files (REPLACE THESE!)

## Questions?

If you encounter any issues, check:
1. Container logs: `nixos-container run oauth2-proxy-gitea -- journalctl -u oauth2-proxy -f`
2. Traefik logs: `ssh pylon journalctl -u traefik -f`
3. Container status: `ssh pylon nixos-container status oauth2-proxy-gitea`
