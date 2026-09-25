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
, deviceHub
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
  # The server npm-installs expo-device-hub into <base-dir>/tools on first
  # use, which needs the registry and pulls the scrcpy jar from GitHub. Seed
  # the same layout from the store, sentinel included, so installTool sees a
  # complete install and skips both. Re-seeded on every start because the
  # version directory changes when the pinned hub version does.
  seedDeviceHub = ''
    seed_device_hub() {
      local base="''${T3CODE_HOME:-$HOME/.t3}"
      local dir="$base/tools/expo-device-hub/${deviceHub.hubVersion}"
      # Re-seed when the sentinel is missing or names another version. Files
      # copied out of the store are read-only, so clear the write bit before
      # removing, otherwise a stale tree blocks its own replacement.
      if [ "$(cat "$dir/.install-complete" 2>/dev/null)" = '${deviceHub.hubVersion}' ]; then
        return 0
      fi
      if [ -d "$dir" ]; then
        chmod -R u+w "$dir" 2>/dev/null || true
        rm -rf "$dir"
      fi
      mkdir -p "$dir/node_modules"
      cp -r ${deviceHub}/lib/node_modules/expo-device-hub "$dir/node_modules/"
      chmod -R u+w "$dir"
      # Trailing newline without printf escapes: makeWrapper strips
      # backslashes, so '%s\n' would reach the wrapper as '%sn'.
      echo '${deviceHub.hubVersion}' > "$dir/.install-complete"
    }
    seed_device_hub
  '';
  # Seeding is best-effort. Commands like `--help` run in contexts whose home
  # may not be writable (the build sandbox sets HOME=/homeless-shelter), and a
  # failed seed must not turn those into failures.
  seedDeviceHubRun = "( ${seedDeviceHub} ) 2>/dev/null || true";
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
      --prefix PATH : "${runtimePath}" \
      --run '${seedDeviceHubRun}'

    makeWrapper ${nodejs_24}/bin/node "$out/bin/t3code-server" \
      --add-flags "$out/lib/node_modules/t3/${binPath}" \
      --add-flags "serve" \
      ${checkpointWrapperArgs} \
      --set ANDROID_HOME "${androidHome}" \
      --set ANDROID_SDK_ROOT "${androidHome}" \
      --set JAVA_HOME "${androidJdk.home}" \
      --prefix PATH : "${runtimePath}" \
      --run '${seedDeviceHubRun}'

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
