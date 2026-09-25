---
name: infra-review
disable-model-invocation: true
description: Review infrastructure changes for operational, security, reliability, cost, and migration risk. Use when asked for any kind of infrastructure review — and proactively when the user shares Terraform, Kubernetes manifests, Helm charts, GitOps config, CI/CD pipelines, or AWS CDK and asks 'what do you think', 'is this ok', or 'does this look right', even without the word 'review'.
---

# infra-review

Review infrastructure changes with a production-operations lens. Prefer concrete risks over style advice.

## Scope

Review whatever scope or files the user named. If none were named, inspect the current diff and nearby infrastructure files.

Relevant files include Terraform/OpenTofu, AWS CDK, Kubernetes manifests, Helm charts, GitOps config, CI/CD workflows, IAM policies, networking, monitoring, backup, and secrets-management config.

## Workflow

1. Build context first. Check the diff, then read only the files needed to understand the changed resource, module, chart, or pipeline.
2. Verify current docs before quoting exact AWS, Kubernetes, Terraform provider, Helm, or CLI fields and flags.
3. Look for risks in this order: security, data loss, availability, rollback, state drift, blast radius, cost, operability, maintainability.
4. Treat missing tests, missing validation, or missing rollout/rollback steps as findings only when they create a concrete operational risk.
5. Do not rewrite code unless the user explicitly asks for fixes. This skill is review-first.

## Output

Use this structure exactly:

```markdown
## Findings

1. [Severity] File:line - Short title
   Impact: What can fail, leak, drift, or cost money.
   Evidence: The exact config or behavior that creates the risk.
   Fix: The smallest change that reduces the risk.

## Open Questions

- Question or assumption that affects the review result.

## Residual Risk

- What was not verified, including unavailable docs, missing runtime context, or tests not run.
```

If there are no findings, say `No findings.` first, then list residual risks.

## Severity

- Critical: likely data loss, credential exposure, public exposure of private systems, or production-wide outage.
- High: plausible outage, privilege escalation, destructive state change, or expensive runaway behavior.
- Medium: operational regression, missing guardrail, rollback gap, or cost/performance risk with bounded blast radius.
- Low: maintainability or observability issue that does not block rollout.
