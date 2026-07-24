{
  description = "T3 Code delayed-nightly, bundled with Codex from llm-agents.nix";

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
    in
    {
      packages.${system} = {
        default = t3code;
        inherit t3code;
      };

      apps.${system} = {
        default = self.apps.${system}.t3code;
        t3code = {
          type = "app";
          program = "${t3code}/bin/t3code";
          meta = t3code.meta;
        };
      };

      checks.${system} = {
        inherit t3code;
        bundled-codex = pkgs.runCommand "t3code-bundled-codex" { } ''
          test -x ${t3code.passthru.codex}/bin/codex
          ${t3code.passthru.codex}/bin/codex --version > "$out"
        '';
      };
    };
}
