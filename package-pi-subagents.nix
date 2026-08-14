{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:
buildNpmPackage rec {
  pname = "pi-subagents";
  version = "0.16.0";

  src = fetchFromGitHub {
    owner = "tintinweb";
    repo = "pi-subagents";
    rev = "v${version}";
    hash = "sha256-vkhSHSkOmAAdw/F5sQ4iV/Vls4VZfxedpSsWiTrnXRo=";
  };

  npmDepsHash = "sha256-qZo5C8d6ZhX7Zv9i9SxDxaUUwgnrMkJbPpeSF0JtNe4=";
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

    runHook postInstall
  '';

  meta = {
    description = "Claude Code-style subagent extension for the Pi coding agent";
    homepage = "https://github.com/tintinweb/pi-subagents";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
