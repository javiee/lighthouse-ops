# AGENTS.md

High-signal facts for working in this repo. Everything else is in `CLAUDE.md`.

## Nix / flake

- **Flakes ignore untracked files.** `git add` new `.nix` or `.age` files before building, or the build fails with "path not tracked by Git."
- The flake evaluates with `allowUnfree = true` globally (in devShells). Packages like `cudaSupport` on nvidia/firefox cascade from a global `nixpkgs.config.cudaSupport = true` — **never set it globally here**. Use per-package `.override { cudaSupport = true; }` (only `llama-cpp` needs it).
- `nixpkgs-unstable` is a pinned input. Use `unstable` from `specialArgs` in host modules for newer packages (e.g., llama-cpp CUDA deps). In dev shells, import directly via the helper shown in `flake.nix`.
- `nix flake check` validates the entire flake (no build). Run it before deploying.
- `nix fmt` formats all `.nix` files.

## Deploying from a Mac

`nixos-rebuild` is not installed on darwin. Use:
```bash
nix run nixpkgs#nixos-rebuild -- switch --flake .#<hostname> \
  --target-host jcaro@<hostname> --build-host jcaro@<hostname> \
  --sudo --ask-sudo-password
```
The `--build-host` flag builds on the Linux target, not the Mac.

## Secrets (agenix)

- Edit: `cd secrets && EDITOR=vim nix run github:ryantm/agenix -- -e <name>.age`
- Rekey after editing `secrets.nix`: `cd secrets && nix run github:ryantm/agenix -- -r`
- Full workflow: `secrets/HELP.md`
- Plaintext lives in `/run/agenix/<host>` (tmpfs). Survives nothing past reboot.

## K3s gotchas

- After changing runtime config (CDI, nvidia), **delete the cached containerd config and restart**:
  ```bash
  rm /var/lib/rancher/k3s/agent/etc/containerd/config.toml
  systemctl restart k3s
  ```
- Flannel uses the LAN interface (not `tailscale0`). `--node-ip` is pinned per host to its LAN address.

## Ops

- **`stalled-download-timeout`** requires the calling user in `nix.settings.trusted-users`. `@wheel` is currently trusted (set in `nix/modules/common.nix`).
- **Tailscale DNS:** Public DNS only works if a Global nameserver is configured in the Tailscale admin panel.
- **First CUDA build on a new host takes hours.** Subsequent builds reuse `/nix/store`.
- NVIDIA CDN downloads are slow/unreliable — avoid `cudaSupport = true` on anything broader than what needs it.

## Dev shell

`nix develop` (or `direnv` via `.envrc`) provides: `kubectl`, `helm`, `fluxcd`, `k9s`, `kubeseal`, `opentofu`, `age`, `agenix`, `gh`, `git`, `jq`, `yq-go`, `opencode`, `aider`, `python3Packages.huggingface-hub` (provides `hf`), `tmux`.

## Git

- **NEVER commit changes** unless the user explicitly asks. The user wants to review changes before committing.
- Never push to any branch without explicit permission.
- **NEVER commit secrets, tokens, passwords, API keys, or any credentials** — not even in `.gitignore` or as comments. Use agenix/sealed-secrets/external secret managers only.

## Things to skip

- `.aider.chat.history.md` — stale LLM chat logs, ignore.
- `requirements.txt` — leftover from an abandoned Flask experiment, not used.
- `README.md` — empty.
