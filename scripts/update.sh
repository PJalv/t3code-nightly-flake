#!/usr/bin/env bash
set -euo pipefail

repo="pingdotgg/t3code"
delay_hours="${T3CODE_DELAY_HOURS:-0}"
check_only=false

usage() {
  cat <<'EOF'
Usage: scripts/update.sh [--delay-hours HOURS] [--check]

Compares the newest T3 Code nightly with the nightly that PJalv/t3code
personal/nightly is based on (source.json). Use --delay-hours HOURS to require
a minimum release age. When the base is current, refreshes the pinned nixpkgs;
with --check it only reports. A newer nightly needs the fork branch rebased
first, so this script never moves the pin itself.
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
        revision: $release.target_commitish
      }
  )
' "$releases" > "$candidate"

if [ "$(jq -r 'type' "$candidate")" != "object" ]; then
  echo "no eligible nightly found at least ${delay_hours} hours old" >&2
  exit 1
fi

new_version="$(jq -r '.version' "$candidate")"
new_revision="$(jq -r '.revision' "$candidate")"
base_version="$(jq -r '.version' "$root/source.json")"
# An age delay can select a nightly older than the fork base; only a newer one is an update.
newer="$(jq -r --slurpfile base "$root/source.json" \
  '(.publishedAt | fromdateiso8601) > ($base[0].publishedAt | fromdateiso8601)' "$candidate")"

if [ "$newer" != true ]; then
  echo "T3 Code already current: fork base ${base_version} (${delay_hours}-hour delay)"
  if $check_only; then
    exit 0
  fi
elif $check_only; then
  echo "update available: fork base ${base_version} -> ${new_version} (${new_revision})"
  exit 10
else
  echo "fork base is ${base_version}; rebase PJalv/t3code personal/nightly onto ${new_version} (${new_revision}), then move the flake input, source.json and the pnpm deps hash together" >&2
  exit 1
fi

(
  cd "$root"
  nix flake update nixpkgs
)

echo "refreshed pinned nixpkgs"
