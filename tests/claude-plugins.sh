#!/usr/bin/env bash
# Behavior of modules/claude-plugins/activate.sh against a fake claude CLI.
# usage: claude-plugins.sh <activate.sh>
set -euo pipefail

script=${1:?usage: claude-plugins.sh <activate.sh>}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

export HOME=$tmp/home CALLS=$tmp/calls MARKETPLACES=$tmp/marketplaces.json PLUGINS=$tmp/plugins.json
export CLAUDE=$tmp/claude
mkdir -p "$HOME"
cat >"$CLAUDE" <<'SH'
#!/usr/bin/env bash
echo "$*" >>"$CALLS"
case "$*" in
"plugin marketplace list --json") cat "$MARKETPLACES" ;;
"plugin list --json") cat "$PLUGINS" ;;
esac
SH
chmod +x "$CLAUDE"

# A marketplace repo with a listed plugin, an unlisted one, and a remote source.
market=$tmp/src
mkdir -p "$market/.claude-plugin" "$market/team/skills/alpha" "$market/team/skills/notes" "$market/other/skills/alpha"
echo '---' >"$market/team/skills/alpha/SKILL.md"
cat >"$market/.claude-plugin/marketplace.json" <<'JSON'
{"name": "acme", "plugins": [
  {"name": "team", "source": "./team"},
  {"name": "other", "source": "./other"},
  {"name": "remote", "source": {"source": "github", "repo": "acme/remote"}}
]}
JSON
git -C "$market" init --quiet
git -C "$market" add .
git -C "$market" -c user.name=t -c user.email=t@t commit --quiet -m init

config=$HOME/.config/claude-plugins.json
links=$HOME/.local/share/claude-plugins
mkdir -p "$(dirname "$config")"
activate() {
  : >"$CALLS"
  bash "$script" "$config" "$links" 2>"$tmp/stderr"
}

# No config: links removed, Claude untouched.
mkdir -p "$links/plugins"
activate
[[ ! -e $links ]] || fail "links kept without config"
[[ ! -s $CALLS ]] || fail "claude called without config"

# Invalid config warns and changes nothing.
echo '{"path": 1}' >"$config"
activate
grep -qF 'must be {"path": string' "$tmp/stderr" || fail "invalid config not reported"

# Missing checkout is cloned from `repo`; listed plugins are linked and installed,
# unlisted enabled plugins of the same marketplace are disabled.
printf '{"path": "~/work/market", "repo": "%s", "plugins": ["team", "remote", "missing"]}\n' "$market" >"$config"
echo '[]' >"$MARKETPLACES"
cat >"$PLUGINS" <<'JSON'
[
  {"id": "other@acme", "scope": "user", "enabled": true},
  {"id": "keep@elsewhere", "scope": "user", "enabled": true}
]
JSON
activate
[[ -f $HOME/work/market/.claude-plugin/marketplace.json ]] || fail "checkout not cloned"
[[ $(readlink "$links/plugins/team") == "$HOME/work/market/team" ]] || fail "plugin root not linked"
[[ $(readlink "$links/skills/alpha") == "$HOME/work/market/team/skills/alpha" ]] || fail "skill not linked"
[[ ! -e $links/skills/notes ]] || fail "directory without SKILL.md linked"
[[ ! -e $links/plugins/remote && ! -e $links/plugins/missing ]] || fail "non-local plugin linked"
grep -qF 'no local plugin directory for remote' "$tmp/stderr" || fail "remote plugin not reported"
grep -qxF "plugin marketplace add $HOME/work/market" "$CALLS" || fail "marketplace not added"
grep -qxF 'plugin install team@acme --scope user' "$CALLS" || fail "plugin not installed"
grep -qxF 'plugin disable other@acme --scope user' "$CALLS" || fail "unlisted plugin not disabled"
grep -q 'keep@elsewhere' "$CALLS" && fail "other marketplace touched"

# Duplicate plugin names are linked and installed once.
printf '{"path": "~/work/market", "plugins": ["team", "team"]}\n' >"$config"
echo '[]' >"$PLUGINS"
activate
[[ $(grep -c 'plugin install team@acme' "$CALLS") == 1 ]] || fail "duplicate plugin installed twice"
[[ ! -e $HOME/work/market/team/team ]] || fail "link created inside the checkout"

# Known marketplace at the same path: re-enable a disabled plugin, no re-add.
printf '[{"name": "acme", "source": "directory", "installLocation": "%s"}]\n' "$HOME/work/market" >"$MARKETPLACES"
echo '[{"id": "team@acme", "scope": "user", "enabled": false}]' >"$PLUGINS"
activate
grep -q 'marketplace add' "$CALLS" && fail "known marketplace re-added"
grep -qxF 'plugin enable team@acme --scope user' "$CALLS" || fail "disabled plugin not enabled"

# A same-named marketplace from another source is reported, not replaced.
echo '[{"name": "acme", "source": "github", "installLocation": "/elsewhere"}]' >"$MARKETPLACES"
activate
grep -qF 'comes from /elsewhere' "$tmp/stderr" || fail "conflicting marketplace not reported"
grep -q 'plugin install\|plugin enable' "$CALLS" && fail "plugins changed despite conflict"

# Unexpected CLI output warns instead of aborting activation.
echo '{"not": "a list"}' >"$MARKETPLACES"
activate || fail "unexpected marketplace list aborted activation"
grep -qF 'unexpected claude plugin marketplace list output' "$tmp/stderr" || fail "unexpected output not reported"
printf '[{"name": "acme", "installLocation": "%s"}]\n' "$HOME/work/market" >"$MARKETPLACES"
echo '"nope"' >"$PLUGINS"
activate || fail "unexpected plugin list aborted activation"
grep -qF 'unexpected claude plugin list output' "$tmp/stderr" || fail "unexpected plugin list not reported"

# A manifest with the wrong shape warns.
cp "$HOME/work/market/.claude-plugin/marketplace.json" "$tmp/manifest"
echo '{"name": "acme"}' >"$HOME/work/market/.claude-plugin/marketplace.json"
activate || fail "malformed manifest aborted activation"
grep -qF 'has no plugins array' "$tmp/stderr" || fail "malformed manifest not reported"
echo '{"name": "acme", "plugins": ["team"]}' >"$HOME/work/market/.claude-plugin/marketplace.json"
activate || fail "string plugin entry aborted activation"
cp "$tmp/manifest" "$HOME/work/market/.claude-plugin/marketplace.json"

# CLI failures warn instead of aborting activation.
printf '#!/usr/bin/env bash\nexit 1\n' >"$CLAUDE"
activate || fail "claude failure aborted activation"
grep -qF 'claude plugin marketplace list failed' "$tmp/stderr" || fail "claude failure not reported"
echo ok
