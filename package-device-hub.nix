{
  lib,
  buildNpmPackage,
  fetchurl,
  importNpmLock,
  nodejs_24,
  scrcpyServer,
  hubVersion ? "0.12.0",
}:

let
  packageJson = lib.importJSON ./npm/expo-device-hub/package.json;
  packageJsonForNpm = builtins.removeAttrs packageJson [ "overrides" ];
  packageLockJson = lib.importJSON ./npm/expo-device-hub/package-lock.json;
in

# expo-device-hub is normally npm-installed into <base-dir>/tools on first
# use. That needs the registry, and serve-emu also downloads
# scrcpy-server-v4.0 from GitHub the first time a physical Android device
# streams. Build the installed tree here instead so the server wrappers can
# seed it and installTool's sentinel check skips both.
buildNpmPackage {
  pname = "t3code-device-hub";
  version = hubVersion;

  src = fetchurl {
    url = "https://registry.npmjs.org/expo-device-hub/-/expo-device-hub-${hubVersion}.tgz";
    hash = "sha512-afTwAQAKx05bPe5FW/rfN22awYcp9iXj36Qfj+1XbUP8UGlIUkeEfJP3beJOzXzt6POlf1kKegkpja87ltkYEQ==";
  };

  sourceRoot = "package";
  nodejs = nodejs_24;
  npmFlags = [ "--legacy-peer-deps" ];
  dontNpmBuild = true;

  npmDeps = importNpmLock {
    package = packageJsonForNpm;
    packageLock = packageLockJson;
  };
  npmConfigHook = importNpmLock.npmConfigHook;

  postPatch = ''
    cp ${./npm/expo-device-hub/package.json} package.json
    cp ${./npm/expo-device-hub/package-lock.json} package-lock.json
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/node_modules/expo-device-hub"
    cp -r . "$out/lib/node_modules/expo-device-hub/"

    hubRoot="$out/lib/node_modules/expo-device-hub"
    test -f "$hubRoot/dist/server/cli.mjs"
    test -d "$hubRoot/node_modules/ws"

    # T3 spawns the hub without a stream source. expo-device-hub defaults to
    # grpc-screenshot, which rejects every physical device (and only the
    # --stream-source flag avoids it; the env var does not gate that check).
    # Wrap the entry point so physical Android devices stream over scrcpy.
    mv "$hubRoot/dist/server/cli.mjs" "$hubRoot/dist/server/cli-real.mjs"
    cat > "$hubRoot/dist/server/cli.mjs" <<'SHIM'
    #!/usr/bin/env node
    // T3 does not pass a stream source, and the hub defaults to
    // grpc-screenshot, which rejects physical Android devices. Force scrcpy.
    const args = process.argv.slice(2);
    if (!args.includes("--stream-source")) args.push("--stream-source", "scrcpy");
    process.argv = [process.argv[0], process.argv[1], ...args];
    await import(new URL("./cli-real.mjs", import.meta.url));
    SHIM
    chmod +x "$hubRoot/dist/server/cli.mjs"

    # serve-emu resolves the scrcpy server relative to its own directory and
    # otherwise fetches it at runtime. Put it where the lookup lands.
    scrcpyVendor="$hubRoot/vendor/serve-emu/vendor"
    mkdir -p "$scrcpyVendor"
    cp ${scrcpyServer} "$scrcpyVendor/scrcpy-server-v${scrcpyServer.version}"

    runHook postInstall
  '';

  passthru = {
    inherit hubVersion;
    entry = "dist/server/cli.mjs";
  };

  meta = {
    description = "Bundled expo-device-hub with the scrcpy server for physical Android streaming";
    homepage = "https://github.com/expo/expo-device-hub";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
