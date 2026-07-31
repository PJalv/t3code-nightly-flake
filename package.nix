{ lib
, appimageTools
, asar
, fetchurl
, makeWrapper
, nodejs_24
, runCommand
, codex
, disableCheckpoints ? true
}:

let
  source = lib.importJSON ./source.json;
  pname = "t3code";
  inherit (source) version;

  src = fetchurl {
    inherit (source) url hash;
  };

  appimageContents = appimageTools.extractType2 {
    inherit pname version src;
  };
  patchedAppimageContents = runCommand "${pname}-${version}-checkpoint-patched" {
    nativeBuildInputs = [ nodejs_24 ];
  } ''
    mkdir -p "$out"
    cp -a ${appimageContents}/. "$out/"
    chmod u+w "$out/resources/app.asar"

    node ${./scripts/patch-checkpoint-asar.mjs} \
      ${asar}/lib/node_modules/@electron/asar/lib/disk.js \
      "$out/resources/app.asar"
  '';
  runtimeAppimageContents = if disableCheckpoints then
    patchedAppimageContents
  else
    appimageContents;
  checkpointWrapperArgs = lib.optionalString disableCheckpoints
    "--set T3_DISABLE_CHECKPOINTS 1";
in
appimageTools.wrapAppImage {
  inherit pname version;
  contents = runtimeAppimageContents;
  nativeBuildInputs = [ makeWrapper ];

  extraInstallCommands = ''
    mkdir -p "$out/share"

    if [ -d ${runtimeAppimageContents}/usr/share ]; then
      cp -r ${runtimeAppimageContents}/usr/share/* "$out/share/"
    fi

    desktop_file="$(find "$out/share" -type f -name '*.desktop' | head -n 1 || true)"
    if [ -n "$desktop_file" ]; then
      desktop_basename="$(basename "$desktop_file")"
      sed -i \
        -e 's|Exec=AppRun|Exec=${pname}|g' \
        -e 's|Exec=AppRun %U|Exec=${pname} %U|g' \
        -e 's|TryExec=AppRun|TryExec=${pname}|g' \
        -e 's|^StartupWMClass=.*$|StartupWMClass=t3-code-desktop|g' \
        "$desktop_file"

      wrapProgram "$out/bin/${pname}" \
        --add-flags "--ignore-certificate-errors" \
        --set CHROME_DESKTOP "$desktop_basename" \
        ${checkpointWrapperArgs} \
        --prefix XDG_DATA_DIRS : "$out/share" \
        --prefix PATH : "${lib.makeBinPath [ codex ]}"
    else
      wrapProgram "$out/bin/${pname}" \
        --add-flags "--ignore-certificate-errors" \
        ${checkpointWrapperArgs} \
        --prefix XDG_DATA_DIRS : "$out/share" \
        --prefix PATH : "${lib.makeBinPath [ codex ]}"
    fi

    if [ -f ${runtimeAppimageContents}/.DirIcon ]; then
      install -Dm444 ${runtimeAppimageContents}/.DirIcon "$out/share/pixmaps/${pname}.png"
    fi
  '';

  passthru = {
    inherit codex disableCheckpoints;
    release = source;
  };

  meta = {
    description = "Latest T3 Code nightly with a bundled Codex CLI";
    homepage = "https://github.com/pingdotgg/t3code";
    changelog = "https://github.com/pingdotgg/t3code/releases/tag/v${version}";
    license = lib.licenses.mit;
    mainProgram = pname;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
