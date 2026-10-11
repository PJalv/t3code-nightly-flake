# t3code-nightly-flake

The latest T3 Code nightly runtime for Nix, with the Android tooling its Device
panel needs. Agent CLIs such as Pi and Codex are not bundled.

The web, server, and desktop JavaScript bundles are built from the pinned
[`pingdotgg/t3code`](https://github.com/pingdotgg/t3code) source revision, then
apply the personal QoL patch recorded in `source.json`. The patch is based on
the exact upstream revision pinned by this flake, so it builds without publishing
the personal source branch. The upstream AppImage supplies Electron and its
prebuilt native modules.

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

Then open the URL printed by the server from a browser. Binding to `0.0.0.0`
makes it reachable from other machines, so use a firewall or trusted network
and follow the pairing/authentication details printed at startup.

Use the full upstream CLI with:

```sh
nix run .#t3 -- --help
```

Agent CLIs, including Pi and Codex, are not bundled. Install them separately,
for example from your NixOS or Home Manager configuration, and make them
available on your `PATH`. The launchers preserve that path; T3 Code runs the
`pi` it finds there unless a binary path is set in its provider settings.

The flake pins `nixpkgs` directly. It does not depend on `llm-agents.nix` or
advertise Numtide's cache.

The launcher also passes Electron's `--ignore-certificate-errors` flag for
development environments that use untrusted HTTPS certificates. This disables
Chromium certificate verification globally within T3 Code and should only be
used with development systems you trust.

## Update policy

Update to the newest available nightly:

```sh
./scripts/update.sh
```

This checkout carries a personal patch. Before upgrading, rebase it on the new
upstream source and refresh the source revision, patch hash, and pnpm dependency
hash together. `./scripts/update.sh --check` only reports the update and does
not change files.

Optionally require a stabilization delay:

```sh
./scripts/update.sh --delay-hours 72
```

The daily GitHub Actions workflow opens an update PR. It also refreshes the
pinned `nixpkgs`, even when the selected T3 Code nightly has not changed. The
delay can be overridden when running the workflow manually.

Do not use T3 Code's npm update action for the Nix-store binary; update the
flake input instead.

## Android device control

T3 Code's Device panel drives iOS Simulators and Android emulators/phones. The
wrappers bundle the host-side Android toolchain — `platform-tools` (`adb`), the
emulator, `cmdline-tools` (`avdmanager`/`sdkmanager`), one `google_apis` API 35
`x86_64` system image, and a JDK — and export `ANDROID_HOME`, `ANDROID_SDK_ROOT`,
and `JAVA_HOME` so the panel can find them without a host Android SDK. Both
launchers also seed the pinned device hub and scrcpy server under T3 home before
the backend starts. The flake packages desktop, server, and web assets; it does
not build or ship the source tree's native mobile app or an APK. Restart the
desktop app after updating the flake; pressing **Refresh devices** alone does
not replace an already-running backend.

An AVD must exist before T3 can start an emulator; create one against the bundled
image, for example:

```sh
avdmanager create avd --name t3-pixel --package 'system-images;android-35;google_apis;x86_64' --device pixel_7
```

The x86_64 emulator needs KVM (`/dev/kvm`) on the host. A physical phone needs
USB debugging enabled and the host key authorized; it appears once `adb devices`
reports it as `device` rather than `unauthorized`. Verify the bundled tooling
with `nix build .#checks.x86_64-linux.android-tooling`.

## Browser previews

T3 Code renders HTML previews and server browser tabs with a pinned Chrome for
Testing headless shell. Upstream downloads it into T3 home, but that build
cannot find its libraries on NixOS, and `t3 browser setup` only knows how to
install Debian packages. The flake builds the same pinned version, patched to
use Nix libraries, and both launchers point T3's install location at it. The
version and checksum are read from the pinned T3 source, so they follow T3
updates. Restart T3 Code after updating the flake so the launcher replaces an
earlier download.

## Platform

Currently packaged for `x86_64-linux`, matching the upstream Linux AppImage.
