{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:
buildNpmPackage rec {
  pname = "pi-mcp-adapter";
  version = "2.21.1";

  src = fetchFromGitHub {
    owner = "nicobailon";
    repo = "pi-mcp-adapter";
    rev = "v${version}";
    hash = "sha256-voO8gCDjGtXoSiEQM/D4lL4JXrz5be3HZ5ol7KYVCzI=";
  };

  npmDepsHash = "sha256-YZbDesWby6kw4sMcTu0gwLj694aX5Ttf0t0KxFRbKkk=";
  dontNpmBuild = true;

  postPatch = ''
    cp ${./npm/pi-mcp-adapter/package.json} package.json
    cp ${./npm/pi-mcp-adapter/package-lock.json} package-lock.json

    substituteInPlace utils.ts \
      --replace-fail \
        'export function getConfigPathFromArgv(): string | undefined {
  const idx = process.argv.indexOf("--mcp-config");
  if (idx >= 0 && idx + 1 < process.argv.length) {
    return process.argv[idx + 1];
  }
  return undefined;
}' \
        'export function getConfigPathFromArgv(): string | undefined {
  const idx = process.argv.indexOf("--mcp-config");
  if (idx >= 0 && idx + 1 < process.argv.length) {
    return process.argv[idx + 1];
  }
  return process.env.T3CODE_PI_MCP_CONFIG?.trim() || undefined;
}'
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/pi-mcp-adapter"
    cp -r . "$out/lib/pi-mcp-adapter"

    test -f "$out/lib/pi-mcp-adapter/index.ts"
    test -d "$out/lib/pi-mcp-adapter/node_modules/@modelcontextprotocol/sdk"

    runHook postInstall
  '';

  meta = {
    description = "MCP adapter extension for the Pi coding agent";
    homepage = "https://github.com/nicobailon/pi-mcp-adapter";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
