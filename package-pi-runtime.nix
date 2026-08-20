{
  lib,
  gnugrep,
  runCommand,
  writeShellScriptBin,
  pi,
  piMcpAdapter,
  piSubagents,
}: let
  subagentExtension = runCommand "t3code-pi-subagent-extension" {} ''
    mkdir -p "$out"
    cp -r ${pi}/libexec/pi/examples/extensions/subagent/. "$out/"
    chmod -R u+w "$out"

    # Provide one neutral built-in role instead of Pi's specialized example
    # roles. The child inherits the active parent model and all available tools.
    rm -rf "$out/agents"
    mkdir -p "$out/agents"
    substitute ${pi}/libexec/pi/examples/extensions/subagent/agents/worker.md "$out/agents/default.md" \
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
    # The managed pi runs from a dedicated agent dir (~/.pi-t3code) whose npm
    # holds NO user-installed extensions, and this export redirects the exec'd
    # pi to it. The pinned --extension flags below are therefore the only
    # mcp-adapter/subagents source. Personal pi keeps ~/.pi/agent (where users
    # install subagents/mcp freely); the two no longer collide.
    export PI_CODING_AGENT_DIR="''${PI_CODING_AGENT_DIR:-''${HOME}/.pi-t3code}"
    package_list="$(${pi}/bin/pi list 2>/dev/null || true)"
    extra_args=()
    has_mcp_adapter=0
    agent_dir="$PI_CODING_AGENT_DIR"
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

    # The managed runtime ALWAYS loads the exact tested pi-mcp-adapter and
    # pi-subagents releases bundled in this flake. User-installed or local
    # copies are never used, so `pi update --extensions` cannot silently replace
    # the pinned versions. A warning points at any copy that would otherwise be
    # loaded twice, so it can be removed with `pi remove`.
    if ${gnugrep}/bin/grep -qi 'pi-mcp-adapter' <<< "$package_list" || has_named_extension mcp; then
      printf '%s\n' "t3code-pi: a user pi-mcp-adapter is installed; the pinned flake version is being used. Run \`pi remove npm:pi-mcp-adapter\` to avoid loading two copies." >&2
    fi
    if ${gnugrep}/bin/grep -qi 'subagent' <<< "$package_list" || has_named_extension subagent; then
      printf '%s\n' "t3code-pi: a user pi-subagents is installed; the pinned flake version is being used. Run \`pi remove npm:@tintinweb/pi-subagents\` to avoid loading two copies." >&2
    fi
    extra_args+=(--extension ${piMcpAdapter}/lib/pi-mcp-adapter/index.ts)
    if [ -n "''${T3CODE_PI_MCP_CONFIG:-}" ]; then
      extra_args+=(--mcp-config "''${T3CODE_PI_MCP_CONFIG}")
    fi
    extra_args+=(--extension ${piSubagents}/lib/pi-subagents/src/index.ts)

    exec ${pi}/bin/pi "''${extra_args[@]}" "$@"
  '').overrideAttrs (old: {
    pname = "t3code-pi-runtime";
    version = pi.version;
    passthru =
      (old.passthru or {})
      // {
        inherit pi piMcpAdapter piSubagents subagentExtension;
      };
    meta =
      (old.meta or {})
      // {
        description = "Pi runtime with T3 Code MCP and subagent defaults";
        license = lib.licenses.mit;
        mainProgram = "pi";
      };
  })
