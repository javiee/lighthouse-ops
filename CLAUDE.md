# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Authorization

Claude is authorized to deploy NixOS configurations and apply GitOps changes in this repo without per-command confirmation, including `nixos-rebuild switch`, `nix flake update`, and `git push` to feature branches. Still confirm before:

- Force-pushing to any branch
- `nixos-rebuild switch` to a host with running workloads, when the change is non-trivial (kernel, network, k3s)
- Destructive operations (k3s wipe, etcd reset, secret deletion, branch deletion)
- Anything touching `main`

## Common commands

```bash
# Validate the entire flake (eval check, no build)
nix flake check

# Format all Nix files
nix fmt

# Build a host configuration locally — does not deploy
nix build .#nixosConfigurations.<hostname>.config.system.build.toplevel

# Deploy to a remote host immediately (activate on apply)
nixos-rebuild switch --flake .#<hostname> --target-host <hostname> --use-remote-sudo

# Deploy safely (activates on next reboot — for kernel/early-boot changes)
nixos-rebuild boot --flake .#<hostname> --target-host <hostname> --use-remote-sudo

# Update all flake inputs
nix flake update

# Rollback to the previous system generation (run on the target host)
sudo nixos-rebuild switch --rollback
```

### Deploying from a Mac without `nixos-rebuild` installed

```bash
nix run nixpkgs#nixos-rebuild -- switch --flake .#<hostname> \
  --target-host jcaro@<hostname> --build-host jcaro@<hostname> \
  --sudo --ask-sudo-password
```

The `--build-host` flag points at the target so the build happens on the Linux host, not the darwin Mac.

## Hosts

| Host | Role | Notable modules |
|---|---|---|
| `lh-satellite` | K3s server (clusterInit, embedded etcd), Flux GitOps source, kube-prometheus-stack, XFCE workstation | `k3s-bootstrap.nix`, `flux-bootstrap.nix`, `workstation.nix` |
| `leviathan` | K3s agent, GPU-accelerated LLM host (llama.cpp via llama-swap, Lemonade) | `k3s-join.nix`, `amdgpu.nix`, `llama-cpp.nix`, `llama-swap.nix`, `lemonade.nix` |

## Architecture

### Repo layout

```
flake.nix                       — defines nixosConfigurations.<host> for each entry below
nix/
  hosts/
    lh-satellite/{default,hardware}.nix
    leviathan/{default,hardware}.nix
  modules/
    common.nix                  — shared base (locale, boot, base packages, including opencode)
    workstation.nix             — XFCE + audio + printing + firefox
    ssh.nix, users.nix, tailscale.nix
    amdgpu.nix                  — amdgpu driver + ROCm userspace (kernel/ROCm from unstable)
    llama-cpp.nix               — llama.cpp (TurboQuant fork) built with GGML_HIP for gfx1201
    llama-swap.nix              — model swapper / OpenAI API on :9090 (the primary LLM path)
    lemonade.nix                — AMD Lemonade server on :13305 via noamsto/nix-amd-ai
    k3s-bootstrap.nix           — server (clusterInit=true, embedded etcd)
    k3s-join.nix                — agents/HA peers (serverAddr to bootstrap node)
    flux-bootstrap.nix          — one-shot systemd unit that runs `flux bootstrap` once
secrets/
  secrets.nix                   — agenix recipients (user age key + each host's SSH host key)
  *.age                         — agenix-encrypted secrets (token files etc.)
  CHEATSHEET.md                 — agenix workflow reference (add new hosts, rekey, recover)
gitops/
  lighthouse-cluster/           — flux bootstrap target (cluster entry point)
  infrastructure/base/          — shared infra HelmReleases (Prometheus, DCGM, etc.)
  apps/                         — workload manifests (currently empty)
```

### Multi-host pattern

`flake.nix` defines a `mkHost` helper that threads the hostname into the host's module via `specialArgs.hostname`. Adding a new host means:

1. `nix/hosts/<name>/default.nix` (imports + hostname + stateVersion)
2. `nix/hosts/<name>/hardware.nix` (generated via `nixos-generate-config` on the box)
3. Append `<name> = mkHost "<name>";` to `nixosConfigurations` in `flake.nix`
4. Add the new host's SSH host key to `secrets/secrets.nix`, then `agenix -r` to rekey

### Secrets via agenix

- `agenix.nixosModules.default` is passed to every host through `flake.nix`.
- Each host can decrypt secrets it's a recipient of, using `/etc/ssh/ssh_host_ed25519_key` at activation. Plaintext lands in `/run/agenix/<name>` (tmpfs).
- All editing happens on the Mac with the user's age key. Adding a new host requires getting its SSH host pubkey (post-install) and adding it to `secrets/secrets.nix`, then `nix run github:ryantm/agenix -- -r` to rekey. If a file can't be decrypted from the Mac (recipient mismatch), see `secrets/CHEATSHEET.md`.

### K3s topology

Embedded-etcd HA-ready cluster. `lh-satellite` initialised with `clusterInit = true`. Additional servers or agents join via `k3s-join.nix`, which reads the same shared token from agenix. Flannel uses the LAN interface (NOT tailscale0) — `--node-ip` is pinned per host to its LAN address so etcd peer URLs stay stable.

### GitOps via Flux

Flux is bootstrapped onto `lh-satellite` by `nix/modules/flux-bootstrap.nix` — a one-shot systemd unit gated by `/var/lib/flux/.bootstrapped`. It points at `github.com/javiee/lighthouse-ops` at path `gitops/lighthouse-cluster`. Anything dropped in `gitops/infrastructure/base/` is picked up by Flux via a Kustomization (see `gitops/lighthouse-cluster/infrastructure.yaml` once present).

### AMD GPU on leviathan

Radeon AI PRO R9700 — Navi 48 (RDNA 4), LLVM target `gfx1201`, 32 GB GDDR6.

The in-tree `amdgpu` kernel driver binds the card via PCI IP-discovery (the catch-all `pci:v00001002d*...bc03sc00i00*` alias) and loads GC 12.0.x microcode from `linux-firmware`, which is already present because `hardware.enableRedistributableFirmware` is on. There is no out-of-tree module and no unfree driver.

**The GPU stack comes from `nixpkgs-unstable`, not 25.11.** The host is still a nixos-25.11 system — only the kernel, firmware, ROCm and llama.cpp are pulled forward via `_unstablePkgs`, the same way `llama-swap.nix` already does:

| | 25.11 | unstable |
|---|---|---|
| kernel | 6.12.93 (Navi 48 only via the IP-discovery catch-all) | **6.18.48** (first-class) |
| ROCm | 6.4.3 | **7.2.3** |
| linux-firmware | 20260519 | **20260810** |

Kernel and `linux-firmware` are deliberately taken from the *same* nixpkgs so a 6.18 driver never asks 25.11's older firmware for a blob it doesn't ship. `hardware.firmware` is set with `lib.mkBefore`, and since its `buildEnv` runs with `ignoreCollisions`, the newer blobs win.

`hardware.amdgpu.opencl.enable` is deliberately **not** used: it wires 25.11's `rocmPackages.clr` (6.4.3), which would leave OpenCL on ROCm 6 while HIP runs on 7.2.3. `hardware.graphics.extraPackages` names the unstable `clr` + its ICD instead.

`llama-cpp.nix` builds the *entire* derivation from unstable, stdenv included — a 25.11 stdenv linked against unstable's ROCm would put two glibcs in one process.

No container runtime shim is needed — AMD GPUs reach containers through `/dev/kfd` + `/dev/dri`, not a custom OCI runtime. Nothing in `gitops/` currently requests a GPU, so no RuntimeClass or device plugin is deployed.

### LLM serving on leviathan

Two servers, mutually exclusive by systemd `Conflicts=` (the card has 31.86 GiB and one resident model is ~20-23 GiB):

- **llama-swap** (`:9090`) — the fast path. Full llama.cpp flag control: TurboQuant `turbo4` KV cache plus `--spec-type draft-mtp`. Measured 50.2 tok/s on Qwen3.8-27B-Q4_K_XL, vs 27.1 without MTP.
- **lemonade** (`:13305`) — model manager, web UI, and the multimodal extras. `autoStart = false`, so llama-swap owns the GPU at boot; `systemctl start lemond` takes it, `systemctl start llama-swap` takes it back.

Ollama was removed 2026-09-07: it had never served a request, held no models, and duplicated both servers for 4.1 GiB of closure.

**Gotcha:** lemonade's `llamacpp.backend` must be pinned to `rocm`. On `auto` it prefers a `llama-server` found on PATH — which is our TurboQuant fork from `llama-cpp.nix` — then injects its own upstream `libggml-hip.so` into it. Two incompatible llama.cpp builds in one process, SIGSEGV at warmup.

## Deployment workflow gotchas

- **Flakes ignore untracked files.** After creating new `.nix`/`.age` files, `git add` (no commit needed) before `nixos-rebuild`. Otherwise the build fails with "path not tracked by Git."
- **Privileged nix options** (`stalled-download-timeout`, `extra-substituters`, `extra-trusted-public-keys`) are ignored for untrusted users — silently, so the symptom is "it rebuilt everything from source". `nix.settings.trusted-users = [ "root" "@wheel" ]` is set in `common.nix`. NOTE: this was documented as true long before it actually was; the live daemon reported `trusted-users = root` until 2026-09-06.
- **Never set `nixpkgs.config.rocmSupport = true` globally.** Like `cudaSupport` before it, it cascades into unrelated packages and forces enormous local rebuilds. Scope ROCm per-package (`llama-cpp.nix` is the only one).
- **Keep ROCm libraries on their default multi-arch build.** `rocmPackages.gfx1201` is a valid single-arch scope, but it busts the binary cache and rebuilds rocBLAS/hipBLASLt locally (hours). Pin the arch with `-DCMAKE_HIP_ARCHITECTURES=gfx1201` on our own code instead.
- **The GPU stack straddles two nixpkgs.** `nix flake update` moves `nixpkgs-unstable`, and that changes leviathan's *kernel*, not just userspace. Prefer `nixos-rebuild boot` over `switch` after an unstable bump.
- **Tailscale DNS:** with `accept-dns=true` (default), public DNS only works if a Global nameserver is set in the Tailscale admin (https://login.tailscale.com/admin/dns).
- **One-time, at the NVIDIA→AMD migration:** k3s caches its containerd config, which still registers the now-gone `nvidia` runtime handler. Delete it and restart so it regenerates:
  ```bash
  sudo rm /var/lib/rancher/k3s/agent/etc/containerd/config.toml
  sudo systemctl restart k3s
  ```

## Reference

- agenix workflow: `secrets/CHEATSHEET.md`
- nixpkgs options search: https://search.nixos.org/options
- systemd unit options: `man 5 systemd.service`, `man 5 systemd.exec`
