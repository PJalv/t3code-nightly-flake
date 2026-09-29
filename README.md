# t3code-nightly-flake

The latest T3 Code nightly runtime for Nix, bundled with Codex from
[`numtide/llm-agents.nix`](https://github.com/numtide/llm-agents.nix) and Pi 0.99.1
from the `git.pjalv.com/PJalv/pi-copilot` fork.

The web, server, and desktop JavaScript bundles are built from the pinned
[`PJalv/t3code`](https://github.com/PJalv/t3code) source fork. The upstream
AppImage supplies Electron and its prebuilt native modules.

The default policy selects the newest available upstream nightly. An optional
minimum release age can still be supplied to the updater when desired.

## Run

From a local checkout:

```sh
nix run .
```

After publishing the repository:

```sh
nix run github:PJalv/t3code-nightly-flake
```

Or use it as an input:

```nix
{
  inputs.t3code-nightly.url = "github:PJalv/t3code-nightly-flake";
}
```

The package is available as:

```nix
inputs.t3code-nightly.packages.${pkgs.system}.t3code
```

## Headless server

The matching nightly npm server is exposed as `server`, `t3code-server`, and
`t3`. Run it without opening a local browser with:

```sh
nix run .#server -- --host 0.0.0.0 --port 13773
```

The server packages disable T3 Code's hidden Git checkpoints by default. Those
checkpoints run `git add -A` against the project workspace at turn boundaries,
which can be prohibitively expensive for large repositories containing build
artifacts. The source build honors `T3_DISABLE_CHECKPOINTS=1`, and its wrappers
set that variable automatically.

The patched source also adds **Provider-native file changes** under Settings →
General. When enabled, T3 Code records file diffs reported by Codex and OpenCode,
including absolute paths outside the selected project and files in non-Git
directories. This review feature is independent from Git checkpoints.

To retain upstream checkpoint behavior, use the explicit opt-in variant:

```sh
nix run .#server-with-checkpoints -- --host 0.0.0.0 --port 13773
```

The default desktop package also disables checkpoints. To run the desktop
application with upstream checkpoint behavior, use:

```sh
nix run .#desktop-with-checkpoints
```

Then open the URL printed by the server from a browser. Binding to `0.0.0.0`
makes it reachable from other machines, so use a firewall or trusted network
and follow the pairing/authentication details printed at startup.

Use the full upstream CLI with:

```sh
nix run .#t3 -- --help
```

The launcher prepends the pinned Codex and Pi packages to `PATH`, so T3 Code
consistently sees the bundled CLIs rather than host installations. Pi includes
the fork's OpenCode-aligned Copilot provider and T3 RPC compaction fixes.
MCP uses Pi's built-in support. Configure servers in `~/.pi/agent/mcp.json` or
in a trusted project's `.pi/mcp.json`, and manage them with `pi mcp` or `/mcp`.
T3 registers its authenticated `t3-code` server for each session without
rewriting either config file. Do not add a separate `t3-code` entry unless you
intend to override T3's session connection; native Pi gives configured servers
precedence over extension registrations.

The adapter is no longer bundled. If you installed `pi-mcp-adapter` yourself,
remove it with `pi remove npm:pi-mcp-adapter`; otherwise it disables Pi's native
MCP extension. The wrapper warns about installed copies but does not edit your
settings. Existing adapter-only options, such as `directTools` and `lifecycle`,
are not native MCP settings. Use `exposure: "direct"` for directly declared
tools; native MCP defaults to calling server tools through codemode.

The wrapper still loads `@tintinweb/pi-subagents` 0.19.0 for the `Agent` tool,
foreground and background work, durable agent IDs, and targeted Stop. Remove
separately installed copies to avoid loading it twice.

T3 Code translates native MCP calls into MCP tool rows and subagent activity
into the Agents panel and per-agent usage without replacing `~/.pi/agent`.
Its RPC-only bridge registers the session MCP server and carries versioned
lifecycle events and targeted subagent control; it does not fork or import
pi-subagents internals.

The flake follows the `nixpkgs` revision used by `llm-agents.nix` and advertises
Numtide's binary cache, allowing the agent CLIs to be substituted instead of
rebuilt when the local Nix daemon trusts that cache.

The launcher also passes Electron's `--ignore-certificate-errors` flag for
development environments that use untrusted HTTPS certificates. This disables
Chromium certificate verification globally within T3 Code and should only be
used with development systems you trust.

## Update policy

Update to the newest available nightly:

```sh
./scripts/update.sh
```

Optionally require a stabilization delay:

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

## Android device control

T3 Code's Device panel drives iOS Simulators and Android emulators/phones. The
wrappers bundle the host-side Android toolchain — `platform-tools` (`adb`), the
emulator, `cmdline-tools` (`avdmanager`/`sdkmanager`), one `google_apis` API 35
`x86_64` system image, and a JDK — and export `ANDROID_HOME`, `ANDROID_SDK_ROOT`,
and `JAVA_HOME` so the panel can find them without a host Android SDK. Both
launchers also seed the pinned device hub and scrcpy server under T3 home before
the backend starts. Restart the desktop app after updating the flake; pressing
**Refresh devices** alone does not replace an already-running backend.

An AVD must exist before T3 can start an emulator; create one against the bundled
image, for example:

```sh
avdmanager create avd --name t3-pixel --package 'system-images;android-35;google_apis;x86_64' --device pixel_7
```

The x86_64 emulator needs KVM (`/dev/kvm`) on the host. A physical phone needs
USB debugging enabled and the host key authorized; it appears once `adb devices`
reports it as `device` rather than `unauthorized`. Verify the bundled tooling
with `nix build .#checks.x86_64-linux.android-tooling`.

## Platform

Currently packaged for `x86_64-linux`, matching the upstream Linux AppImage.
