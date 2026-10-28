#!/usr/bin/env python3
"""Focused tests for the finite, best-effort remote mutation classifier."""

import importlib.util
import json
import pathlib
import subprocess
import sys
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
HELPER = ROOT / "config/shared/remote-mutation.py"
spec = importlib.util.spec_from_file_location("remote_mutation", HELPER)
remote_mutation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(remote_mutation)


class ClassifierTests(unittest.TestCase):
    def test_mcp_cases(self):
        cases = [
            ({"tool_name": "mcp__kubernetes__resources_create_or_update", "tool_input": {"resource": "apiVersion: v1\\nkind: Pod"}}, "mutation"),
            ({"tool_name": "mcp__kubernetes__pods_run", "tool_input": {}, "mcp_server": {"name": "kubernetes", "source": "local"}}, "mutation"),
            ({"tool_name": "resources_create_or_update", "tool_input": {"resource": "{}"}}, "unknown"),
            ({"tool_name": "mcp__other__resources_scale", "tool_input": {"scale": 0}}, "unknown"),
            ({"tool_name": "mcp__kubernetes__resources_scale", "mcp_server": {"name": "github", "source": "local"}, "tool_input": {"scale": 0}}, "unknown"),
            ({"tool_name": "mcp__github__resources_scale", "tool_input": {"scale": 0}}, "unknown"),
            ({"tool_name": "mcp__kubernetes__create_branch", "tool_input": {}}, "unknown"),
            ({"tool_name": "mcp__kubernetes__resources_scale", "tool_input": {"name": "pod"}}, "read"),
            ({"tool_name": "mcp__kubernetes__resources_scale", "tool_input": {"scale": 0}}, "mutation"),
            ({"tool_name": "mcp__kubernetes__resources_scale", "tool_input": {"scale": False}}, "unknown"),
            ({"tool_name": "mcp__kubernetes__resources_scale", "tool_input": {"scale": "2"}}, "unknown"),
            ({"tool_name": "mcp__kubernetes__resources_create_or_update", "tool_input": {}}, "unknown"),
            ({"tool_name": "mcp__kubernetes__pods_exec", "tool_input": {"command": ["rm", "-rf", "/tmp/x"]}}, "mutation"),
            ({"tool_name": "mcp__kubernetes__pods_exec", "tool_input": {"command": ["cat", "/tmp/x"]}}, "read"),
            ({"tool_name": "mcp__kubernetes__pods_exec", "tool_input": {"command": ["find", "/tmp", "-delete"]}}, "mutation"),
            ({"tool_name": "mcp__kubernetes__pods_exec", "tool_input": {"command": ["find", "/tmp", "-exec", "rm", "{}", ";"]}}, "unknown"),
            ({"tool_name": "mcp__kubernetes__pods_exec", "tool_input": {"command": ["sh", "-c", "rm /tmp/x"]}}, "unknown"),
            ({"tool_name": "mcp__kubernetes__pods_exec", "tool_input": {"command": "rm /tmp/x"}}, "unknown"),
            ({"tool_name": "mcp__github__create_pull_request", "tool_input": {}}, "mutation"),
            ({"tool_name": "mcp_github_issue_write", "tool_input": {}}, "mutation"),
            ({"tool_name": "mcp__github__pull_request_review_write", "tool_input": {"method": "resolve_thread"}}, "mutation"),
            ({"tool_name": "mcp__github__pull_request_review_write", "tool_input": {"method": "unknown"}}, "unknown"),
            ({"tool_name": "mcp__github__issue_read", "tool_input": {}}, "read"),
            ({"tool_name": "unknown__write", "tool_input": {}}, "unknown"),
            ({"tool_name": "aws___run_script", "tool_input": {}}, "unknown"),
        ]
        for payload, expected in cases:
            with self.subTest(payload=payload):
                self.assertEqual(remote_mutation.classify(payload), expected)

    def test_cli_cases(self):
        cases = [
            ("aws --profile prod ec2 run-instances --image-id ami-x", "mutation"),
            ("aws s3 cp ./file s3://bucket/file", "mutation"),
            ("aws s3 cp s3://bucket/file ./file", "read"),
            ("aws s3 cp s3://a/x --profile prod s3://b/x", "mutation"),
            ("aws s3 cp s3://a/x --profile prod ./x", "read"),
            ("aws s3 cp ./x --unknown-option v s3://b/x", "unknown"),
            ("aws s3 sync s3://bucket ./backup", "read"),
            ("aws s3 sync ./backup s3://bucket", "mutation"),
            ("aws s3 mv s3://bucket/a ./a", "mutation"),
            ("aws s3 rm s3://bucket/a", "mutation"),
            ("kubectl --context prod apply -f x.yaml", "mutation"),
            ("kubectl get pods", "read"),
            ("kubectl rollout restart deployment/web", "mutation"),
            ("kubectl rollout undo deployment/web", "mutation"),
            ("kubectl rollout surprise deployment/web", "unknown"),
            ("helm upgrade web chart", "mutation"),
            ("helm status web", "read"),
            ("helm repo add test https://example.invalid", "unknown"),
            ("terraform -chdir=infra apply", "mutation"),
            ("terraform push", "unknown"),
            ("terraform plan", "read"),
            ("tofu state rm x", "mutation"),
            ("terraform state replace-provider a b", "mutation"),
            ("terraform state mysterious", "unknown"),
            ("kubectl config set-context x", "unknown"),
            ("aws s3 ls; kubectl get pods", "read"),
            ("kubectl get pods; helm uninstall web", "mutation"),
            ("echo 'kubectl delete pods'", "read"),
            ("echo ';' kubectl apply -f x", "read"),
            ("echo 'x'apply", "unknown"),
            ('echo "$(kubectl apply -f x)"', "unknown"),
            ("echo ';'; kubectl get pods", "read"),
            ("kubectl get pods\nkubectl apply -f x", "unknown"),
            ("sudo kubectl delete pods", "unknown"),
            ("kubectl delete pods | cat", "unknown"),
            ("kubectl delete pods && echo done", "unknown"),
            ("python -c 'import os; os.remove(\"x\")'", "unknown"),
            ("kubectl", "unknown"),
        ]
        for command, expected in cases:
            with self.subTest(command=command):
                self.assertEqual(remote_mutation.classify_cli(command), expected)

    def test_stdin_api_and_malformed_input(self):
        payload = {"tool_name": "mcp__kubernetes__resources_scale", "tool_input": {"scale": 0}}
        result = subprocess.run(
            [sys.executable, str(HELPER)],
            input=json.dumps(payload),
            text=True,
            capture_output=True,
            check=True,
        )
        self.assertEqual(json.loads(result.stdout), {"classification": "mutation"})
        bash_payload = {"tool_name": "bash", "tool_input": {"command": "kubectl apply -f x"}}
        bash_result = subprocess.run(
            [sys.executable, str(HELPER)], input=json.dumps(bash_payload), text=True,
            capture_output=True, check=True
        )
        self.assertEqual(json.loads(bash_result.stdout), {"classification": "mutation"})
        malformed = subprocess.run(
            [sys.executable, str(HELPER)], input="{", text=True, capture_output=True
        )
        self.assertNotEqual(malformed.returncode, 0)
        self.assertEqual(malformed.stdout, "")


if __name__ == "__main__":
    unittest.main()
