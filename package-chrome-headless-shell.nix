{ lib
, stdenvNoCC
, fetchurl
, unzip
, autoPatchelfHook
, alsa-lib
, at-spi2-atk
, at-spi2-core
, dbus
, expat
, glib
, libgbm
, libxkbcommon
, nspr
, nss
, systemd
, xorg
, version
, sha256
}:

# The pinned Chrome for Testing headless shell T3 Code downloads for HTML
# previews and server browser tabs (apps/server/src/preview/PreviewBrowser.ts).
# Upstream's build expects FHS libraries; patch it to Nix's so it runs on NixOS.
# The version and checksum come from the pinned T3 source, so a T3 update that
# bumps the browser updates this package with it.
stdenvNoCC.mkDerivation {
  pname = "t3code-chrome-headless-shell";
  inherit version;

  src = fetchurl {
    url = "https://storage.googleapis.com/chrome-for-testing-public/${version}/linux64/chrome-headless-shell-linux64.zip";
    inherit sha256;
  };

  nativeBuildInputs = [ unzip autoPatchelfHook ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    dbus
    expat
    glib
    libgbm
    libxkbcommon
    nspr
    nss
    systemd # libudev
    xorg.libX11
    xorg.libXcomposite
    xorg.libXdamage
    xorg.libXext
    xorg.libXfixes
    xorg.libXrandr
    xorg.libxcb
  ];

  # Chrome dlopens its bundled GL/Vulkan libraries from its own directory.
  autoPatchelfIgnoreMissingDeps = [ "libGLESv2.so" "libEGL.so" ];

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -r . "$out/"
    test -x "$out/chrome-headless-shell"
    runHook postInstall
  '';

  meta = {
    description = "Chrome for Testing headless shell pinned by T3 Code, patched for NixOS";
    homepage = "https://googlechromelabs.github.io/chrome-for-testing/";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
  };
}
