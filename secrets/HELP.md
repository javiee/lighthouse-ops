# agenix cheatsheet

Quick reference for managing the encrypted secrets in this directory.
Each `.age` file is encrypted to the recipients listed in `secrets.nix`.

## Daily operations

### Edit (or create) a secret

```bash
cd secrets
EDITOR=vim nix run github:ryantm/agenix -- -e <name>.age
```

Opens the decrypted content in `$EDITOR`. On save, re-encrypts to **all current
recipients** in `secrets.nix`. Use this to:

- Create a new secret (file doesn't exist yet → empty buffer)
- Rotate a token (replace contents)
- Inspect a secret (open, don't change, `:q` without writing)

### View a secret (read-only, no editor)

```bash
age -d -i ~/.config/age/keys.txt secrets/<name>.age
```

Or from the satellite where agenix already decrypted at boot:

```bash
ssh jcaro@192.168.10.122 'sudo cat /run/agenix/<name>'
```

### Re-encrypt after editing `secrets.nix`

When you change the recipient list (e.g. added a new host), rekey all files:

```bash
cd secrets
nix run github:ryantm/agenix -- -r
```

Requires that **your local key can already decrypt** each file. If it can't, see
"Recovery" below.

## Adding a new host

1. After first boot, grab its SSH host pubkey:
   ```bash
   ssh jcaro@<new-host> 'cat /etc/ssh/ssh_host_ed25519_key.pub'
   ```
2. Add to `secrets.nix`:
   ```nix
   new-host = "ssh-ed25519 AAAA... root@new-host";
   allHosts = [ lh-satellite leviathan new-host ];
   ```
3. Rekey:
   ```bash
   nix run github:ryantm/agenix -- -r
   ```
4. Stage and redeploy:
   ```bash
   git add secrets/
   nixos-rebuild switch --flake .#<new-host> ...
   ```

## Recovery: "no identity matched any of the recipients"

Means your local age key isn't a recipient on the file. Two paths:

### A. Re-encrypt from an existing recipient (preserves the secret value)

```bash
# 1. Decrypt on a host that IS a recipient
ssh jcaro@192.168.10.122 'sudo cat /run/agenix/<name>' > /tmp/plaintext

# 2. Delete the unreadable file
rm secrets/<name>.age

# 3. Recreate, encrypting to current recipients
cd secrets
EDITOR=vim nix run github:ryantm/agenix -- -e <name>.age
# paste contents of /tmp/plaintext, save & quit

# 4. Clean up
shred -u /tmp/plaintext
```

### B. Recreate from scratch (loses the previous secret value)

```bash
rm secrets/<name>.age
EDITOR=vim nix run github:ryantm/agenix -- -e <name>.age
# enter fresh value (new PAT, fresh random token, etc.)
```

For tokens that other systems still use (e.g. k3s join token), prefer (A) —
changing the value mid-cluster can break running nodes.

## Initial setup

### Generate your personal age key (one time)

```bash
mkdir -p ~/.config/age
age-keygen -o ~/.config/age/keys.txt
chmod 600 ~/.config/age/keys.txt
age-keygen -y ~/.config/age/keys.txt   # prints the public key
```

Add the printed `age1...` line as your `javier` recipient in `secrets.nix`.

### Get a host's SSH host pubkey

```bash
# Remote
ssh-keyscan -t ed25519 <host>           # via TOFU
ssh jcaro@<host> 'cat /etc/ssh/ssh_host_ed25519_key.pub'

# Local (run on the host itself)
cat /etc/ssh/ssh_host_ed25519_key.pub
```

agenix accepts both age (`age1...`) and SSH ed25519 (`ssh-ed25519 AAAA...`)
formats as recipients.

## Things to remember

- **Edit creates with current recipients.** No need to rekey a file you just
  created.
- **Rekey requires a working identity.** If you can't decrypt, you can't rekey —
  recreate the file instead.
- **`secrets.nix` is the source of truth for recipients.** Edit it, then rekey
  (or recreate) so the `.age` files reflect the new set.
- **`.age` files are content-addressed by their recipient list.** Same plaintext +
  different recipients = different ciphertext. That's expected.
- **Plaintext on hosts lives only in tmpfs** (`/run/agenix/`). Survives nothing
  past reboot — agenix re-decrypts each time using the host's SSH key.
- **Back up `~/.config/age/keys.txt`** somewhere (1Password, encrypted drive).
  Losing it means losing access to every secret you're a recipient of.

## Useful subcommands

```bash
# What does my age key look like?
age-keygen -y ~/.config/age/keys.txt

# Decrypt a file to stdout (read-only)
age -d -i ~/.config/age/keys.txt secrets/<name>.age

# Quick decrypt without prompting (uses default editor + caches result)
EDITOR=cat nix run github:ryantm/agenix -- -e secrets/<name>.age

# List all secrets defined in secrets.nix
nix eval --file secrets.nix --json | jq 'keys'
```
