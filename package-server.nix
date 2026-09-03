{ lib
, buildNpmPackage
, fetchurl
, git
, importNpmLock
, makeWrapper
, nodejs_24
, openssh
, lsof
, codex
, pi
, sourceAssets
, disableCheckpoints ? true
}:

let
  source = lib.importJSON ./source.json;
  packageJson = lib.importJSON ./npm/package.json;
  packageJsonForNpm = builtins.removeAttrs packageJson [ "overrides" ];
  packageLockJson = lib.importJSON ./npm/package-lock.json;
  binPath = lib.removePrefix "./" packageJson.bin.t3;
  runtimePath = lib.makeBinPath [ codex pi git openssh lsof ];
  checkpointWrapperArgs = lib.optionalString disableCheckpoints
    "--set T3_DISABLE_CHECKPOINTS 1";
in
buildNpmPackage {
  pname = "t3code-server";
  inherit (source) version;
  nodejs = nodejs_24;

  src = fetchurl {
    url = source.npmUrl;
    hash = source.npmHash;
  };

  sourceRoot = "package";

  npmDeps = importNpmLock {
    package = packageJsonForNpm;
    packageLock = packageLockJson;
    fetcherOpts = {
      "node_modules/@effect/platform-node" = { name = "platform-node.tgz"; };
      "node_modules/@effect/platform-node-shared" = { name = "platform-node-shared.tgz"; };
      "node_modules/@effect/sql-sqlite-bun" = { name = "sql-sqlite-bun.tgz"; };
      "node_modules/effect" = { name = "effect.tgz"; };
    };
  };

  npmConfigHook = importNpmLock.npmConfigHook;
  npmFlags = [ "--legacy-peer-deps" ];
  nativeBuildInputs = [ makeWrapper ];
  dontNpmBuild = true;

  postPatch = ''
    cp ${./npm/package.json} package.json
    cp ${./npm/package-lock.json} package-lock.json

    node -e '
      const fs = require("fs");
      const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
      delete pkg.overrides;
      fs.writeFileSync("package.json", JSON.stringify(pkg, null, 2) + "\n");
    '

    rm -rf dist
    cp -r ${sourceAssets}/apps/server/dist ./dist

    test -f ${lib.escapeShellArg binPath}
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/node_modules/t3" "$out/bin"
    cp -r . "$out/lib/node_modules/t3"

    makeWrapper ${nodejs_24}/bin/node "$out/bin/t3" \
      --add-flags "$out/lib/node_modules/t3/${binPath}" \
      ${checkpointWrapperArgs} \
      --prefix PATH : "${runtimePath}"

    makeWrapper ${nodejs_24}/bin/node "$out/bin/t3code-server" \
      --add-flags "$out/lib/node_modules/t3/${binPath}" \
      --add-flags "serve" \
      ${checkpointWrapperArgs} \
      --prefix PATH : "${runtimePath}"

    runHook postInstall
  '';

  passthru = {
    inherit codex pi disableCheckpoints sourceAssets;
    release = source;
  };

  meta = {
    description = "Headless T3 Code nightly server with bundled Codex and Pi agent CLIs";
    homepage = "https://github.com/pingdotgg/t3code";
    license = lib.licenses.mit;
    mainProgram = "t3code-server";
    platforms = lib.platforms.linux;
  };
}
