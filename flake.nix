{
  description = "Latest T3 Code nightly, bundled with Codex and the T3 Pi Copilot runtime";

  nixConfig = {
    extra-substituters = [ "https://cache.numtide.com" ];
    extra-trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };

  inputs = {
    llm-agents.url = "github:numtide/llm-agents.nix";
    nixpkgs.follows = "llm-agents/nixpkgs";
    # Pi 1.0.0 with the opencode-aligned GitHub Copilot port and T3's
    # RPC compaction fixes. Pi is packaged directly from its npm release;
    # llm-agents remains the source of the separately bundled Codex runtime.
    pi-copilot = {
      url = "git+ssh://git@git.pjalv.com:2221/PJalv/pi-copilot.git?ref=pi-1.0.0-copilot";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    t3code-source = {
      url = "github:pingdotgg/t3code/4ee6bfd50ef4a089440d5c3662db2298da9cc50e";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, llm-agents, pi-copilot, t3code-source }:
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
      # The repo pins packageManager pnpm@11.10.0; nixpkgs' pnpm_11 (11.25.0)
      # fetches the filtered workspace store incompletely.
      pnpmPinned = pkgs.pnpm_11.override {
        version = "11.10.0";
        hash = "sha256-YgtmBepPYvxWptCphzP0eQcdAyHgPkhrUix+mnRhdDE=";
      };
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
      piSubagents = pkgs.callPackage ./package-pi-subagents.nix { };
      scrcpyServer = pkgs.callPackage ./package-scrcpy-server.nix { };
      deviceHub = pkgs.callPackage ./package-device-hub.nix { inherit scrcpyServer; };
      seedDeviceHub = pkgs.writeShellScript "t3code-seed-device-hub"
        (import ./seed-device-hub.nix { inherit deviceHub; });
      piRuntime = pkgs.callPackage ./package-pi-runtime.nix {
        # Standalone Pi keeps the user's pinned subagent extension.
        pi = pi-copilot.packages.${system}.pi;
        inherit piSubagents;
      };
      t3PiRuntime = pkgs.callPackage ./package-pi-runtime.nix {
        # T3 must not load the custom Pi subagent extension.
        pi = pi-copilot.packages.${system}.pi;
        inherit piSubagents;
        enableSubagents = false;
      };
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
        codex = llm-agents.packages.${system}.codex;
        pi = t3PiRuntime;
        inherit sourceAssets seedDeviceHub androidSdk androidPlatformTools androidEmulator androidJdk;
      };
      server = pkgs.callPackage ./package-server.nix {
        codex = llm-agents.packages.${system}.codex;
        pi = t3PiRuntime;
        inherit sourceAssets seedDeviceHub androidSdk androidPlatformTools androidEmulator androidJdk;
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
        pi = piRuntime;
        pi-subagents = piSubagents;
        device-hub = deviceHub;
        scrcpy-server = scrcpyServer;
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
        bundled-codex = pkgs.runCommand "t3code-bundled-codex" { } ''
          test -x ${t3code.passthru.codex}/bin/codex
          ${t3code.passthru.codex}/bin/codex --version > "$out"
        '';
        bundled-pi = pkgs.runCommand "t3code-bundled-pi" { } ''
          test -x ${t3code.passthru.pi}/bin/pi
          ! grep -q -- '--mcp-config' ${t3code.passthru.pi}/bin/pi
          ! grep -q 'pi-subagents' ${t3code.passthru.pi}/bin/pi
          grep -q -- '--extension' ${piRuntime}/bin/pi
          test -f ${piRuntime.passthru.pi}/lib/node_modules/@earendil-works/pi-coding-agent/dist/extensions/mcp/index.js
          ${t3code.passthru.pi}/bin/pi --version > "$out"
          test "$(cat "$out")" = '${t3PiRuntime.version}'
          export HOME="$(mktemp -d)"
          export PI_CODING_AGENT_DIR="$HOME/.pi/agent"
          ${t3code.passthru.pi}/bin/pi mcp list > mcp-list.txt
          grep -q 'No MCP servers configured' mcp-list.txt
        '';
        source-features = pkgs.runCommand "t3code-source-features" { } ''
          grep -a -q 'Pi started agent work outside an active T3 turn' ${sourceAssets}/apps/server/dist/binCli-*.mjs
          grep -a -q 'delegate_task' ${sourceAssets}/apps/server/dist/binCli-*.mjs
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
          grep -q 't3code-seed-device-hub' ${server}/bin/t3code-server
          grep -q 't3code-seed-device-hub' ${t3code}/bin/.t3code-wrapped
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
      };
    };
}
