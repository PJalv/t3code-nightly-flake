{ lib
, stdenvNoCC
, stdenv
, cacert
, fetchPnpmDeps
, git
, glib
, libsecret
, nodejs_24
, pkg-config
, patch
, spdxLicenseData
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
    pnpm = pnpm_11;
    fetcherVersion = 4;
    # Unfiltered: filtered fetches skip packages the sandboxed install
    # resolves (observed with the Sep 13 lockfile and @effect/platform-bun).
    hash = "sha256-8h9YXCg5hOe1TmkgY0gbIKBoCPZfxYqRS33RROqAqYA=";
  };

  pnpmWorkspaces = [
    "."
    "t3..."
    "@t3tools/desktop..."
    "scripts..."
  ];

  nativeBuildInputs = [
    cacert
    patch
    git
    glib
    libsecret
    nodejs_24
    pkg-config
    pnpm_11
    pnpmConfigHook
    stdenv.cc
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
      node -e '
        const fs = require("fs");
        const [file, version] = process.argv.slice(1);
        const packageJson = JSON.parse(fs.readFileSync(file, "utf8"));
        packageJson.version = version;
        fs.writeFileSync(file, JSON.stringify(packageJson, null, 2) + "\n");
      ' "$packageJson" "${version}"
    done
    echo '${(lib.importJSON ./source.json).personalPatchSha256}  ${./patches/personal-qol.patch}' | sha256sum -c -
    patch -p1 < ${./patches/personal-qol.patch}
    mkdir -p .generated/third-party-licenses/spdx
    ln -s ${spdxLicenseData}/json/details .generated/third-party-licenses/spdx/v3.28.0
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
    # Ship only the compiled bundles. The server bundle inlines its JavaScript
    # dependencies; its few native/disk-backed externals come from the matching
    # upstream platform package in package-server.nix (and from the AppImage for
    # the desktop app). Copying the pnpm workspace with `cp -rL` dereferenced
    # every workspace symlink and duplicated the dependency graph ~1M files
    # deep, which made every fixup hook crawl the output for minutes.
    cp -r apps/server/dist "$out/apps/server/"
    cp -r apps/desktop/dist-electron "$out/apps/desktop/"

    test -f "$out/apps/server/dist/bin.mjs"
    test -f "$out/apps/desktop/dist-electron/main.cjs"

    runHook postInstall
  '';
}
