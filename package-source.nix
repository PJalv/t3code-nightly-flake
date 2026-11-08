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
, runCommand
, src
, version
}:

let
  # The pnpm dependency fetch needs only the lockfile, workspace manifest and
  # package.jsons. Fetching from the full source briefly needs ~13G of build
  # transient on /, which no longer fits next to the store; the pruned source
  # removes the full-tree unpack from that peak. The fetch output depends only
  # on the lockfile and manifests, and this flake always fetches with this
  # same pruned source, so the hash stays deterministic.
  pnpmFetchSrc = runCommand "t3code-pnpm-fetch-src" { } ''
    mkdir -p $out/apps $out/infra $out/packages $out/evals $out/scripts
    cp ${src}/pnpm-lock.yaml ${src}/pnpm-workspace.yaml ${src}/package.json $out/
    cp ${src}/.pnpmfile.cjs $out/.pnpmfile.cjs
    cp -r ${src}/patches $out/patches
    # local (file:) dependencies referenced by the lockfile
    mkdir -p $out/apps/mobile/deps $out/apps/mobile/modules $out/deps
    cp ${src}/apps/mobile/deps/*.tgz $out/apps/mobile/deps/ 2>/dev/null || true
    for m in t3-highlights t3-review-diff t3-source-text t3-terminal; do
      cp -r ${src}/apps/mobile/modules/$m $out/apps/mobile/modules/$m
    done
    cp ${src}/deps/*.tgz $out/deps/ 2>/dev/null || true
    chmod -R u+w $out
    for f in $(cd ${src} && find apps infra packages evals scripts oxlint-plugin-t3code -name package.json -not -path '*/node_modules/*' 2>/dev/null); do
      mkdir -p "$out/$(dirname $f)"
      cp "${src}/$f" "$out/$f"
    done
    for f in $(cd ${src} && find . -maxdepth 1 -name '.npmrc' -o -maxdepth 1 -name 'npmrc' 2>/dev/null); do
      cp "${src}/$f" "$out/$f"
    done
  '';
in

stdenvNoCC.mkDerivation {
  pname = "t3code-source-assets";
  inherit src version;

  pnpmDeps = (fetchPnpmDeps {
    pname = "t3code-source-assets";
    src = pnpmFetchSrc;
    inherit version;
    pnpm = pnpm_11;
    fetcherVersion = 4;
    # Unfiltered: filtered fetches skip packages the sandboxed install
    # resolves (observed with the Sep 13 lockfile and @effect/platform-bun).
    # The 20261108.4353 lockfile only dropped the @napi-rs/keyring importer
    # lines; the fetched store (and hash) is identical to 20261107.4314 —
    # proven by a real fetch with a placeholder hash reporting this value
    # as `got:`.
    hash = "sha256-rOX3lMbvJsPmeqc/9yJM2kFDOopyCAjts5FSy/2gvdA=";
  }).overrideAttrs (old: {
    # The unpacked pnpm store, the virtual store, pnpm's download cache
    # (HOME) and the installed node_modules are all dead after the fixup
    # tarball is written; deleting them before nix exports the output keeps
    # the export copy (which doubles $out) from exhausting /. Does not change
    # any output byte, so the fixed-output hash is unaffected.
    fixupPhase = old.fixupPhase + ''
      echo "PNPMDEPS_RM storePath=''${storePath:-UNSET} HOME=''${HOME:-UNSET} virtualStore=''${virtualStorePath:-UNSET}" >&2
      rm -rf node_modules || true
      for d in "''${storePath:-}" "''${virtualStorePath:-}" "''${HOME:-}" /homeless-shelter; do
        [ -n "$d" ] && [ -e "$d" ] && chmod -R u+w "$d" 2>/dev/null; rm -rf "$d"
      done
      echo "PNPMDEPS_RM done" >&2
    '';
  });

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

  # pnpm executes whatever `packageManager` pins; without this it replaces itself
  # with pnpm 12.14.0, which is not the version this derivation provides.
  npm_config_manage_package_manager_versions = "false";
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
