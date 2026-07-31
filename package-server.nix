{ lib
, buildNpmPackage
, fetchurl
, git
, importNpmLock
, makeWrapper
, nodejs_24
, openssh
, codex
, disableCheckpoints ? true
}:

let
  source = lib.importJSON ./source.json;
  packageJson = lib.importJSON ./npm/package.json;
  packageJsonForNpm = builtins.removeAttrs packageJson [ "overrides" ];
  packageLockJson = lib.importJSON ./npm/package-lock.json;
  binPath = lib.removePrefix "./" packageJson.bin.t3;
  runtimePath = lib.makeBinPath [ codex git openssh ];
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

    node <<'NODE'
    const fs = require("fs");
    const bundlePath = "dist/bin.mjs";
    const source = fs.readFileSync(bundlePath, "utf8");
    const regionStartMarker =
      "//#region src/orchestration/Layers/CheckpointReactor.ts";
    const regionEndMarker =
      "//#region src/orchestration/Layers/ThreadDeletionReactor.ts";
    const regionStart = source.indexOf(regionStartMarker);
    const regionEnd = source.indexOf(regionEndMarker, regionStart);

    if (regionStart < 0 || regionEnd < 0) {
      throw new Error("T3 Code checkpoint reactor region was not found");
    }

    const before = source.slice(0, regionStart);
    const region = source.slice(regionStart, regionEnd);
    const after = source.slice(regionEnd);
    const needle = 'start: Effect.fn("start")(function* () {';
    const replacement =
      needle + ' if (process.env.T3_DISABLE_CHECKPOINTS === "1") return;';
    const occurrences = region.split(needle).length - 1;

    if (occurrences !== 1) {
      throw new Error(
        "Expected exactly one checkpoint reactor start function, found " +
          occurrences,
      );
    }

    fs.writeFileSync(bundlePath, before + region.replace(needle, replacement) + after);
    NODE

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
    inherit codex disableCheckpoints;
    release = source;
  };

  meta = {
    description = "Headless T3 Code nightly server for browser access";
    homepage = "https://github.com/pingdotgg/t3code";
    license = lib.licenses.mit;
    mainProgram = "t3code-server";
    platforms = lib.platforms.linux;
  };
}
