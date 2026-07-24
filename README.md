# t3code-nightly-flake

T3 Code nightlies for Nix, held back for a short stabilization window and
bundled with Codex from [`numtide/llm-agents.nix`](https://github.com/numtide/llm-agents.nix).

The default policy selects the newest upstream nightly that is at least 48
hours old. This is age-based rather than “two release numbers behind,” because
upstream can publish several nightlies in one day.

## Run

From a local checkout:

```sh
nix run .
```

After publishing the repository:

```sh
nix run github:YOUR-USER/t3code-nightly-flake
```

Or use it as an input:

```nix
{
  inputs.t3code-nightly.url = "github:YOUR-USER/t3code-nightly-flake";
}
```

The package is available as:

```nix
inputs.t3code-nightly.packages.${pkgs.system}.t3code
```

The launcher prepends the pinned `llm-agents.nix` Codex package to `PATH`, so
T3 Code consistently sees the bundled CLI rather than a host installation.
The flake follows the `nixpkgs` revision used by `llm-agents.nix` and advertises
Numtide's binary cache, allowing Codex to be substituted instead of rebuilt
when the local Nix daemon trusts that cache.

## Update policy

Update to the newest nightly at least 48 hours old:

```sh
./scripts/update.sh
```

Use a different delay:

```sh
./scripts/update.sh --delay-hours 72
```

The daily GitHub Actions workflow opens an update PR. It also refreshes
`nixpkgs` and `llm-agents`, even when the selected T3 Code nightly has not
changed, so the bundled Codex does not unnecessarily fall behind npm. The
delay can be overridden when running the workflow manually.

T3 Code compares the installed Codex version with the latest npm release. If
`llm-agents.nix` briefly trails npm, T3 Code may show an update notice even
though the bundled CLI is working. Do not use T3 Code's npm update action for
the Nix-store binary; either wait for the next automated input refresh or turn
off **provider update checks** in T3 Code's settings.

## Platform

Currently packaged for `x86_64-linux`, matching the upstream Linux AppImage.
