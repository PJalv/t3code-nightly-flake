{ lib
, stdenvNoCC
, cacert
, fetchPnpmDeps
, git
, nodejs_24
, pnpm_11
, pnpmConfigHook
, src
, version
}:

stdenvNoCC.mkDerivation {
  pname = "t3code-source-assets";
  inherit src version;

  pnpmDeps = fetchPnpmDeps {
    pname = "t3code-source-assets";
    inherit src version;
    fetcherVersion = 4;
    pnpmWorkspaces = [
      "."
      "t3..."
      "@t3tools/desktop..."
    ];
    hash = "sha256-T4cchShV3HI4jWWw1n6oENciExjQKupN9P1YEIbIbcc=";
  };

  pnpmWorkspaces = [
    "."
    "t3..."
    "@t3tools/desktop..."
  ];

  nativeBuildInputs = [
    cacert
    git
    nodejs_24
    pnpm_11
    pnpmConfigHook
  ];

  ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
  PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
  APP_VERSION = version;
  SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";

  postPatch = ''
    for packageJson in \
      apps/server/package.json \
      apps/web/package.json \
      apps/desktop/package.json
    do
      substituteInPlace "$packageJson" \
        --replace-fail '"version": "0.0.31"' '"version": "${version}"'
    done
  '';

  buildPhase = ''
    runHook preBuild

    # Filtered pnpm installs expose Effect under the server workspace, while
    # the server release script imports it from a repository-root helper.
    ln -s ../apps/server/node_modules/effect node_modules/effect
    pnpm exec vp run build:desktop

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/apps/server" "$out/apps/desktop"
    cp -r apps/server/dist "$out/apps/server/"
    cp -r apps/desktop/dist-electron "$out/apps/desktop/"

    test -f "$out/apps/server/dist/bin.mjs"
    test -f "$out/apps/desktop/dist-electron/main.cjs"

    runHook postInstall
  '';
}
