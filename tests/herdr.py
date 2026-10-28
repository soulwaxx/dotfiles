#!/usr/bin/env python3
"""Behavior tests for the generated Herd plugin activation snippet."""

import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path


FIXTURE = Path(sys.argv[1])
BASH = sys.argv[2]


def plugin(plugin_id, repo, ref, enabled=True, subdir="", manifest_path=""):
    owner, name = repo.split("/", 1)
    return {
        "plugin_id": plugin_id,
        "enabled": enabled,
        "source": {
            "kind": "github",
            "owner": owner,
            "repo": name,
            "subdir": subdir,
            "requested_ref": ref,
        },
        "manifest_path": manifest_path,
    }


def run_case(
    fixture, initial=(), releases=None, *, curl_failure=False, invalid_redirect=False, install_failure=False
):
    with tempfile.TemporaryDirectory(prefix="herdr-test-") as tmp:
        root = Path(tmp)
        home = root / "home"
        home.mkdir()
        (home / ".claude").mkdir()
        (home / ".local/state/dotfiles").mkdir(parents=True)
        settings = home / ".claude/settings.json"
        settings.write_text('{"integrations":{"keep":true}}\n')

        manifest = root / "heeler.toml"
        manifest.write_text('command = ["/old/node", "src/main.js"]\n')
        state = root / "plugins.json"
        plugins = []
        for item in initial:
            item = dict(item)
            if item["plugin_id"] == "heeler":
                item["manifest_path"] = str(manifest)
            plugins.append(item)
        state.write_text(json.dumps(plugins))
        log = root / "calls.jsonl"
        release_data = releases or {
            "thanhdat77/herdr-navigator": {"tag_name": "v9.8.7"},
            "ZingerLittleBee/Heeler": {"tag_name": "v2.3.4"},
        }

        bindir = root / "bin"
        bindir.mkdir()
        curl = bindir / "curl"
        curl.write_text(
            f"#!{sys.executable}\n"
            "import json, os, sys\n"
            "args=sys.argv[1:]\n"
            "url=args[-1]\n"
            "repo=url.split('https://github.com/',1)[1].split('/releases/latest',1)[0]\n"
            "open(os.environ['HERDR_LOG'],'a').write(json.dumps(['curl',repo])+'\\n')\n"
            "if os.environ.get('CURL_FAILURE') == '1': sys.exit(22)\n"
            "if os.environ.get('INVALID_REDIRECT') == '1': print(f'https://github.com/{repo}/releases', end=''); sys.exit(0)\n"
            "tag=json.loads(os.environ['RELEASES']).get(repo, {'tag_name':'v1'})['tag_name']\n"
            "print(f'https://github.com/{repo}/releases/tag/{tag}', end='')\n"
        )
        herdr = bindir / "herdr"
        herdr.write_text(
            f"#!{sys.executable}\n"
            "import json, os, sys\n"
            "a=sys.argv[1:]\n"
            "p=os.environ['PLUGINS']; items=json.load(open(p))\n"
            "def log(v): open(os.environ['HERDR_LOG'],'a').write(json.dumps(v)+'\\n')\n"
            "if a[:2] == ['plugin','list']:\n"
            " plugin=a[a.index('--plugin')+1]\n"
            " log(['list',plugin])\n"
            " print(json.dumps({'result':{'plugins':[x for x in items if x['plugin_id']==plugin]}}))\n"
            "elif a[:2] == ['plugin','install']:\n"
            " log(['install']+a[2:])\n"
            " if os.environ.get('INSTALL_FAILURE')=='1': sys.exit(1)\n"
            " url=a[2]; ref=a[a.index('--ref')+1]; parts=url.split('/')\n"
            " repo='/'.join(parts[:2]); subdir='/'.join(parts[2:])\n"
            " owner,name=repo.split('/',1); pid='heeler' if 'Heeler' in repo else 'herdr-navigator'\n"
            " item={'plugin_id':pid,'enabled':True,'source':{'kind':'github','owner':owner,'repo':name,'subdir':subdir,'requested_ref':ref},'manifest_path':os.environ['MANIFEST']}\n"
            " items=[x for x in items if x['plugin_id']!=pid]+[item]; json.dump(items,open(p,'w'))\n"
            "elif a[:2] == ['integration','install']:\n log(a)\n"
            "else: log(['unexpected']+a); sys.exit(2)\n"
        )
        for executable in (curl, herdr):
            executable.chmod(0o755)

        script = fixture["script"]
        script = re.sub(r"/nix/store/[^ '\"$]+/bin/(?:curl|jq|sed|install)", lambda m: m.group(0).rsplit("/", 1)[1], script)
        script = re.sub(r"/nix/store/[^ '\"$]+/bin/herdr", str(herdr), script)
        script = script.replace("/opt/homebrew/bin/herdr", str(herdr))
        script = script.replace("/opt/homebrew/opt/node@24/bin/node", "/runtime/node")
        script = script.replace("${pkgs.nodejs_24}/bin/node", "/runtime/node")
        script = re.sub(r"/nix/store/[^ '\"]+/bin/node", "/runtime/node", script)
        script_file = root / "activation.sh"
        script_file.write_text("set -euo pipefail\nrun() { \"$@\"; }\n" + script + "\n")

        env = os.environ.copy()
        env.update({
            "HOME": str(home),
            "PATH": str(bindir) + os.pathsep + env["PATH"],
            "HERDR_LOG": str(log),
            "PLUGINS": str(state),
            "MANIFEST": str(manifest),
            "RELEASES": json.dumps(release_data),
            "CURL_FAILURE": "1" if curl_failure else "0",
            "INVALID_REDIRECT": "1" if invalid_redirect else "0",
            "INSTALL_FAILURE": "1" if install_failure else "0",
        })
        result = subprocess.run([BASH, str(script_file)], env=env, text=True, capture_output=True)
        calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
        return (
            result,
            calls,
            json.loads(state.read_text()),
            manifest.read_text(),
            (home / ".local/state/dotfiles/claude-settings.last.json").read_text()
            if (home / ".local/state/dotfiles/claude-settings.last.json").exists()
            else None,
        )


def expect(condition, message):
    if not condition:
        raise AssertionError(message)


def run_host(host, fixture):
    expect("script" in fixture and "heeler" in fixture, f"{host}: missing script/heeler")
    nav_repo = "thanhdat77/herdr-navigator"
    heel_repo = "ZingerLittleBee/Heeler"
    nav = lambda ref, **kw: plugin("herdr-navigator", nav_repo, ref, **kw)
    heel = lambda ref, **kw: plugin("heeler", heel_repo, ref, subdir="plugin", **kw)

    result, calls, _, manifest_text, _ = run_case(fixture)
    expect(result.returncode == 0, f"{host}: initial activation failed: {result.stderr}")
    installs = [c for c in calls if c[0] == "install"]
    expect(any(nav_repo in c and "v9.8.7" in c for c in installs), "latest navigator tag was not installed")
    expect(all("1.0.0" not in str(c) for c in installs), "plugin manifest version used instead of release tag")
    expect(any(c[:2] == ["integration", "install"] for c in calls), "integrations not installed")
    if fixture["heeler"]:
        expect(any(any(heel_repo in arg for arg in c) and "v2.3.4" in c for c in installs), "Heeler missing on enabled host")
        expect('/runtime/node' in manifest_text, "Heeler Node path not adjusted")
    else:
        expect(not any(any(heel_repo in arg for arg in c) for c in installs), "Heeler installed on disabled host")

    current = [nav("v9.8.7")]
    if fixture["heeler"]:
        current.append(heel("v2.3.4"))
    result, calls, _, manifest_text, _ = run_case(fixture, current)
    expect(result.returncode == 0, "repeat activation failed")
    expect(not any(c[0] == "install" for c in calls), "current release was reinstalled")
    if fixture["heeler"]:
        expect('/runtime/node' in manifest_text, "repeat activation did not adjust Heeler Node path")

    result, calls, _, _, _ = run_case(fixture, [nav("old-pin"), *( [heel("old-pin")] if fixture["heeler"] else [])])
    expect(result.returncode == 0 and any(c[0] == "install" for c in calls), "pinned plugin refs did not migrate")
    result, calls, _, _, _ = run_case(fixture, [nav("v9.8.7", enabled=False)])
    expect(result.returncode == 0 and any(c[0] == "install" for c in calls), "disabled current plugin was not reinstalled")
    result, calls, _, _, _ = run_case(fixture, [plugin("herdr-navigator", nav_repo, "v9.8.7", subdir="wrong")])
    expect(result.returncode == 0 and any(c[0] == "install" for c in calls), "source subdirectory mismatch was ignored")
    result, calls, _, _, _ = run_case(fixture, [nav("v9.8.7")], releases={nav_repo: {"tag_name": "v9.8.8"}})
    expect(result.returncode == 0 and any("v9.8.8" in c for c in calls if c[0] == "install"), "changed release was not installed")
    if fixture["heeler"]:
        result, calls, _, manifest_text, _ = run_case(fixture, [nav("v9.8.7"), heel("v2.3.4")], releases={nav_repo: {"tag_name": "v9.8.7"}, heel_repo: {"tag_name": "v2.3.5"}})
        expect(result.returncode == 0 and '/runtime/node' in manifest_text, "Heeler Node path not adjusted after reinstall")

    for kwargs in ({"curl_failure": True}, {"invalid_redirect": True}, {"releases": {nav_repo: {"tag_name": ""}}}, {"install_failure": True}):
        result, calls, _, _, _ = run_case(fixture, **kwargs)
        expect(result.returncode != 0, "failure did not fail activation")
        expect(not any(c[:1] == ["integration"] for c in calls), "integration ran after plugin failure")

    result, calls, _, _, backup = run_case(fixture)
    expect(backup == '{"integrations":{"keep":true}}\n', "settings backup missing or integrations were not preserved")
    expect(not any("upgrade" in str(c) or "brew" in str(c) for c in calls), "Herd self-updater or brew invoked")
    print(f"herdr activation behavior passed ({host})")


def main():
    fixtures = json.loads(FIXTURE.read_text())
    expect(fixtures, "fixture must contain at least one host")
    for host, fixture in fixtures.items():
        run_host(host, fixture)


if __name__ == "__main__":
    main()
