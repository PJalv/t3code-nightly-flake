{
  lib,
  appimageTools,
  asar,
  fetchurl,
  makeWrapper,
  pkgs,
  runCommand,
  codex,
  sourceAssets,
  disableCheckpoints ? true,
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
  sourceAppimageContents =
    runCommand "${pname}-${version}-source-patched"
      {
        nativeBuildInputs = [ asar ];
      }
      ''
        mkdir -p "$out"
        cp -a ${appimageContents}/. "$out/"
        chmod -R u+w "$out/resources"

        mkdir app
        asar extract "$out/resources/app.asar" app

        rm -rf app/apps/server/dist app/apps/desktop/dist-electron
        cp -r ${sourceAssets}/apps/server/dist app/apps/server/
        cp -r ${sourceAssets}/apps/desktop/dist-electron app/apps/desktop/

        rm -f "$out/resources/app.asar"
        rm -rf "$out/resources/app.asar.unpacked"
        asar pack \
          --unpack-dir 'node_modules/{@ff-labs,@msgpackr-extract,@yuuang,node-pty}' \
          app \
          "$out/resources/app.asar"

        test -f "$out/resources/app.asar"
        test -d "$out/resources/app.asar.unpacked/node_modules/node-pty"
      '';
  checkpointWrapperArgs = lib.optionalString disableCheckpoints "--set T3_DISABLE_CHECKPOINTS 1";
  runtimeLibraryPath = lib.makeLibraryPath (
    appimageTools.defaultFhsEnvArgs.targetPkgs pkgs ++ appimageTools.defaultFhsEnvArgs.multiPkgs pkgs
  );
in
runCommand "${pname}-${version}"
  {
    nativeBuildInputs = [ makeWrapper ];

    passthru = {
      inherit
        codex
        disableCheckpoints
        sourceAppimageContents
        sourceAssets
        ;
      release = source;
    };

    meta = {
      description = "Latest T3 Code nightly with a bundled Codex CLI";
      homepage = "https://github.com/pingdotgg/t3code";
      changelog = "https://github.com/pingdotgg/t3code/releases/tag/v${version}";
      license = lib.licenses.mit;
      mainProgram = pname;
      platforms = [ "x86_64-linux" ];
      sourceProvenance = with lib.sourceTypes; [
        fromSource
        binaryNativeCode
      ];
    };
  }
  ''
    mkdir -p "$out/bin" "$out/share"

    if [ -d ${sourceAppimageContents}/usr/share ]; then
      cp -r ${sourceAppimageContents}/usr/share/* "$out/share/"
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
    fi

    makeWrapper ${sourceAppimageContents}/AppRun "$out/bin/${pname}" \
      --add-flags "--ignore-certificate-errors" \
      ${checkpointWrapperArgs} \
      --prefix LD_LIBRARY_PATH : "${runtimeLibraryPath}" \
      --prefix XDG_DATA_DIRS : "$out/share" \
      --prefix PATH : "${lib.makeBinPath [ codex ]}"

    if [ -n "$desktop_file" ]; then
      wrapProgram "$out/bin/${pname}" \
        --set CHROME_DESKTOP "$desktop_basename"
    fi

    if [ -f ${sourceAppimageContents}/.DirIcon ]; then
      install -Dm444 ${sourceAppimageContents}/.DirIcon "$out/share/pixmaps/${pname}.png"
    fi
  ''
