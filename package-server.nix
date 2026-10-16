{ lib
, stdenv
, autoPatchelfHook
, fetchurl
, git
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
  binPath = "dist/bin.mjs";
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
stdenv.mkDerivation {
  pname = "t3code-server";
  inherit (source) version;

  src = fetchurl {
    url = source.serverUrl;
    hash = source.serverHash;
  };

  nativeBuildInputs = [ makeWrapper autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib ];
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/node_modules/t3" "$out/bin"
    cp -r ${sourceAssets}/apps/server/dist "$out/lib/node_modules/t3/dist"
    cp -r node_modules "$out/lib/node_modules/t3/node_modules"
    chmod u+w "$out/lib/node_modules/t3/dist"
    cp -r resource-monitor "$out/lib/node_modules/t3/dist/resource-monitor"
    rm -rf "$out/lib/node_modules/t3/node_modules/@ff-labs/fff-bin-linux-x64-musl"
    test -f "$out/lib/node_modules/t3/node_modules/node-pty/prebuilds/linux-x64/pty.node"
    test -f "$out/lib/node_modules/t3/node_modules/@ff-labs/fff-bin-linux-x64-gnu/libfff_c.so"
    test -f "$out/lib/node_modules/t3/${binPath}"

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
