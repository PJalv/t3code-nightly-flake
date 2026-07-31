{
  description = "Latest T3 Code nightly, bundled with Codex from llm-agents.nix";

  nixConfig = {
    extra-substituters = [ "https://cache.numtide.com" ];
    extra-trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };

  inputs = {
    llm-agents.url = "github:numtide/llm-agents.nix";
    nixpkgs.follows = "llm-agents/nixpkgs";
  };

  outputs = { self, nixpkgs, llm-agents }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      t3code = pkgs.callPackage ./package.nix {
        codex = llm-agents.packages.${system}.codex;
      };
      t3codeWithCheckpoints = t3code.override {
        disableCheckpoints = false;
      };
      server = pkgs.callPackage ./package-server.nix {
        codex = llm-agents.packages.${system}.codex;
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
        server-help = pkgs.runCommand "t3code-server-help" { } ''
          ${server}/bin/t3code-server --help > "$out"
        '';
      };
    };
}
