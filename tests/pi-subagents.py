#!/usr/bin/env python3
"""Check generated host configuration for the pi-subagents adoption."""

import json
from pathlib import Path
import sys

ALL_FEATURES = [
    "agent-management",
    "watchdog",
    "panes",
    "missions",
    "lane-management",
    "spawn-budget-grants",
    "preflight",
    "lane-metadata",
    "gates",
    "usage-budgets",
    "tool-budgets",
    "control-overrides",
    "extension-bindings",
    "external-machines",
    "workflow-scripts",
]


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
        "disabledFeatures": ALL_FEATURES,
        "scheduledRuns": {"enabled": False},
        "missions": {"enabled": False},
        "maxSubagentDepth": 1,
    }
    assert "standing authorization to delegate" in instructions
    assert "Do not ask permission merely to delegate" in instructions
    assert "Parallel workers are allowed when their owned files do not overlap" in instructions
    assert "one writer at a time per file, including the parent" in instructions
    assert "Before launching writers, assign each an explicit set of owned files" in instructions
    assert "Commands that write files" in instructions
    assert "Never expand ownership without coordinating with the parent" in instructions
    for tool in ("subagents_enable", "contact_supervisor", "subagent_supervisor"):
        assert tool in instructions, tool
    for legacy in ("gotgenes", "get_subagent_result", "steer_subagent", "ask_parent", "subagent_type"):
        assert legacy not in instructions, legacy

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
        assert "observational-memory" not in settings, hostname

        packages = settings["packages"]
        sources = [p if isinstance(p, str) else p["source"] for p in packages]
        assert "npm:pi-subagents" in sources, hostname
        assert not any("gotgenes/pi-subagents" in s for s in sources), hostname
        assert "npm:pi-observational-memory" not in sources, hostname
        subagents_pkg = next(p for p in packages if isinstance(p, dict) and p["source"] == "npm:pi-subagents")
        assert subagents_pkg == {
            "source": "npm:pi-subagents",
            "extensions": ["index.js"],
            "skills": ["skills/pi-subagents/SKILL.md"],
            "prompts": [],
        }, hostname
        assert "npm:@gotgenes/pi-permission-system" in sources, hostname
        assert "npm:@gotgenes/pi-anthropic-auth" in sources, hostname
        assert "npm:pi-web-access" in sources, hostname
        assert ("npm:@soulwaxx/obsidian-second-brain" in sources) == fixture["darwin"]

        expected_subagents = {"disableBuiltins": True}
        if fixture["darwin"]:
            vault = {"inheritGlobalContext": True}
            if fixture["vaultModel"] is not None:
                vault["model"] = fixture["vaultModel"]
            expected_subagents["agentOverrides"] = {"obsidian-second-brain.wiki-vault": vault}
        assert settings["subagents"] == expected_subagents, hostname

        assert str(Path(fixture["runtimeTarget"]).readlink()).endswith("/config/pi/subagents.json")
        assert str(Path(fixture["instructionsTarget"]).readlink()).endswith("/config/pi/subagents.md")

        # Only repository-owned agents; the vault agent comes from its package.
        agents = {
            Path(name).stem: agent_definition(path)
            for name, path in fixture["agents"].items()
        }
        assert set(agents) == {"scout", "reviewer", "worker"}, hostname
        for name, (fields, body) in agents.items():
            assert fields["name"] == name, (hostname, name)
            assert fields["advertise"] == "true", (hostname, name)
            assert fields["async"] == "true", (hostname, name)
            assert fields["inheritProjectContext"] == "true", (hostname, name)
            assert fields["inheritGlobalContext"] == "true", (hostname, name)
            assert fields["model"] == fixture["models"][name], (hostname, name)
            assert fields["thinking"] == ("low" if name == "scout" else "high"), (hostname, name)
            tools = set(fields["tools"].split(", "))
            assert "subagent" not in tools, (hostname, name)
            if name in {"scout", "reviewer"}:
                assert tools == {"read", "bash", "grep", "find", "ls"}, (hostname, name)
                assert fields["acceptanceRole"] == "read-only", (hostname, name)
            else:
                assert {"edit", "write", "web_enable", "web_search", "fetch_content", "get_search_content"} <= tools
                assert fields["acceptanceRole"] == "writer", (hostname, name)
            # Explicit-only skills are never injected into children; the
            # reviewer must read its contract by path.
            assert "skills" not in fields, (hostname, name)
            if name == "reviewer":
                assert "/.pi/agent/skills/code-review/SKILL.md" in body, hostname
            for legacy in ("max_turns", "run_in_background", "prompt_mode", "inherit_context", "locked", "enabled"):
                assert legacy not in fields, (hostname, name, legacy)
            assert body.strip(), (hostname, name)
        print(f"{hostname}: pi-subagents configuration passed")


if __name__ == "__main__":
    main()
