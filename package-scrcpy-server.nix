{
  lib,
  fetchurl,
  jdk,
  unzip,
}:

# serve-emu streams physical Android devices over scrcpy and expects the
# scrcpy server jar at vendor/serve-emu/vendor/scrcpy-server-v<version>.
# Without it serve-emu fetches the jar from GitHub on first use, which fails
# offline and cannot write inside a read-only store path.
let
  version = "4.0";
in
fetchurl {
  url = "https://github.com/Genymobile/scrcpy/releases/download/v${version}/scrcpy-server-v${version}";

  hash = "sha256-hJJL1WSh62CJyHLHUh+WgFiXf5H1/wJRSox0r/MhDzo=";

  passthru = { inherit version; };

  meta = {
    description = "scrcpy server, pushed to Android devices to stream their screen";
    homepage = "https://github.com/Genymobile/scrcpy";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
  };
}
