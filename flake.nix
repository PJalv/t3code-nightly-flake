{
  description = "Latest T3 Code nightly, bundled with Codex and Pi from llm-agents.nix";

  nixConfig = {
    extra-substituters = [ "https://cache.numtide.com" ];
    extra-trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };

  inputs = {
    llm-agents.url = "github:numtide/llm-agents.nix";
    nixpkgs.follows = "llm-agents/nixpkgs";
    t3code-source = {
      url = "github:PJalv/t3code/0d62dc8b605de6149a62902be1550b148e9949de";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, llm-agents, t3code-source }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      lib = pkgs.lib;
      source = lib.importJSON ./source.json;
      sourceAssets = pkgs.callPackage ./package-source.nix {
        src = t3code-source;
        inherit (source) version;
      };
      piMcpAdapter = pkgs.callPackage ./package-pi-mcp-adapter.nix { };
      piRuntime = pkgs.callPackage ./package-pi-runtime.nix {
        pi = llm-agents.packages.${system}.pi;
        inherit piMcpAdapter;
      };
      t3code = pkgs.callPackage ./package.nix {
        codex = llm-agents.packages.${system}.codex;
        pi = piRuntime;
        inherit sourceAssets;
      };
      t3codeWithCheckpoints = t3code.override {
        disableCheckpoints = false;
      };
      server = pkgs.callPackage ./package-server.nix {
        codex = llm-agents.packages.${system}.codex;
        pi = piRuntime;
        inherit sourceAssets;
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
          grep -q T3CODE_PI_MCP_CONFIG ${piRuntime.passthru.piMcpAdapter}/lib/pi-mcp-adapter/utils.ts
          test -f ${piRuntime.passthru.subagentExtension}/index.ts
          grep -q 'agent.model ??' ${piRuntime.passthru.subagentExtension}/index.ts
          grep -q 'Use "default" unless' ${piRuntime.passthru.subagentExtension}/index.ts
          test -f ${piRuntime.passthru.subagentExtension}/agents/default.md
          test "$(find ${piRuntime.passthru.subagentExtension}/agents -maxdepth 1 -name '*.md' | wc -l)" -eq 1
          ${t3code.passthru.pi}/bin/pi --version > "$out"
        '';
        source-features = pkgs.runCommand "t3code-source-features" { } ''
          grep -a -q providerNativeFileChangesEnabled ${sourceAssets}/apps/server/dist/bin.mjs
          grep -a -q T3_DISABLE_CHECKPOINTS ${sourceAssets}/apps/server/dist/bin.mjs
          grep -R -q "Provider-native file changes" ${sourceAssets}/apps/server/dist/client
          grep -a -q get_session_stats ${sourceAssets}/apps/server/dist/bin.mjs
          grep -a -q pi-mcp-adapter ${sourceAssets}/apps/server/dist/bin.mjs
          grep -R -q PiAgentIcon ${sourceAssets}/apps/server/dist/client
          touch "$out"
        '';
        server-help = pkgs.runCommand "t3code-server-help" { } ''
          ${server}/bin/t3code-server --help > "$out"
        '';
      };
    };
}
