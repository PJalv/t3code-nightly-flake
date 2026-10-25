{
  description = "Latest T3 Code nightly with its Android device tooling";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    t3code-source = {
      url = "github:pingdotgg/t3code/5f64c5eb299a23d278ef043c416bd4dc801bc53c";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, t3code-source }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        # Android SDK components use Google's unfree license; the SDK
        # composition below explicitly accepts that license.
        config.allowUnfree = true;
      };
      lib = pkgs.lib;
      source = lib.importJSON ./source.json;
      # The repo pins packageManager pnpm@12.14.0. pnpm rewrites itself to the
      # pinned version unless told otherwise, and 12.14.0's npm tarball no longer
      # ships the `dist/vendor` tree that nixpkgs' pnpm builder unpacks, so it
      # cannot be packaged here. The pinned nixpkgs pnpm installs the same
      # lockfile; package-source.nix stops it from self-upgrading first.
      pnpmPinned = pkgs.pnpm;
      spdxLicenseData = pkgs.fetchFromGitHub {
        owner = "spdx";
        repo = "license-list-data";
        rev = "c4a7237ec8f4654e867546f9f409749300f1bf4c";
        hash = "sha256-FbeeEBAg9ih6DkAsXdU6ruZwkC7A2u2zYBvblpl54q0=";
      };
      sourceAssets = pkgs.callPackage ./package-source.nix {
        src = t3code-source;
        inherit (source) version;
        pnpm_11 = pnpmPinned;
        inherit spdxLicenseData;
      };
      scrcpyServer = pkgs.callPackage ./package-scrcpy-server.nix { };
      deviceHub = pkgs.callPackage ./package-device-hub.nix { inherit scrcpyServer; };
      seedDeviceHub = pkgs.writeShellScript "t3code-seed-device-hub"
        (import ./seed-device-hub.nix { inherit deviceHub; });
      # Read T3's pinned headless-browser build from its source so the Nix build
      # always matches what T3 would download.
      previewBrowserPin =
        let
          lines = lib.splitString "\n" (builtins.readFile "${t3code-source}/apps/server/src/preview/PreviewBrowser.ts");
          capture = pattern: lib.findFirst (m: m != null) null (map (builtins.match pattern) lines);
          linux64Index = lib.lists.findFirstIndex (line: builtins.match " *linux64: \\{" line != null) null lines;
          linux64 = if linux64Index == null then [ ] else lib.sublist (linux64Index + 1) 3 lines;
          version = capture ''const VERSION = "([0-9.]+)";'';
          sha256 = lib.findFirst (m: m != null) null (map (builtins.match "[ ]*sha256: \"([0-9a-f]{64})\",") linux64);
        in
        assert lib.assertMsg (version != null && sha256 != null)
          "Could not read the linux64 headless-browser pin from PreviewBrowser.ts; update the parser in flake.nix.";
        { version = builtins.head version; sha256 = builtins.head sha256; };
      chromeHeadlessShell = pkgs.callPackage ./package-chrome-headless-shell.nix {
        inherit (previewBrowserPin) version sha256;
      };
      seedChromeHeadlessShell = pkgs.writeShellScript "t3code-seed-chrome-headless-shell"
        (import ./seed-chrome-headless-shell.nix { inherit chromeHeadlessShell; });
      # Each launcher runs this before T3 starts, so neither falls back to an
      # npm or Chrome download at runtime.
      seedTools = pkgs.writeShellScript "t3code-seed-tools" ''
        ${seedDeviceHub}
        ${seedChromeHeadlessShell}
      '';
      androidComposition = (pkgs.androidenv.override { licenseAccepted = true; }).composeAndroidPackages {
        platformVersions = [ "35" ];
        includeEmulator = "if-supported";
        # An installed system image is required before `avdmanager create avd`
        # can build an AVD, and nixpkgs patches the google_apis images so the
        # emulator and avdmanager recognise their ABI. Pin this to a single
        # type/ABI: the upstream defaults expand to four types across four ABIs.
        includeSystemImages = true;
        systemImageTypes = [ "google_apis" ];
        abiVersions = [ "x86_64" ];
        includeSources = false;
        includeNDK = false;
      };
      androidSdkBase = androidComposition.androidsdk;
      androidPlatformTools = androidComposition.platform-tools;
      androidEmulator = androidComposition.emulator;
      androidJdk = pkgs.jdk;
      # T3 checks cmdline-tools/latest explicitly. nixpkgs installs the tools
      # under their version number, so expose the conventional alias without
      # copying the SDK payload.
      androidSdk = pkgs.runCommand "t3code-android-sdk" { } ''
        mkdir -p "$out/libexec"
        cp -rs ${androidSdkBase}/libexec/android-sdk "$out/libexec/android-sdk"
        chmod u+w "$out/libexec/android-sdk/cmdline-tools"
        ln -s 22.0 "$out/libexec/android-sdk/cmdline-tools/latest"
      '';
      androidHome = "${androidSdk}/libexec/android-sdk";
      t3code = pkgs.callPackage ./package.nix {
        inherit sourceAssets seedTools androidSdk androidPlatformTools androidEmulator androidJdk;
      };
      server = pkgs.callPackage ./package-server.nix {
        inherit sourceAssets seedTools androidSdk androidPlatformTools androidEmulator androidJdk;
      };
    in
    {
      packages.${system} = {
        default = t3code;
        inherit t3code;
        inherit server;
        t3code-server = server;
        t3 = server;
        source-assets = sourceAssets;
        device-hub = deviceHub;
        scrcpy-server = scrcpyServer;
        chrome-headless-shell = chromeHeadlessShell;
      };

      apps.${system} = {
        default = self.apps.${system}.t3code;
        t3code = {
          type = "app";
          program = "${t3code}/bin/t3code";
          meta = t3code.meta;
        };
        server = {
          type = "app";
          program = "${server}/bin/t3code-server";
          meta = server.meta;
        };
        t3 = {
          type = "app";
          program = "${server}/bin/t3";
          meta = server.meta;
        };
      };

      checks.${system} = {
        inherit t3code;
        provider-path = pkgs.runCommand "t3code-provider-path" { } ''
          mkdir -p providers
          for provider in codex pi; do
            printf '#!${pkgs.runtimeShell}\nexit 0\n' > "providers/$provider"
            chmod +x "providers/$provider"
          done
          providerPath="$PWD/providers"
          for wrapper in \
            ${server}/bin/t3 \
            ${server}/bin/t3code-server \
            ${t3code}/bin/.t3code-wrapped
          do
            ! grep -q -e 'codex' -e 'pi-coding-agent' -e 't3code-pi-runtime' "$wrapper"
            grep -E '^(PATH=|export PATH$)' "$wrapper" > provider-path.sh
            test -s provider-path.sh
            PATH="$providerPath" ${pkgs.bash}/bin/bash -c \
              '. "$1"; test "$(command -v codex)" = "$2/codex"; test "$(command -v pi)" = "$2/pi"' \
              -- "$PWD/provider-path.sh" "$providerPath"
          done
          touch "$out"
        '';
        source-features = pkgs.runCommand "t3code-source-features" { } ''
          grep -a -q 'Pi started agent work outside an active T3 turn' ${sourceAssets}/apps/server/dist/binCli-*.mjs
          grep -a -q 'delegate_task' ${sourceAssets}/apps/server/dist/binCli-*.mjs
          grep -a -q 'T3_DISABLE_CHECKPOINTS' ${sourceAssets}/apps/server/dist/binCli-*.mjs
          grep -q 'T3_DISABLE_CHECKPOINTS' ${server}/bin/t3code-server
          grep -q 'T3_DISABLE_CHECKPOINTS' ${t3code}/bin/.t3code-wrapped
          grep -q 'preferredLanInterfaceName' ${sourceAssets}/apps/desktop/dist-electron/main.cjs
          grep -R -q 'Show diff' ${sourceAssets}/apps/server/dist/client/assets
          touch "$out"
        '';
        server-help = pkgs.runCommand "t3code-server-help" { } ''
          ${server}/bin/t3code-server --help > "$out"
        '';
        android-tooling = pkgs.runCommand "t3code-android-tooling" { } ''
          # The Device panel shells out to these; a missing one shows up as an
          # unusable device panel rather than a build error.
          test -x ${androidPlatformTools}/libexec/android-sdk/platform-tools/adb
          test -x ${androidEmulator}/libexec/android-sdk/emulator/emulator
          test -x ${androidHome}/cmdline-tools/latest/bin/avdmanager
          find -L ${androidHome}/system-images -name system.img | grep -q .
          for variable in ANDROID_HOME ANDROID_SDK_ROOT JAVA_HOME; do
            grep -q "$variable" ${server}/bin/t3code-server
            grep -q "$variable" ${t3code}/bin/.t3code-wrapped
          done
          # Physical Android devices stream over scrcpy, which serve-emu
          # otherwise downloads from GitHub at runtime.
          test -f ${deviceHub}/lib/node_modules/expo-device-hub/vendor/serve-emu/vendor/scrcpy-server-v${scrcpyServer.version}
          test -f ${deviceHub}/lib/node_modules/expo-device-hub/dist/server/cli.mjs
          grep -q 't3code-seed-tools' ${server}/bin/t3code-server
          grep -q 't3code-seed-tools' ${t3code}/bin/.t3code-wrapped
          grep -q 't3code-seed-device-hub' ${seedTools}
          # A version-matched npm install must also be replaced: it has the
          # sentinel but lacks the bundled scrcpy entry and runtime deps.
          testHome="$(mktemp -d)"
          hubDir="$testHome/tools/expo-device-hub/${deviceHub.hubVersion}"
          mkdir -p "$hubDir"
          echo '${deviceHub.hubVersion}' > "$hubDir/.install-complete"
          T3CODE_HOME="$testHome" ${seedDeviceHub}
          test "$(cat "$hubDir/.t3-bundled-from")" = '${deviceHub}'
          test -f "$hubDir/node_modules/expo-device-hub/dist/server/cli-real.mjs"
          test -f "$hubDir/node_modules/expo-device-hub/vendor/serve-emu/vendor/scrcpy-server-v${scrcpyServer.version}"
          T3CODE_HOME="$testHome" ${seedDeviceHub}
          touch "$out"
        '';
        headless-browser = pkgs.runCommand "t3code-headless-browser" { } ''
          browser=${chromeHeadlessShell}/chrome-headless-shell
          # Every library resolves from the Nix store, not from an FHS path.
          ! ${pkgs.glibc.bin}/bin/ldd "$browser" | grep -q 'not found'
          "$browser" --version | grep -q '${previewBrowserPin.version}'
          # It renders a page (T3 launches it the same way, plus a sandbox).
          export HOME="$(mktemp -d)"
          "$browser" --headless=new --no-sandbox --disable-gpu --no-first-run \
            --user-data-dir="$HOME/profile" \
            --dump-dom 'data:text/html,<p id="t3">rendered</p>' > dom.html
          grep -q '<p id="t3">rendered</p>' dom.html
          # Seeding replaces an earlier unpatched download at T3's install path.
          grep -q 't3code-seed-chrome-headless-shell' ${seedTools}
          testHome="$(mktemp -d)"
          dir="$testHome/tools/chrome-headless-shell/linux64/${previewBrowserPin.version}"
          mkdir -p "$dir"
          touch "$dir/chrome-headless-shell"
          T3CODE_HOME="$testHome" ${seedChromeHeadlessShell}
          test "$(readlink "$dir")" = '${chromeHeadlessShell}'
          test -x "$dir/chrome-headless-shell"
          T3CODE_HOME="$testHome" ${seedChromeHeadlessShell}
          ! ls -A "$testHome/tools/chrome-headless-shell/linux64" | grep -q '^\.install-'
          touch "$out"
        '';
      };
    };
}
