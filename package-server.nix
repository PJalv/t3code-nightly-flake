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
, androidSdk
, androidPlatformTools
, androidEmulator
, androidJdk
, disableCheckpoints ? true
}:

let
  source = lib.importJSON ./source.json;
  packageJson = lib.importJSON ./npm/package.json;
  packageJsonForNpm = builtins.removeAttrs packageJson [ "overrides" ];
  packageLockJson = lib.importJSON ./npm/package-lock.json;
  # The published package's bin is now a platform launcher. This derivation
  # replaces dist with our source build, so invoke that bundle directly.
  binPath = "dist/bin.mjs";
  androidHome = "${androidSdk}/libexec/android-sdk";
  runtimePath = lib.makeBinPath [
    codex
    pi
    git
    openssh
    lsof
    androidSdk
    androidPlatformTools
    androidEmulator
    androidJdk
  ];
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

    # Overlay the source workspace dependencies after npm has finished, since
    # the source-built bundle externalizes packages absent from the launcher.
    cp -r ${sourceAssets}/apps/server/node_modules/. ./node_modules/
    # The published launcher keeps native dependencies under its Linux platform
    # package. Hoist them for the source-built dist/bin.mjs bundle.
    if [ -d node_modules/@t3code/t3-linux-x64/node_modules ]; then
      chmod -R u+w node_modules
      cp -r node_modules/@t3code/t3-linux-x64/node_modules/. ./node_modules/
    fi

    mkdir -p "$out/lib/node_modules/t3" "$out/bin"
    cp -r . "$out/lib/node_modules/t3"

    makeWrapper ${nodejs_24}/bin/node "$out/bin/t3" \
      --add-flags "$out/lib/node_modules/t3/${binPath}" \
      ${checkpointWrapperArgs} \
      --set ANDROID_HOME "${androidHome}" \
      --set ANDROID_SDK_ROOT "${androidHome}" \
      --set JAVA_HOME "${androidJdk.home}" \
      --prefix PATH : "${runtimePath}"

    makeWrapper ${nodejs_24}/bin/node "$out/bin/t3code-server" \
      --add-flags "$out/lib/node_modules/t3/${binPath}" \
      --add-flags "serve" \
      ${checkpointWrapperArgs} \
      --set ANDROID_HOME "${androidHome}" \
      --set ANDROID_SDK_ROOT "${androidHome}" \
      --set JAVA_HOME "${androidJdk.home}" \
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
