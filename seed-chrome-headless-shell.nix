{ chromeHeadlessShell }:
''
  set -eu
  # T3 Code downloads this pinned browser into T3 home on first use, but the
  # upstream build cannot load its libraries on NixOS. Point T3's install
  # location at the Nix-patched build instead; a matching runnable binary there
  # is what T3 treats as already installed.
  base="''${T3CODE_HOME:-''${HOME:-}/.t3}"
  if [ -z "''${T3CODE_HOME:-}" ] && [ ! -w "''${HOME:-/}" ]; then
    # Commands such as --help run with HOME=/homeless-shelter in Nix checks.
    exit 0
  fi

  root="$base/tools/chrome-headless-shell/linux64"
  dir="$root/${chromeHeadlessShell.version}"
  if [ "$(readlink "$dir" 2>/dev/null || true)" = '${chromeHeadlessShell}' ]; then
    exit 0
  fi

  mkdir -p "$root"
  # T3 treats `.install-*` entries as staging, so a crash leaves nothing it uses.
  staging="$root/.install-nix-$$"
  rm -f "$staging"
  ln -s '${chromeHeadlessShell}' "$staging"
  if [ -L "$dir" ]; then
    rm -f "$dir"
  elif [ -e "$dir" ]; then
    # Replace the unpatched download T3 made before this build was seeded.
    chmod -R u+w "$dir"
    rm -rf "$dir"
  fi
  mv -T "$staging" "$dir"
''
