{ deviceHub }:
''
  set -eu
  # Desktop launches its embedded server directly, not through t3code-server.
  # Both launchers seed the same hub so neither falls back to npm at runtime.
  base="''${T3CODE_HOME:-''${HOME:-}/.t3}"
  if [ -z "''${T3CODE_HOME:-}" ] && [ ! -w "''${HOME:-/}" ]; then
    # Commands such as --help run with HOME=/homeless-shelter in Nix checks.
    exit 0
  fi

  parent="$base/tools/expo-device-hub"
  dir="$parent/${deviceHub.hubVersion}"
  if [ "$(cat "$dir/.install-complete" 2>/dev/null)" = '${deviceHub.hubVersion}' ] &&
     [ "$(cat "$dir/.t3-bundled-from" 2>/dev/null)" = '${deviceHub}' ]; then
    exit 0
  fi

  mkdir -p "$parent"
  staging="$(mktemp -d "$parent/.staging-XXXXXXXX")"
  trap 'chmod -R u+w "$staging" 2>/dev/null || true; rm -rf "$staging"' EXIT
  mkdir -p "$staging/node_modules"
  cp -r ${deviceHub}/lib/node_modules/expo-device-hub "$staging/node_modules/"
  chmod -R u+w "$staging"
  echo '${deviceHub.hubVersion}' > "$staging/.install-complete"
  echo '${deviceHub}' > "$staging/.t3-bundled-from"

  if [ -d "$dir" ]; then
    chmod -R u+w "$dir"
    rm -rf "$dir"
  fi
  mv "$staging" "$dir"
  trap - EXIT
''
