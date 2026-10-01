#!/usr/bin/env python3
"""Check native MCP configuration and permission-rule migration."""

import fnmatch
import json
import sys
from pathlib import Path

permissions, personal, work = (json.loads(Path(path).read_text()) for path in sys.argv[1:])
policy = permissions["permission"]

# Keep gateway protections while older hosts and sessions still use the adapter.
for pattern, action in policy["mcp"].items():
    assert policy[f"mcp__{pattern}"] == action, pattern


def native_permission(name):
    action = policy["*"]
    for pattern, value in policy.items():
        if pattern.startswith("mcp__") and fnmatch.fnmatchcase(name, pattern):
            action = value
    return action


for name, expected in {
    "mcp__github__search_repositories": "allow",
    "mcp__github__delete_file": "ask",
    "mcp__github__merge_pull_request": "ask",
    "mcp__github__create_or_update_file": "ask",
    "mcp__github__fork_repository": "ask",
    "mcp__notion__move_page": "ask",
    "mcp__notion__archive_page": "ask",
    "mcp__aws_mcp__terminate_instances": "ask",
    "mcp__datadog__list_monitors": "allow",
}.items():
    assert native_permission(name) == expected, name

assert policy["path"]["mcp-auth.json"] == "deny"
assert policy["path"]["*/mcp-auth.json"] == "deny"

assert set(personal["mcpServers"]) == {"github"}
assert set(work["mcpServers"]) == {
    "github", "aws-mcp", "aws-pricing-mcp-server", "aws-knowledge-mcp",
    "kubernetes", "notion", "datadog",
}
for config in (personal, work):
    assert set(config) == {"mcpServers"}
    for name, server in config["mcpServers"].items():
        assert ("command" in server) != ("url" in server), name
        assert server["exposure"] == "codemode", name
        assert server["timeout"] == 60, name
        assert isinstance(server["description"], str) and server["description"].strip(), name
    assert config["mcpServers"]["github"]["headers"]["Authorization"] == "Bearer ${GH_TOKEN}"

print("PASS: native MCP role configuration, selective confirmations, and OAuth path protection")
