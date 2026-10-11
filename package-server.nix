{ lib
, buildNpmPackage
, fetchurl
, git
, importNpmLock
, makeWrapper
, nodejs_24
, openssh
, lsof
, sourceAssets
, seedTools
, androidSdk
, androidPlatformTools
, androidEmulator
, androidJdk
}:

let
  source = lib.importJSON ./source.json;
  packageJson = lib.importJSON ./npm/package.json;
  packageJsonForNpm = builtins.removeAttrs packageJson [ "overrides" ];
  packageLockJson = lib.importJSON ./npm/package-lock.json;
  # The published package's bin is now a platform launcher. This derivation
  # replaces dist with our source build, so invoke that bundle directly.
  binPath = "dist/bin.mjs";
  # The source-built bundle externalizes only native/disk-backed packages
  # (scripts/lib/cli-external-packages.ts). Upstream's matching Linux platform
  # package bundles exactly that closure. npm skips this optional dependency in
  # the sandbox, so fetch the locked tarball directly.
  platformPackage = packageLockJson.packages."node_modules/@t3code/t3-linux-x64";
  platformTarball = fetchurl {
    url = platformPackage.resolved;
    hash = platformPackage.integrity;
  };
  androidHome = "${androidSdk}/libexec/android-sdk";
  # Agent CLIs (Pi, Codex, ...) come from the user's PATH, which the wrapper
  # preserves; only T3's own runtime tools are pinned here.
  runtimePath = lib.makeBinPath [
    git
    openssh
    lsof
    androidSdk
    androidPlatformTools
    androidEmulator
    androidJdk
  ];
in
assert lib.assertMsg (
  packageJson.version == source.version
  && packageLockJson.version == source.version
  && packageLockJson.packages."node_modules/@t3code/t3-linux-x64".version == source.version
) "Refresh npm/package.json and npm/package-lock.json to match source.json before building the server.";
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

    # Unpack only the runtime dependency closure; dist/bin.mjs resolves it from
    # ./node_modules.
    tar -xzf ${platformTarball} --strip-components=1 package/node_modules
    test -f node_modules/node-pty/prebuilds/linux-x64/pty.node
    test -f node_modules/@ff-labs/fff-bin-linux-x64-gnu/libfff_c.so

    mkdir -p "$out/lib/node_modules/t3" "$out/bin"
    cp -r . "$out/lib/node_modules/t3"

    makeWrapper ${nodejs_24}/bin/node "$out/bin/t3" \
      --add-flags "$out/lib/node_modules/t3/${binPath}" \
      --set T3_DISABLE_CHECKPOINTS "1" \
      --set ANDROID_HOME "${androidHome}" \
      --set ANDROID_SDK_ROOT "${androidHome}" \
      --set JAVA_HOME "${androidJdk.home}" \
      --prefix PATH : "${runtimePath}" \
      --run '${seedTools}'

    makeWrapper ${nodejs_24}/bin/node "$out/bin/t3code-server" \
      --add-flags "$out/lib/node_modules/t3/${binPath}" \
      --add-flags "serve" \
      --set T3_DISABLE_CHECKPOINTS "1" \
      --set ANDROID_HOME "${androidHome}" \
      --set ANDROID_SDK_ROOT "${androidHome}" \
      --set JAVA_HOME "${androidJdk.home}" \
      --prefix PATH : "${runtimePath}" \
      --run '${seedTools}'

    runHook postInstall
  '';

  passthru = {
    inherit sourceAssets;
    release = source;
  };

  meta = {
    description = "Headless T3 Code nightly server with Android device tooling";
    homepage = "https://github.com/pingdotgg/t3code";
    license = lib.licenses.mit;
    mainProgram = "t3code-server";
    platforms = lib.platforms.linux;
  };
}
