#!/usr/bin/env python3
"""Check generated host configuration for pi and Claude Code agents."""

import json
from pathlib import Path
import sys

DISABLED_FEATURES = [
    "agent-management",
    "watchdog",
    "panes",
    "missions",
    "spawn-budget-grants",
    "preflight",
    "lane-metadata",
    "gates",
    "usage-budgets",
    "tool-budgets",
    "control-overrides",
    "extension-bindings",
    "external-machines",
]


def agent_definition(path):
    header, body = Path(path).read_text().split("---", 2)[1:]
    fields = {}
    for line in header.splitlines():
        line = line.strip()
        if not line:
            continue
        if line.startswith("- "):
            fields[key].append(line[2:])
        else:
            key, value = line.split(":", 1)
            fields[key] = value.strip() if value.strip() else []
    return fields, body


def main():
    fixtures = json.loads(Path(sys.argv[1]).read_text())
    runtime = json.loads(Path(sys.argv[2]).read_text())
    prompts = {
        path.stem: path.read_text().strip() for path in Path(sys.argv[3]).glob("*.md")
    }
    assert set(prompts) == {
        "scout",
        "reviewer",
        "worker",
        "researcher",
        "infra-reviewer",
    }
    assert "try to disprove it" in prompts["reviewer"]
    assert "concrete input or realistic sequence" in prompts["reviewer"]
    assert "personal preferences" in prompts["reviewer"]
    assert "existing Standards/Spec structure" in prompts["reviewer"]
    assert "not its file-writing steps" in prompts["researcher"]
    assert "Do not edit files, write research artifacts" in prompts["researcher"]
    assert "unchecked citations" in prompts["researcher"]
    assert "Terraform/OpenTofu" in prompts["infra-reviewer"]
    assert "Kubernetes/Helm/Kustomize/GitOps" in prompts["infra-reviewer"]
    assert "infra-review findings, severity, and output contract" in prompts["infra-reviewer"]
    assert "Do not edit files, deploy, apply changes" in prompts["infra-reviewer"]
    assert runtime == {
        "disabledFeatures": DISABLED_FEATURES,
        "scheduledRuns": {"enabled": False},
        "missions": {"enabled": False},
        "maxSubagentDepth": 1,
        "authorityPolicy": {
            "discardWorktree": "confirm",
            "destructiveCleanup": "confirm",
        },
    }

    for hostname, fixture in fixtures.items():
        settings = json.loads(Path(fixture["settings"]).read_text())
        provider = settings["defaultProvider"]
        assert settings["defaultThinkingLevel"] == "high", hostname
        assert provider == ("anthropic" if hostname == "work-macbook" else "openai"), (
            hostname
        )
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
        subagents_pkg = next(
            p
            for p in packages
            if isinstance(p, dict) and p["source"] == "npm:pi-subagents"
        )
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
            expected_subagents["agentOverrides"] = {
                "obsidian-second-brain.wiki-vault": vault
            }
        assert settings["subagents"] == expected_subagents, hostname

        assert str(Path(fixture["runtimeTarget"]).readlink()).endswith(
            "/config/pi/subagents.json"
        )
        assert not fixture["hasAppendSystem"], hostname

        # Only repository-owned agents; the vault agent comes from its package.
        agents = {
            Path(name).stem: agent_definition(path)
            for name, path in fixture["agents"].items()
        }
        assert set(agents) == set(prompts), hostname
        for name, (fields, body) in agents.items():
            assert fields["name"] == name, (hostname, name)
            assert fields["advertise"] == "true", (hostname, name)
            assert fields["async"] == "true", (hostname, name)
            assert fields["inheritProjectContext"] == "true", (hostname, name)
            assert fields["inheritGlobalContext"] == "true", (hostname, name)
            model_role = {"researcher": "worker", "infra-reviewer": "reviewer"}.get(
                name, name
            )
            assert fields["model"] == fixture["models"][model_role], (hostname, name)
            assert fields["thinking"] == ("low" if name == "scout" else "high"), (
                hostname,
                name,
            )
            tools = set(fields["tools"].split(", "))
            assert "subagent" not in tools, (hostname, name)
            if name != "worker":
                expected_tools = {"read", "bash", "grep", "find", "ls"}
                if name in {"researcher", "infra-reviewer"}:
                    expected_tools |= {
                        "web_enable",
                        "web_search",
                        "fetch_content",
                        "get_search_content",
                    }
                assert tools == expected_tools, (hostname, name)
                assert fields["acceptanceRole"] == "read-only", (hostname, name)
            else:
                assert {
                    "edit",
                    "write",
                    "web_enable",
                    "web_search",
                    "fetch_content",
                    "get_search_content",
                } <= tools
                assert fields["acceptanceRole"] == "writer", (hostname, name)
            # Skills are deliberately loaded by path, including explicit-only ones.
            assert "skills" not in fields, (hostname, name)
            if name == "reviewer":
                assert "For diff reviews only, read " in body, hostname
                assert "/.pi/agent/skills/code-review/SKILL.md" in body, hostname
                assert "**Diff review:**" in body, hostname
                assert "**Current-state audit:**" in body, hostname
                assert "No diff or fixed point is required." in body, hostname
                assert "current-state audits" in fields["description"], hostname
            for legacy in (
                "max_turns",
                "run_in_background",
                "prompt_mode",
                "inherit_context",
                "locked",
                "enabled",
            ):
                assert legacy not in fields, (hostname, name, legacy)
            assert prompts[name] in body, (hostname, name)
            if name == "researcher":
                assert "/.pi/agent/skills/research/SKILL.md" in body, hostname
            if name == "infra-reviewer":
                assert "/.pi/agent/skills/infra-review/SKILL.md" in body, hostname
                assert "/.pi/agent/skills/kubernetes-skill/SKILL.md" in body, hostname

        claude_agents = {
            Path(name).stem: agent_definition(path)
            for name, path in fixture["claudeAgents"].items()
        }
        assert set(claude_agents) == set(prompts), hostname
        for name, (fields, body) in claude_agents.items():
            assert fields["name"] == name, (hostname, name)
            assert prompts[name] in body, (hostname, name)
            tools = set(fields["tools"].split(", "))
            assert "Agent" not in tools, (hostname, name)
            if name != "worker":
                expected_tools = {"Read", "Grep", "Glob", "Bash"}
                if name in {"researcher", "infra-reviewer"}:
                    expected_tools |= {"WebSearch", "WebFetch"}
                assert tools == expected_tools, (hostname, name)
                assert fields["permissionMode"] == "plan", (hostname, name)
                assert fields["background"] == "true", (hostname, name)
            else:
                assert {"Read", "Edit", "Write", "Grep", "Glob", "Bash"} == tools
            assert fields["model"] == {"scout": "haiku", "worker": "opus"}.get(
                name, "sonnet"
            ), (hostname, name)
            assert fields["effort"] == ("low" if name == "scout" else "high")
            if name == "infra-reviewer":
                assert fields["skills"] == ["infra-review"], hostname
                assert "/.claude/skills/kubernetes-skill/SKILL.md" in body, hostname
            else:
                assert "skills" not in fields, (hostname, name)
            if name == "researcher":
                assert "/.claude/skills/research/SKILL.md" in body, hostname
            if name == "reviewer":
                assert "For diff reviews only, read " in body, hostname
                assert "/.claude/skills/code-review/SKILL.md" in body, hostname
        print(f"{hostname}: pi and Claude Code agent configuration passed")


if __name__ == "__main__":
    main()
