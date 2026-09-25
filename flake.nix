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
    # Pi 0.86.1 with the opencode-aligned GitHub Copilot port and T3's
    # RPC compaction fixes. Pi is packaged directly from its npm release;
    # llm-agents remains the source of the separately bundled Codex runtime.
    pi-copilot = {
      url = "git+ssh://git@git.pjalv.com:2221/PJalv/pi-copilot.git?ref=pi-0.87.0-copilot";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    t3code-source = {
      url = "github:PJalv/t3code/3533201142";
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
      sourceAssets = pkgs.callPackage ./package-source.nix {
        src = t3code-source;
        inherit (source) version;
        pnpm_11 = pnpmPinned;
      };
      piMcpAdapter = pkgs.callPackage ./package-pi-mcp-adapter.nix { };
      piSubagents = pkgs.callPackage ./package-pi-subagents.nix { };
      scrcpyServer = pkgs.callPackage ./package-scrcpy-server.nix { };
      deviceHub = pkgs.callPackage ./package-device-hub.nix { inherit scrcpyServer; };
      piRuntime = pkgs.callPackage ./package-pi-runtime.nix {
        # pi with the opencode-aligned GitHub Copilot port.
        pi = pi-copilot.packages.${system}.pi;
        inherit piMcpAdapter piSubagents;
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
        pi = piRuntime;
        inherit sourceAssets androidSdk androidPlatformTools androidEmulator androidJdk;
      };
      t3codeWithCheckpoints = t3code.override {
        disableCheckpoints = false;
      };
      server = pkgs.callPackage ./package-server.nix {
        codex = llm-agents.packages.${system}.codex;
        pi = piRuntime;
        inherit sourceAssets deviceHub androidSdk androidPlatformTools androidEmulator androidJdk;
      };
      serverWithCheckpoints = server.override {
        disableCheckpoints = false;
      };
    in
    {
      packages.${system} = {
        default = t3code;
        inherit t3code;
        desktop-with-checkpoints = t3codeWithCheckpoints;
        inherit server;
        t3code-server = server;
        t3 = server;
        server-with-checkpoints = serverWithCheckpoints;
        source-assets = sourceAssets;
        pi = piRuntime;
        pi-mcp-adapter = piMcpAdapter;
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
        desktop-with-checkpoints = {
          type = "app";
          program = "${t3codeWithCheckpoints}/bin/t3code";
          meta = t3codeWithCheckpoints.meta;
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
        server-with-checkpoints = {
          type = "app";
          program = "${serverWithCheckpoints}/bin/t3code-server";
          meta = serverWithCheckpoints.meta;
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
          grep -q T3CODE_PI_MCP_CONFIG ${t3code.passthru.pi}/bin/pi
          test -f ${piRuntime.passthru.piMcpAdapter}/lib/pi-mcp-adapter/index.ts
          grep -q '"version": "2.34.0"' ${piRuntime.passthru.piMcpAdapter}/lib/pi-mcp-adapter/package.json
          test -f ${piRuntime.passthru.piSubagents}/lib/pi-subagents/src/index.ts
          grep -q '"version": "0.19.0"' ${piRuntime.passthru.piSubagents}/lib/pi-subagents/package.json
          grep -q 'subagents:rpc:stop' ${piRuntime.passthru.piSubagents}/lib/pi-subagents/src/cross-extension-rpc.ts
          grep -q 'pi-subagents-0.19.0' ${t3code.passthru.pi}/bin/pi
          grep -q 'Type.Union(\[Type.Literal("off"), Type.Literal("worktree")\]' ${piRuntime.passthru.piSubagents}/lib/pi-subagents/src/invocation-config.ts
          test -f ${piRuntime.passthru.subagentExtension}/index.ts
          grep -q 'agent.model ??' ${piRuntime.passthru.subagentExtension}/index.ts
          grep -q 'Use "default" unless' ${piRuntime.passthru.subagentExtension}/index.ts
          test -f ${piRuntime.passthru.subagentExtension}/agents/default.md
          test "$(find ${piRuntime.passthru.subagentExtension}/agents -maxdepth 1 -name '*.md' | wc -l)" -eq 1
          ${t3code.passthru.pi}/bin/pi --version > "$out"
        '';
        source-features = pkgs.runCommand "t3code-source-features" { } ''
          grep -a -q 'src/provider/Drivers/PiDriver.ts' ${sourceAssets}/apps/server/dist/bin.mjs
          grep -a -q 'AntigravityDriver' ${sourceAssets}/apps/server/dist/bin.mjs
          grep -a -q providerNativeFileChangesEnabled ${sourceAssets}/apps/server/dist/bin.mjs
          grep -a -q T3_DISABLE_CHECKPOINTS ${sourceAssets}/apps/server/dist/bin.mjs
          grep -R -q "Provider-native file changes" ${sourceAssets}/apps/server/dist/client
          grep -a -q get_session_stats ${sourceAssets}/apps/server/dist/bin.mjs
          grep -a -q pi-mcp-adapter ${sourceAssets}/apps/server/dist/bin.mjs
          grep -a -q t3code.pi-bridge.v1 ${sourceAssets}/apps/server/dist/bin.mjs
          grep -a -q get_entries ${sourceAssets}/apps/server/dist/bin.mjs
          grep -R -q PiAgentIcon ${sourceAssets}/apps/server/dist/client
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
          grep -q 'install-complete' ${server}/bin/t3code-server
          touch "$out"
        '';
      };
    };
}
