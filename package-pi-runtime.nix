{
  lib,
  gnugrep,
  runCommand,
  writeShellScriptBin,
  pi,
  piSubagents,
}: let
  subagentExtension = runCommand "t3code-pi-subagent-extension" {} ''
    mkdir -p "$out"
    cp -r ${pi}/lib/node_modules/@earendil-works/pi-coding-agent/examples/extensions/subagent/. "$out/"
    chmod -R u+w "$out"

    # Provide one neutral built-in role instead of Pi's specialized example
    # roles. The child inherits the active parent model and all available tools.
    rm -rf "$out/agents"
    mkdir -p "$out/agents"
    substitute ${pi}/lib/node_modules/@earendil-works/pi-coding-agent/examples/extensions/subagent/agents/worker.md "$out/agents/default.md" \
      --replace-fail 'name: worker' 'name: default' \
      --replace-fail 'description: General-purpose subagent with full capabilities, isolated context' 'description: General-purpose subagent with full capabilities and isolated context' \
      --replace-fail 'You are a worker agent with full capabilities.' 'You are the default subagent with full capabilities.'
    sed -i '/^model:/d' "$out/agents/default.md"

    substituteInPlace "$out/index.ts" \
      --replace-fail \
        'const agents = discovery.agents;' \
        'const agents = discovery.agents.map((agent) => ({ ...agent, model: agent.model ?? (ctx.model ? ctx.model.provider + "/" + ctx.model.id : undefined) }));' \
      --replace-fail \
        'export default function (pi: ExtensionAPI) {' \
        'export default function (pi: ExtensionAPI) {
	const userAgentNames = discoverAgents(process.cwd(), "user").agents.map((agent) => agent.name).join(", ") || "none";' \
      --replace-fail \
        '"Modes: single (agent + task), parallel (tasks array), chain (sequential with {previous} placeholder).",' \
        '"Modes: single (agent + task), parallel (tasks array), chain (sequential with {previous} placeholder).",
			`Available user agent names: ''${userAgentNames}. Use "default" unless the user requests a specialized agent by name.`,'

    substituteInPlace "$out/agents.ts" \
      --replace-fail \
        'const userAgents = scope === "project" ? [] : loadAgentsFromDir(userDir, "user");' \
        'const userAgents = scope === "project" ? [] : [...loadAgentsFromDir("'"$out"'/agents", "user"), ...loadAgentsFromDir(userDir, "user")];'
  '';
in
  (writeShellScriptBin "pi" ''
    # Pi uses this directory to locate bundled themes and other runtime assets.
    # Never inherit PI_PACKAGE_DIR from a parent Pi agent or an older install.
    export PI_PACKAGE_DIR=${pi}/lib/node_modules/@earendil-works/pi-coding-agent

    # Forward pi's management subcommands untouched: injecting the pinned
    # --extension flags below would move the subcommand out of argv[1] and pi
    # would then treat e.g. `remove` as a coding prompt instead of a command.
    case "''${1:-}" in
      --version|-v|install|remove|uninstall|update|list|config|auth|mcp)
        exec ${pi}/bin/pi "$@"
        ;;
    esac

    # Shell and T3 sessions share native MCP and the pinned subagent extension.
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

    # An installed adapter replaces Pi's native MCP extension. Leave user
    # configuration untouched and explain how to enable native MCP.
    if ${gnugrep}/bin/grep -qi 'pi-mcp-adapter' <<< "$package_list"; then
      printf '%s\n' "t3code-pi: pi-mcp-adapter disables native MCP. Run \`pi remove npm:pi-mcp-adapter\` to use Pi's built-in MCP support." >&2
    fi
    if ${gnugrep}/bin/grep -qi 'subagent' <<< "$package_list" || has_named_extension subagent; then
      printf '%s\n' "t3code-pi: a user pi-subagents is installed; the pinned flake version is being used. Run \`pi remove npm:@tintinweb/pi-subagents\` to avoid loading two copies." >&2
    fi
    extra_args+=(--extension ${piSubagents}/lib/pi-subagents/src/index.ts)

    exec ${pi}/bin/pi "''${extra_args[@]}" "$@"
  '').overrideAttrs (old: {
    pname = "t3code-pi-runtime";
    version = pi.version;
    passthru =
      (old.passthru or {})
      // {
        inherit pi piSubagents subagentExtension;
      };
    meta =
      (old.meta or {})
      // {
        description = "Pi runtime with native MCP and T3 Code subagent defaults";
        license = lib.licenses.mit;
        mainProgram = "pi";
      };
  })
