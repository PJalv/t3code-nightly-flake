{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:
buildNpmPackage rec {
  pname = "pi-subagents";
  version = "0.19.0";

  src = fetchFromGitHub {
    owner = "tintinweb";
    repo = "pi-subagents";
    rev = "v${version}";
    hash = "sha256-1K6U5+2qLgOV7lUWbvqUne/Pf7oMRDf40GXLl8gv6Bk=";
  };

  npmDepsHash = "sha256-w4ht9Wjb73w13bOSfeEU5a1RXPYARXVO21Vpk/NR1nY=";
  dontNpmBuild = true;

  postPatch = ''
    cp ${./npm/pi-subagents/package.json} package.json
    cp ${./npm/pi-subagents/package-lock.json} package-lock.json
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/pi-subagents"
    cp -r . "$out/lib/pi-subagents"

    test -f "$out/lib/pi-subagents/src/index.ts"
    test -d "$out/lib/pi-subagents/node_modules/@sinclair/typebox"
    test -d "$out/lib/pi-subagents/node_modules/croner"
    test -d "$out/lib/pi-subagents/node_modules/nanoid"
    test -d "$out/lib/pi-subagents/node_modules/typebox"

    runHook postInstall
  '';

  meta = {
    description = "Claude Code-style subagent extension for the Pi coding agent";
    homepage = "https://github.com/tintinweb/pi-subagents";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
