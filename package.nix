{
  lib,
  appimageTools,
  asar,
  fetchurl,
  makeWrapper,
  pkgs,
  runCommand,
  codex,
  pi,
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
        nativeBuildInputs = [
          asar
          pkgs.patchelf
        ];
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

        find "$out" -type f -print0 | while IFS= read -r -d $'\0' elf; do
          if patchelf --print-needed "$elf" >/dev/null 2>&1; then
            chmod u+w "$elf"
            patchelf \
              --force-rpath \
              --add-rpath "$out/usr/lib:${runtimeLibraryPath}" \
              "$elf"

            if patchelf --print-interpreter "$elf" >/dev/null 2>&1; then
              patchelf \
                --set-interpreter ${pkgs.stdenv.cc.bintools.dynamicLinker} \
                "$elf"
            fi
          fi
        done
      '';
  checkpointWrapperArgs = lib.optionalString disableCheckpoints "--set T3_DISABLE_CHECKPOINTS 1";
  runtimeLibraryPath = lib.makeLibraryPath (
    appimageTools.defaultFhsEnvArgs.targetPkgs pkgs
    ++ appimageTools.defaultFhsEnvArgs.multiPkgs pkgs
    ++ [ pkgs.stdenv.cc.cc.lib ]
  );
in
runCommand "${pname}-${version}"
  {
    nativeBuildInputs = [ makeWrapper ];

    passthru = {
      inherit
        codex
        pi
        disableCheckpoints
        sourceAppimageContents
        sourceAssets
        ;
      release = source;
    };

    meta = {
      description = "Latest T3 Code nightly with bundled Codex and Pi agent CLIs";
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

    makeWrapper ${sourceAppimageContents}/${pname} "$out/bin/${pname}" \
      --add-flags "--ignore-certificate-errors" \
      ${checkpointWrapperArgs} \
      --set APPDIR "${sourceAppimageContents}" \
      --set GSETTINGS_SCHEMA_DIR "${sourceAppimageContents}/usr/share/glib-2.0/schemas" \
      --run 'if ! ${pkgs.util-linux}/bin/unshare -Ur true 2>/dev/null; then set -- --no-sandbox "$@"; fi' \
      --prefix XDG_DATA_DIRS : "$out/share" \
      --prefix PATH : "${lib.makeBinPath [ codex pi pkgs.lsof ]}"

    if [ -n "$desktop_file" ]; then
      wrapProgram "$out/bin/${pname}" \
        --set CHROME_DESKTOP "$desktop_basename"
    fi

    if [ -f ${sourceAppimageContents}/.DirIcon ]; then
      install -Dm444 ${sourceAppimageContents}/.DirIcon "$out/share/pixmaps/${pname}.png"
    fi
  ''
