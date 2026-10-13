#!/usr/bin/env python3
"""Check generated host configuration for the gotgenes subagent migration."""

import json
from pathlib import Path
import sys


def agent_definition(path):
    header, body = Path(path).read_text().split("---", 2)[1:]
    fields = {}
    for line in header.splitlines():
        if line.strip():
            key, value = line.split(":", 1)
            fields[key.strip()] = value.strip()
    return fields, body


def main():
    fixtures = json.loads(Path(sys.argv[1]).read_text())
    runtime = json.loads(Path(sys.argv[2]).read_text())
    instructions = Path(sys.argv[3]).read_text()
    assert runtime == {
        "maxConcurrent": 4,
        "defaultMaxTurns": 0,
        "wrapUpTurns": 2,
        "consumedSessionRetentionMinutes": 10,
        "unconsumedSessionRetentionMinutes": 720,
        "abortAllOnInterrupt": True,
        "midRunUpdates": True,
        "excludedExtensionPackages": [
            "npm:@juicesharp/rpiv-todo",
            "npm:@juicesharp/rpiv-ask-user-question",
            "npm:pi-powerline-footer",
            "npm:pi-observational-memory",
        ],
    }
    assert "standing authorization to delegate" in instructions
    assert "Do not ask permission merely to delegate" in instructions
    assert "only when the user or applicable project instructions authorize delegation" not in instructions
    assert "Parallel workers are allowed when their owned files do not overlap" in instructions
    assert "one writer at a time per file, including the parent" in instructions
    assert "Before launching writers, assign each an explicit set of owned files" in instructions
    assert "Commands that write files" in instructions
    assert "Never expand ownership without coordinating with the parent" in instructions
    assert "allow only one writer at a time, including the parent" not in instructions
    assert "get_subagent_result" in instructions

    for hostname, fixture in fixtures.items():
        settings = json.loads(Path(fixture["settings"]).read_text())
        provider = settings["defaultProvider"]
        assert provider == ("anthropic" if hostname == "work-macbook" else "openai"), hostname
        context_window, target = {
            "anthropic": (1_000_000, 300_000),
            "openai": (272_000, 220_000),
        }[provider]
        assert settings["compaction"] == {
            "enabled": True,
            "reserveTokens": 16_384,
            "keepRecentTokens": 20_000,
            "modelOverrides": {
                "anthropic/claude-opus-5-5": {"reserveTokens": 700_000},
                "openai/gpt-6.1-sol": {"reserveTokens": 52_000},
            },
        }, hostname
        model_key = f"{provider}/{settings['defaultModel']}"
        reserve = settings["compaction"]["modelOverrides"][model_key]["reserveTokens"]
        assert context_window - reserve == target, hostname
        memory = settings["observational-memory"]
        assert memory["compactAfterTokensMode"] == "calibrated", hostname
        assert memory["compactAfterTokens"] == context_window, hostname
        assert memory.get("passive", False) is False, hostname
        sources = [p if isinstance(p, str) else p["source"] for p in settings["packages"]]
        assert "npm:@gotgenes/pi-subagents" in sources, hostname
        assert "npm:pi-subagents" not in sources, hostname
        assert "npm:@gotgenes/pi-permission-system" in sources, hostname
        assert "npm:@gotgenes/pi-anthropic-auth" in sources, hostname
        assert "npm:pi-web-access" in sources, hostname
        assert ("npm:@soulwaxx/obsidian-second-brain" in sources) == fixture["darwin"]
        assert "subagents" not in settings, hostname
        assert str(Path(fixture["runtimeTarget"]).readlink()).endswith("/config/pi/subagents.json")
        assert str(Path(fixture["instructionsTarget"]).readlink()).endswith("/config/pi/subagents.md")

        agents = {
            Path(name).stem: agent_definition(path)
            for name, path in fixture["agents"].items()
        }
        for name in ("Explore", "Plan", "general-purpose"):
            assert agents[name][0]["enabled"] == "false", (hostname, name)

        expected_roles = {"scout", "reviewer", "worker"}
        if fixture["darwin"]:
            expected_roles.add("obsidian-second-brain.wiki-vault")
        assert set(agents) == expected_roles | {"Explore", "Plan", "general-purpose"}
        for name in expected_roles:
            fields, body = agents[name]
            assert fields["run_in_background"] == "true", (hostname, name)
            assert fields["inherit_context"] == "false", (hostname, name)
            assert fields["max_turns"] == "0", (hostname, name)
            assert fields["prompt_mode"] == "replace", (hostname, name)
            assert set(fields["locked"].split(", ")) == {
                "model", "thinking", "max_turns", "inherit_context"
            }
            tools = set(fields["tools"].split(", "))
            assert not tools & {"subagent", "contact_supervisor", "watchdog_diff"}
            if name in {"scout", "reviewer"}:
                assert tools == {"read", "bash", "grep", "find", "ls"}
            else:
                assert {"web_enable", "web_search", "fetch_content", "get_search_content"} <= tools
            if name in fixture["models"]:
                assert fields["model"] == fixture["models"][name], (hostname, name)
                assert fields["thinking"] == ("low" if name == "scout" else "high")
            if name == "reviewer":
                assert "/skills/code-review/SKILL.md" in body
            if name == "obsidian-second-brain.wiki-vault":
                assert fields.get("model") == fixture["vaultModel"]
                assert "/agents/pi/wiki-vault.md" in body
                assert "/skills/wiki/SKILL.md" in body
                assert "stop and report the blocker" in body
        print(f"{hostname}: gotgenes subagent configuration passed")


if __name__ == "__main__":
    main()
