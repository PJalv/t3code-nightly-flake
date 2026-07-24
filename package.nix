{ lib, appimageTools, fetchurl, makeWrapper, codex }:

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
in
appimageTools.wrapType2 {
  inherit pname version src;
  nativeBuildInputs = [ makeWrapper ];

  extraInstallCommands = ''
    mkdir -p "$out/share"

    if [ -d ${appimageContents}/usr/share ]; then
      cp -r ${appimageContents}/usr/share/* "$out/share/"
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
        --prefix XDG_DATA_DIRS : "$out/share" \
        --prefix PATH : "${lib.makeBinPath [ codex ]}"
    else
      wrapProgram "$out/bin/${pname}" \
        --add-flags "--ignore-certificate-errors" \
        --prefix XDG_DATA_DIRS : "$out/share" \
        --prefix PATH : "${lib.makeBinPath [ codex ]}"
    fi

    if [ -f ${appimageContents}/.DirIcon ]; then
      install -Dm444 ${appimageContents}/.DirIcon "$out/share/pixmaps/${pname}.png"
    fi
  '';

  passthru = {
    inherit codex;
    release = source;
  };

  meta = {
    description = "T3 Code delayed-nightly with a bundled Codex CLI";
    homepage = "https://github.com/pingdotgg/t3code";
    changelog = "https://github.com/pingdotgg/t3code/releases/tag/v${version}";
    license = lib.licenses.mit;
    mainProgram = pname;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
