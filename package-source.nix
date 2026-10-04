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
    hash = "sha256-kJaXB/mf39ilnPGU6ms6pCKYF1Ql0DUTOJw4m3sYfjs=";
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
    cp -r apps/server/dist "$out/apps/server/"
    # The source-built CLI externalizes native/runtime packages such as
    # @ff-labs/fff-node. Preserve the filtered server workspace dependencies so
    # package-server.nix can run dist/bin.mjs without the published launcher.
    cp -rL apps/server/node_modules "$out/apps/server/"
    # The server CLI externalizes Cursor SDK dependencies whose pnpm peer
    # context sits beside (not inside) the SDK package directory.
    cursorContext="$(find node_modules/.pnpm -maxdepth 1 -type d -name '@cursor+sdk@1.0.31*' -print -quit)"
    if [ -n "$cursorContext" ]; then
      mkdir -p "$out/apps/server/node_modules/@cursor/sdk/node_modules"
      for scope in @bufbuild @connectrpc @statsig; do
        if [ -d "$cursorContext/node_modules/$scope" ]; then
          cp -rL "$cursorContext/node_modules/$scope" "$out/apps/server/node_modules/@cursor/sdk/node_modules/"
        fi
      done
      if [ -d "$cursorContext/node_modules/zod" ]; then
        cp -rL "$cursorContext/node_modules/zod" "$out/apps/server/node_modules/@cursor/sdk/node_modules/"
      fi
    fi
    cp -r apps/desktop/dist-electron "$out/apps/desktop/"

    test -f "$out/apps/server/dist/bin.mjs"
    test -f "$out/apps/desktop/dist-electron/main.cjs"

    runHook postInstall
  '';
}
