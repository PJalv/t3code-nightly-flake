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
    package_list="$(${pi}/bin/pi list 2>/dev/null || true)"
    extra_args=()
    has_mcp_adapter=0

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
      has_mcp_adapter=1
    elif ! has_named_extension mcp; then
      extra_args+=(--extension ${piMcpAdapter}/lib/pi-mcp-adapter/index.ts)
      has_mcp_adapter=1
    fi

    # Installed pi-mcp-adapter releases understand --mcp-config even when they
    # predate T3's environment hook. Add the thread-private config only when
    # that adapter is active, so other MCP extensions do not see an unknown flag.
    if [ "$has_mcp_adapter" -eq 1 ] && [ -n "''${T3CODE_PI_MCP_CONFIG:-}" ]; then
      extra_args+=(--mcp-config "$T3CODE_PI_MCP_CONFIG")
    fi

    # The managed runtime uses the exact tested pi-subagents release unless
    # the user explicitly supplies a subagent extension or Pi package.
    if ! ${gnugrep}/bin/grep -qi 'subagent' <<< "$package_list" \
      && ! has_named_extension subagent; then
      extra_args+=(--extension ${piSubagents}/lib/pi-subagents/src/index.ts)
    fi

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
