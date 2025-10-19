# SSH Keys for Private Repository Access

This directory should contain your SSH private keys for accessing private repositories.

## Setup Instructions:

### For private repositories, copy your SSH keys here:

```bash
# Copy your private key (choose the one you use)
cp ~/.ssh/id_rsa ./ssh-keys/id_rsa
# OR
cp ~/.ssh/id_ed25519 ./ssh-keys/id_ed25519

# Set proper permissions
chmod 600 ./ssh-keys/id_rsa
# OR  
chmod 600 ./ssh-keys/id_ed25519
```

### Alternative: Use HTTPS with Personal Access Tokens

Instead of SSH keys, you can use HTTPS URLs with embedded tokens:

**GitHub:**
```
https://username:ghp_token123@github.com/owner/private-repo.git
```

**GitLab:**
```
https://username:glpat-token123@gitlab.com/owner/private-repo.git
```

## Security Notes:

- SSH keys in this directory will be mounted read-only into the webhook container
- Keys are only accessible during git clone operations
- Consider using deploy keys with read-only access instead of personal SSH keys
- Make sure to add this directory to .gitignore if it contains real keys

## Current Status:

- Directory created: ✅
- SSH keys: Not configured (add your keys as described above)