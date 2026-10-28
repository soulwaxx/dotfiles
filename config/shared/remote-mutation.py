#!/usr/bin/env python3
"""Best-effort recognition of a finite set of remote mutations.

This is not a security boundary. Unsupported tools, malformed inputs, shell
wrappers, and ambiguous commands return "unknown" without adding a prompt.
Input is one JSON object on stdin; tool arguments are never accepted via argv.
"""

import json
import re
import shlex
import sys


MUTATION = "mutation"
READ = "read"
UNKNOWN = "unknown"


def _mcp(tool_name, args, server=None):
    if not isinstance(tool_name, str) or not isinstance(args, dict):
        return UNKNOWN
    normalized = tool_name.replace("-", "_")
    parts = normalized.split("__")
    if len(parts) == 3 and parts[0] == "mcp":
        _, tool_server, name = parts
    else:
        parts = normalized.split("_")
        if len(parts) < 3 or parts[0] != "mcp" or parts[1] not in {"github", "kubernetes"}:
            return UNKNOWN
        tool_server = parts[1]
        name = "_".join(parts[2:])
    if tool_server not in {"github", "kubernetes"}:
        return UNKNOWN
    if server is not None:
        if isinstance(server, dict):
            server = server.get("name")
        if not isinstance(server, str):
            return UNKNOWN
        if server.replace("-mcp-server", "").replace("-", "_") != tool_server:
            return UNKNOWN
    if tool_server == "kubernetes" and name not in {
        "resources_create_or_update", "pods_run", "resources_scale", "pods_exec"
    }:
        return UNKNOWN
    if tool_server == "github" and name not in {
        "create_pull_request", "create_branch", "pull_request_review_write", "issue_write", "issue_read"
    }:
        return UNKNOWN

    if name == "resources_create_or_update":
        return MUTATION if isinstance(args.get("resource"), str) else UNKNOWN
    if name == "pods_run":
        return MUTATION
    if name == "resources_scale":
        if "scale" not in args:
            return READ
        scale = args["scale"]
        return MUTATION if type(scale) is int else UNKNOWN
    if name == "pods_exec":
        command = args.get("command")
        if not isinstance(command, list) or not command or not all(
            isinstance(part, str) for part in command
        ):
            return UNKNOWN
        executable = command[0].rsplit("/", 1)[-1]
        if executable in {"rm", "mv", "cp", "mkdir", "rmdir", "touch", "chmod", "chown", "truncate"}:
            return MUTATION
        if executable == "find":
            if any(part in {"-delete", "-delete=true"} for part in command[1:]):
                return MUTATION
            if any(part in {"-exec", "-execdir", "-ok", "-okdir"} for part in command[1:]):
                return UNKNOWN
            return READ
        if executable in {"cat", "ls", "pwd", "head", "tail", "grep", "stat", "wc"}:
            return READ
        return UNKNOWN
    if name in {"create_pull_request", "create_branch", "issue_write", "pull_request_review_write"}:
        if name == "pull_request_review_write":
            action = args.get("method")
            return MUTATION if action in {"create", "submit_pending", "delete_pending", "resolve_thread", "unresolve_thread"} else UNKNOWN
        return MUTATION
    if name == "issue_read":
        return READ
    return UNKNOWN


_OPTION_VALUES = {
    "--profile", "--region", "--endpoint-url", "--context", "--namespace",
    "-n", "--cluster", "--user", "--kubeconfig", "--request-timeout",
    "--field-manager", "--output", "-o", "--timeout", "--values", "-f",
    "--set", "--set-string", "--set-file", "--namespace", "-n",
}


def _skip_options(tokens, index):
    while index < len(tokens) and tokens[index].startswith("-"):
        option = tokens[index]
        if "=" in option:
            index += 1
        elif option in _OPTION_VALUES:
            if index + 1 >= len(tokens):
                return None
            index += 2
        else:
            # A finite set of options known to take no argument.
            if option not in {"--all-namespaces", "-A", "--recursive", "-r", "--wait", "--dry-run", "--force", "--yes", "-y", "--refresh", "-input", "-auto-approve", "-lock", "-lock=false"}:
                return None
            index += 1
    return index


def _s3_operands(tokens):
    value_options = {
        "--profile", "--region", "--endpoint-url", "--acl", "--cache-control",
        "--content-disposition", "--content-encoding", "--content-language",
        "--content-type", "--expires", "--grants", "--metadata", "--metadata-directive",
        "--sse", "--sse-c", "--sse-c-key", "--sse-kms-key-id", "--storage-class",
        "--website-redirect", "--exclude", "--include", "--expected-size",
    }
    flags = {
        "--recursive", "--dryrun", "--only-show-errors", "--no-guess-mime-type",
        "--guess-mime-type", "--no-progress", "--follow-symlinks", "--no-follow-symlinks",
        "--delete", "--copy-props", "--no-verify-ssl", "--request-payer",
    }
    operands = []
    index = 0
    while index < len(tokens):
        token = tokens[index]
        if not token.startswith("-"):
            operands.append(token)
            index += 1
        elif "=" in token:
            index += 1
        elif token in value_options:
            if index + 1 >= len(tokens):
                return None
            index += 2
        elif token in flags:
            index += 1
        else:
            return None
    return operands


def _aws(tokens):
    index = _skip_options(tokens, 1)
    if index is None or index + 1 >= len(tokens):
        return UNKNOWN
    service, operation = tokens[index:index + 2]
    if service == "ec2" and operation == "run-instances":
        return MUTATION
    if service == "ec2" and operation.startswith("describe-"):
        return READ
    if service == "s3" and operation in {"ls", "presign"}:
        return READ
    if service == "s3" and operation in {"cp", "mv", "sync", "rm"}:
        params = _s3_operands(tokens[index + 2:])
        if params is None:
            return UNKNOWN
        if operation == "rm":
            return MUTATION if params and params[0].startswith("s3://") else UNKNOWN
        if len(params) < 2:
            return UNKNOWN
        source, destination = params[:2]
        src_remote, dst_remote = source.startswith("s3://"), destination.startswith("s3://")
        if operation == "cp":
            return MUTATION if dst_remote else READ if src_remote else UNKNOWN
        if operation == "mv":
            return MUTATION if src_remote or dst_remote else UNKNOWN
        return MUTATION if dst_remote else READ if src_remote else UNKNOWN
    return UNKNOWN


def _kubectl(tokens):
    index = _skip_options(tokens, 1)
    if index is None or index >= len(tokens):
        return UNKNOWN
    verb = tokens[index]
    if verb in {"apply", "create", "patch", "scale", "set"}:
        return MUTATION
    if verb == "rollout" and index + 1 < len(tokens):
        action = tokens[index + 1]
        if action in {"restart", "undo"}:
            return MUTATION
        if action in {"status", "history"}:
            return READ
    if verb in {"get", "describe", "logs", "explain", "api-resources", "version"}:
        return READ
    if verb == "config" and index + 1 < len(tokens) and tokens[index + 1] in {"get-contexts", "current-context", "view"}:
        return READ
    return UNKNOWN


def _helm(tokens):
    index = _skip_options(tokens, 1)
    if index is None or index >= len(tokens):
        return UNKNOWN
    verb = tokens[index]
    if verb in {"install", "upgrade", "rollback", "uninstall"}:
        return MUTATION
    if verb in {"list", "status", "get", "history", "show", "search"}:
        return READ
    if verb == "repo" and index + 1 < len(tokens) and tokens[index + 1] in {"list", "update"}:
        return READ
    return UNKNOWN


def _terraform(tokens):
    index = 1
    while index < len(tokens) and tokens[index].startswith("-"):
        option = tokens[index]
        if option in {"-chdir", "-var", "-var-file", "-out", "-state", "-state-out", "-backup"}:
            if index + 1 >= len(tokens):
                return UNKNOWN
            index += 2
        else:
            index += 1
    if index >= len(tokens):
        return UNKNOWN
    verb = tokens[index]
    if verb in {"apply", "destroy", "import"}:
        return MUTATION
    if verb == "state" and index + 1 < len(tokens):
        action = tokens[index + 1]
        if action in {"mv", "rm", "push", "replace-provider"}:
            return MUTATION
        if action in {"list", "show", "pull"}:
            return READ
    if verb in {"show", "plan", "output", "providers", "version", "validate"}:
        return READ
    return UNKNOWN


def _command(tokens):
    if not tokens:
        return UNKNOWN
    basename = tokens[0].rsplit("/", 1)[-1]
    if basename == "aws":
        return _aws(tokens)
    if basename == "kubectl":
        return _kubectl(tokens)
    if basename == "helm":
        return _helm(tokens)
    if basename in {"terraform", "tofu"}:
        return _terraform(tokens)
    if basename == "echo":
        return READ
    return UNKNOWN


def classify_cli(command):
    if not isinstance(command, str) or not command.strip():
        return UNKNOWN
    try:
        if "\n" in command or "\r" in command:
            return UNKNOWN
        if re.search(r"(?<!\\s)['\"]|(?:'[^']*'|\"[^\"]*\")(?=\\S)", command):
            return UNKNOWN
        lexer = shlex.shlex(command, posix=False, punctuation_chars=";&|<>`$()")
        lexer.whitespace_split = True
        raw_tokens = list(lexer)
        tokens = []
        for token in raw_tokens:
            if token[:1] in {"'", '\"'}:
                if "$(`" in token or "$(" in token or "`" in token:
                    return UNKNOWN
                try:
                    parsed = shlex.split(token)
                except ValueError:
                    return UNKNOWN
                tokens.extend((part, True) for part in parsed)
            else:
                tokens.append((token, False))
    except ValueError:
        return UNKNOWN
    # Only simple semicolon-separated commands are recognized. Reject other
    # shell operators, substitutions, redirections, and pipelines.
    if any(not quoted and token != ";" and any(char in token for char in ";&|<>`$()") for token, quoted in tokens):
        return UNKNOWN
    segments, current = [], []
    for token, quoted in tokens:
        if token == ";" and not quoted:
            if current:
                segments.append(current)
                current = []
        else:
            current.append(token)
    if current:
        segments.append(current)
    if not segments:
        return UNKNOWN
    results = [_command(segment) for segment in segments]
    if MUTATION in results:
        return MUTATION
    return READ if all(result == READ for result in results) else UNKNOWN


def classify(payload):
    if not isinstance(payload, dict):
        return UNKNOWN
    tool_name = payload.get("tool_name")
    tool_input = payload.get("tool_input", {})
    if tool_name in {"Bash", "bash"}:
        return classify_cli(tool_input.get("command")) if isinstance(tool_input, dict) else UNKNOWN
    return _mcp(tool_name, tool_input, payload.get("mcp_server"))


def main():
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, UnicodeDecodeError) as error:
        print(f"invalid JSON input: {error}", file=sys.stderr)
        return 2
    print(json.dumps({"classification": classify(payload)}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
