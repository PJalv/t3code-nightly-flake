#!/usr/bin/env bash
set -euo pipefail

repo="pingdotgg/t3code"
delay_hours="${T3CODE_DELAY_HOURS:-0}"
check_only=false

usage() {
  cat <<'EOF'
Usage: scripts/update.sh [--delay-hours HOURS] [--check]

Selects the newest T3 Code nightly. Use --delay-hours HOURS to require a
minimum release age. Updates source.json and refreshes the pinned nixpkgs.
EOF
}

while (($#)); do
  case "$1" in
    --delay-hours)
      delay_hours="${2:?--delay-hours requires a value}"
      shift 2
      ;;
    --check)
      check_only=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! [[ "$delay_hours" =~ ^[0-9]+$ ]]; then
  echo "delay hours must be a non-negative integer" >&2
  exit 2
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cutoff="$(date -u -d "-${delay_hours} hours" +%s)"
releases="$(mktemp)"
candidate="$(mktemp)"
trap 'rm -f "$releases" "$candidate"' EXIT

github_auth=()
if [ -n "${GITHUB_TOKEN:-}" ]; then
  github_auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

curl -fsSL \
  "${github_auth[@]}" \
  -H 'Accept: application/vnd.github+json' \
  -H 'X-GitHub-Api-Version: 2022-11-28' \
  "https://api.github.com/repos/${repo}/releases?per_page=100" > "$releases"

jq --argjson cutoff "$cutoff" '
  first(
    sort_by(.published_at) | reverse | .[]
    | select(.draft == false and .prerelease == true)
    | select(.tag_name | test("^v[0-9].*-nightly\\."))
    | select((.published_at | fromdateiso8601) <= $cutoff)
    | . as $release
    | ($release.assets | map(select(.name == ("t3-" + ($release.tag_name | sub("^v"; "")) + "-linux-x64.tar.gz"))) | first) as $server
    | select($server != null)
    | .assets[]
    | select(.name | endswith("-x86_64.AppImage"))
    | {
        version: ($release.tag_name | sub("^v"; "")),
        tag: $release.tag_name,
        publishedAt: $release.published_at,
        url: .browser_download_url,
        serverUrl: $server.browser_download_url
      }
  )
' "$releases" > "$candidate"

if [ "$(jq -r 'type' "$candidate")" != "object" ]; then
  echo "no eligible nightly found at least ${delay_hours} hours old" >&2
  exit 1
fi

new_version="$(jq -r '.version' "$candidate")"
old_version="$(jq -r '.version' "$root/source.json")"

# The AppImage, source revision, dependency hash, and QoL patch must move together.
if [ "$new_version" != "$old_version" ] && ! $check_only && [ -s "$root/patches/personal-qol.patch" ]; then
  echo "personal QoL build is pinned to ${old_version}; rebase the patch and update the source pin and dependency hash before upgrading to ${new_version}" >&2
  exit 1
fi

if [ "$new_version" = "$old_version" ]; then
  echo "T3 Code already current: ${new_version} (${delay_hours}-hour delay)"
  if $check_only; then
    exit 0
  fi
else
  if $check_only; then
    echo "update available: ${old_version} -> ${new_version}"
    exit 10
  fi

  url="$(jq -r '.url' "$candidate")"
  hash="$(nix store prefetch-file --json "$url" | jq -r '.hash')"
  server_url="$(jq -r '.serverUrl' "$candidate")"
  server_hash="$(nix store prefetch-file --json "$server_url" | jq -r '.hash')"
  jq \
    --arg hash "$hash" \
    --arg serverHash "$server_hash" \
    '. + { hash: $hash, serverHash: $serverHash }' \
    "$candidate" > "$root/source.json.new"
  mv "$root/source.json.new" "$root/source.json"
  echo "updated T3 Code: ${old_version} -> ${new_version}"
fi

(
  cd "$root"
  nix flake update nixpkgs
)

echo "refreshed pinned nixpkgs"
