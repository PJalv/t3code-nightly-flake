{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:
buildNpmPackage rec {
  pname = "pi-mcp-adapter";
  version = "2.34.0";

  src = fetchFromGitHub {
    owner = "nicobailon";
    repo = "pi-mcp-adapter";
    rev = "v${version}";
    hash = "sha256-YpiJROIG0/U81wAoImjktbg/d5wGnc6o130IlOrTyEE=";
  };

  npmDepsHash = "sha256-WC+UDmVqmnKK7Oe9og9oL+kjwK4Uyt1a6NGFFKfhrVs=";
  dontNpmBuild = true;

  postPatch = ''
    cp ${./npm/pi-mcp-adapter/package.json} package.json
    cp ${./npm/pi-mcp-adapter/package-lock.json} package-lock.json
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
