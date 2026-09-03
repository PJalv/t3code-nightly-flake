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
    hash = "sha256-Woq+uRPKCwkDiWNJnN4k48UTbe2U8tZfTVAACUZS8BA=";
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
    node <<'NODE'
    const fs = require("fs");

    const replace = (file, from, to) => {
      const source = fs.readFileSync(file, "utf8");
      if (!source.includes(from)) throw new Error(`missing patch anchor in $file`);
      fs.writeFileSync(file, source.replace(from, to));
    };

    const drivers = "apps/server/src/provider/builtInDrivers.ts";
    replace(
      drivers,
      'import { PiDriver, type PiDriverEnv } from "./Drivers/PiDriver.ts";',
      'import { PiDriver, type PiDriverEnv } from "./Drivers/PiDriver.ts";\n' +
        'import { AntigravityDriver, type AntigravityDriverEnv } from "./Drivers/AntigravityDriver.ts";',
    );
    replace(drivers, "export type BuiltInDriversEnv =\n  | ClaudeDriverEnv", "export type BuiltInDriversEnv =\n  | AntigravityDriverEnv\n  | ClaudeDriverEnv");
    replace(drivers, "  OpenCodeDriver,\n  PiDriver,", "  OpenCodeDriver,\n  AntigravityDriver,\n  PiDriver,");

    const anchoring = "apps/web/src/components/chat/timelineScrollAnchoring.ts";
    replace(
      anchoring,
      "export function getRowBottom",
      `export function keepTimelineEndVisibleAfterOverlayGrowth({
      timeline,
      previousOverlayHeight,
      overlayHeight,
      followingEnd,
    }: {
      readonly timeline: { scrollToEnd: (options: { animated: boolean }) => unknown } | null;
      readonly previousOverlayHeight: number;
      readonly overlayHeight: number;
      readonly followingEnd: boolean;
    }): void {
      if (timeline && followingEnd && overlayHeight > previousOverlayHeight) {
        void timeline.scrollToEnd({ animated: false });
      }
    }

    export function getRowBottom`,
    );
    NODE

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
