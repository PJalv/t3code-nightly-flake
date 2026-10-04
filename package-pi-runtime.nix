{
  lib,
  gnugrep,
  writeShellScriptBin,
  pi,
  piSubagents,
  enableSubagents ? true,
}:
let
  launcher = if enableSubagents then ''
    # Forward management commands untouched; extension flags belong only on interactive sessions.
    case "''${1:-}" in
      --version|-v|install|remove|uninstall|update|list|config|auth|mcp)
        exec ${pi}/bin/pi "$@"
        ;;
    esac

    package_list="$(${pi}/bin/pi list 2>/dev/null || true)"
    extra_args=()
    agent_dir="''${PI_CODING_AGENT_DIR:-''${HOME}/.pi/agent}"
    has_named_extension() {
      local pattern="$1"
      local candidate
      for candidate in \
        "$agent_dir"/extensions/*"$pattern"* \
        "$PWD"/.pi/extensions/*"$pattern"*; do
        [ -e "$candidate" ] && return 0
      done
      return 1
    }

    if ${gnugrep}/bin/grep -qi 'pi-mcp-adapter' <<< "$package_list"; then
      printf '%s\n' "t3code-pi: pi-mcp-adapter disables native MCP. Run \`pi remove npm:pi-mcp-adapter\` to use Pi's built-in MCP support." >&2
    fi
    if ${gnugrep}/bin/grep -qi 'subagent' <<< "$package_list" || has_named_extension subagent; then
      printf '%s\n' "t3code-pi: a user pi-subagents is installed; the pinned flake version is being used. Run \`pi remove npm:@tintinweb/pi-subagents\` to avoid loading two copies." >&2
    fi

    exec ${pi}/bin/pi --extension ${piSubagents}/lib/pi-subagents/src/index.ts "$@"
  '' else ''
    exec ${pi}/bin/pi "$@"
  '';
  description = if enableSubagents
    then "Standalone Pi runtime with T3's pinned subagent extension"
    else "Pi runtime for T3 Code; delegation uses T3's native MCP integration";
in
(writeShellScriptBin "pi" ''
  # Pi locates bundled themes and other runtime assets through this directory.
  # Never inherit it from a parent Pi agent or an older install.
  export PI_PACKAGE_DIR=${pi}/lib/node_modules/@earendil-works/pi-coding-agent
  ${launcher}
'').overrideAttrs (old: {
  pname = "t3code-pi-runtime";
  version = pi.version;
  passthru = (old.passthru or {}) // { inherit pi piSubagents; };
  meta = (old.meta or {}) // {
    inherit description;
    license = lib.licenses.mit;
    mainProgram = "pi";
  };
})
