# Validation

> **Part of:** [kubernetes-skill](../SKILL.md)
> **Purpose:** Left-of-apply pipeline, schema validation, policy gates, CI wiring

---

## TOC

1. [Why Validation Matters More in GitOps](#why-validation-matters-more-in-gitops)
2. [Schema Validation — kubeconform](#schema-validation--kubeconform)
3. [Dry-Run — Client vs Server](#dry-run--client-vs-server)
4. [Render + Validate Pipelines](#render--validate-pipelines)
5. [Policy Validation](#policy-validation)
6. [CI Gate Pattern](#ci-gate-pattern)
7. [Troubleshooting Table](#troubleshooting-table)
8. [LLM Mistake Checklist](#llm-mistake-checklist)

---

## Why Validation Matters More in GitOps

In Terraform, a failed `plan` or `apply` surfaces immediately and the engineer retries. In GitOps, the apply happens asynchronously in the cluster controller. A bad manifest merges to `main`, the PR closes, and the error surfaces minutes later as a `SyncFailed` condition that someone has to diagnose. There is no "apply review" step like Terraform's plan.

CI must catch errors before merge. The left-of-apply pipeline replaces the plan/apply review loop.

---

## Schema Validation — kubeconform

`kubeconform` validates manifests against Kubernetes JSON schemas. Faster than `kubeval` (which it replaces); supports CRD schemas via `-schema-location`.

```bash
# Validate a directory of manifests
kubeconform \
  -strict \
  -summary \
  -kubernetes-version 1.30.0 \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  manifests/

# kubeconform flags
# -strict: fail on unknown fields (catches typos in field names)
# -summary: print pass/fail/skip counts
# -kubernetes-version: validate against this k8s version's schemas
# -schema-location default: official k8s schemas from kubernetes-json-schema repo
# -schema-location <url>: additional schema location for CRDs
# -output text|json|tap: output format
```

**CRD schemas:** the default schema location does not know about CRDs (Karpenter NodePool, Gateway API HTTPRoute, ArgoCD Application, etc.). Add the CRDs-catalog or generate schemas from CRD YAMLs.

```bash
# Generate CRD schema from a live cluster
kubectl get crd nodepools.karpenter.sh -o json \
  | python3 -c "
import json, sys
crd = json.load(sys.stdin)
schema = crd['spec']['versions'][0]['schema']['openAPIV3Schema']
print(json.dumps(schema, indent=2))
" > nodepools-schema.json

# Point kubeconform at a local schema dir
kubeconform \
  -schema-location 'schemas/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  manifests/
```

---

## Dry-Run — Client vs Server

| Mode | What it does | What it catches |
|------|-------------|-----------------|
| `--dry-run=client` | Generates the object locally; no API call | Syntax errors, missing required fields per client-side schema |
| `--dry-run=server` | Sends the object to the API server; not persisted | All of the above + admission webhooks + server-side validation + quota checks + CRD validation |

`--dry-run=server` is the gold standard — it runs the full admission chain without persisting. Use it in CI for any namespace with admission webhooks (PSA, Kyverno, OPA Gatekeeper, ValidatingAdmissionPolicy).

```bash
# Server dry-run on a single manifest
kubectl apply --dry-run=server -f deployment.yaml

# Server dry-run on rendered Helm output
helm template my-release ./chart -f values-prod.yaml \
  | kubectl apply --dry-run=server -f -

# Server dry-run on a Kustomize overlay
kubectl apply --dry-run=server -k overlays/prod

# Server dry-run on kustomize build output (uses standalone kustomize)
kustomize build overlays/prod \
  | kubectl apply --dry-run=server -f -
```

`--dry-run=server` requires a reachable cluster. For pure CI without cluster access, `--dry-run=client` plus `kubeconform -strict` catches most structural errors. Add `--dry-run=server` in a dedicated staging pre-deploy step.

---

## Render + Validate Pipelines

### Helm pipeline

```bash
# Step 1: Lint (chart structure + values schema)
helm lint ./chart -f values-prod.yaml --strict

# Step 2: Render
helm template my-release ./chart -f values-prod.yaml > rendered.yaml

# Step 3: Schema validate rendered output
kubeconform \
  -strict \
  -kubernetes-version 1.30.0 \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  rendered.yaml

# Step 4: Policy check
kyverno apply ./policies/ --resource rendered.yaml
# or: conftest test rendered.yaml --policy ./policies/

# Step 5: Server dry-run (requires cluster)
kubectl apply --dry-run=server -f rendered.yaml
```

### Kustomize pipeline

```bash
# Step 1: Build (catches reference errors, missing patches)
kustomize build overlays/prod > rendered.yaml

# Step 2: Schema validate
kubeconform \
  -strict \
  -kubernetes-version 1.30.0 \
  -schema-location default \
  rendered.yaml

# Step 3: Policy check
kyverno apply ./policies/ --resource rendered.yaml

# Step 4: Server dry-run
kubectl apply --dry-run=server -f rendered.yaml
```

---

## Policy Validation

### Kyverno CLI

```bash
# Install
brew install kyverno   # or download binary

# Apply policies against rendered manifests (offline — no cluster needed)
kyverno apply ./kyverno-policies/ --resource rendered.yaml

# Run policy tests (kyverno test suite)
kyverno test ./kyverno-policies/tests/

# kyverno test structure:
# tests/
# ├── kyverno-test.yaml      # test manifest listing resources + expected results
# ├── resources/
# │   ├── pass-pod.yaml
# │   └── fail-pod.yaml
# └── policies/
#     └── require-labels.yaml
```

`kyverno apply` exits non-zero if any `Enforce` policy fails — makes it CI-gate compatible.

### OPA / conftest

```bash
# conftest evaluates Rego policies against YAML/JSON input
conftest test rendered.yaml \
  --policy ./policies/ \
  --namespace kubernetes    # Rego package namespace

# Pull policies from OCI registry
conftest pull oci://ghcr.io/org/k8s-policies:latest
conftest test rendered.yaml
```

### Polaris

Polaris checks best-practice configuration (missing probes, no resource limits, no security context). Produces a scored report.

```bash
# Audit a live cluster
polaris audit --cluster --format=pretty

# Audit rendered manifests (offline)
polaris audit --audit-path rendered.yaml --format=pretty

# Exit non-zero if score below threshold
polaris audit --audit-path rendered.yaml \
  --set-exit-code-on-score 80 \   # fail if score < 80
  --set-exit-code-below-score 80
```

### Trivy

Trivy covers both misconfiguration and image CVEs.

```bash
# Scan manifests for misconfigurations
trivy config manifests/

# Scan a Kustomize overlay
kustomize build overlays/prod | trivy config --file-patterns "*.yaml" -

# Scan a Helm chart
trivy config ./chart/

# Scan a specific image for CVEs (in CI, before push)
trivy image \
  --exit-code 1 \
  --severity HIGH,CRITICAL \
  my-app:1.2.3

# Scan the cluster in-cluster
trivy k8s --report=summary cluster
```

`trivy config` checks against known misconfig rules (CIS benchmarks, NSA hardening guide). It does not replace schema validation — use both.

---

## CI Gate Pattern

A PR gate that renders → schema-checks → policy-checks before merge:

```yaml
# .github/workflows/validate.yaml (GitHub Actions example)
name: Manifest Validation

on:
  pull_request:
    paths:
      - 'k8s/**'
      - 'charts/**'

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install tools
        run: |
          # kubeconform
          curl -sSL https://github.com/yannh/kubeconform/releases/latest/download/kubeconform-linux-amd64.tar.gz \
            | tar xz -C /usr/local/bin
          # kyverno
          curl -sSL https://github.com/kyverno/kyverno/releases/latest/download/kyverno_linux_x86_64.tar.gz \
            | tar xz -C /usr/local/bin
          # kustomize
          curl -sSL https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh \
            | bash -s /usr/local/bin

      - name: Render Helm charts
        run: |
          for values in charts/*/ci/*.yaml; do
            chart=$(dirname $(dirname $values))
            helm template test "$chart" -f "$values" > /tmp/rendered-$(basename $chart).yaml
          done

      - name: Render Kustomize overlays
        run: |
          for overlay in k8s/overlays/*/; do
            env=$(basename $overlay)
            kustomize build "$overlay" > /tmp/rendered-kustomize-$env.yaml
          done

      - name: Schema validate
        run: |
          kubeconform \
            -strict \
            -summary \
            -kubernetes-version 1.30.0 \
            -schema-location default \
            -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
            /tmp/rendered-*.yaml

      - name: Policy validate
        run: |
          kyverno apply ./kyverno-policies/ --resource /tmp/rendered-*.yaml

      - name: Config scan (Trivy)
        run: |
          trivy config k8s/ charts/
```

For teams using ArgoCD or Flux: add a step that calls `argocd app diff` or `flux diff kustomization` against a staging cluster using a short-lived kubeconfig. This catches webhook rejections that `kubeconform` misses.

---

## Troubleshooting Table

| Error message | Cause | Fix |
|---------------|-------|-----|
| `no matches for kind "X" in version "Y"` | Wrong `apiVersion` for the Kind; CRD not installed | Check [API-Version Guard Table](workloads.md#api-version-guard-table); install CRD first |
| `unknown field "X"` | Field name typo or wrong API version | `-strict` kubeconform flags catches this; check API reference for the correct field name |
| `admission webhook denied: <policy>` | Kyverno/OPA/PSA rejected the resource | Read the policy message; fix the failing field (usually securityContext, image registry, or labels) |
| `error validating: no kind is registered for the type` | kubeconfig points at wrong cluster or context | `kubectl config current-context`; verify cluster version vs apiVersion |
| `manifest does not meet minimum chart requirements` | `helm lint` found structural issue | Check `Chart.yaml` `apiVersion: v2`; check required fields |
| `error converting YAML to JSON: yaml: line X` | YAML syntax error (tabs, indentation) | `kubeconform` or `helm template` will show the line; fix indentation |
| `PodSecurityPolicy` or `batch/v1beta1 CronJob` in cluster | Targeting old cluster version | Check cluster version; update `apiVersion` to current |
| `field is immutable` on apply | Attempt to change an immutable field (e.g., pod selector labels) | Delete and recreate the resource; in GitOps, use a rename + `moved` pattern |

---

## LLM Mistake Checklist

- Recommends `kubeval` — it is unmaintained since 2021; use `kubeconform`.
- Runs only `--dry-run=client` and claims it catches admission webhook failures — client dry-run does not call the API server; `--dry-run=server` is needed for webhook coverage.
- Pipes `helm template` through `kubectl apply --dry-run=client` instead of `--dry-run=server` — client mode misses webhook rejections and server-side schema gaps.
- Omits `-strict` from kubeconform — without it, unknown fields pass validation silently; `-strict` treats unknown fields as errors.
- Does not add CRD schema locations to kubeconform — CRD-backed resources (Karpenter, Gateway API, ArgoCD) silently skip validation as "unknown" resources.
- Treats `kyverno apply` (offline) as equivalent to a live admission webhook — offline policy check validates policy logic but does not reflect cluster-specific context (existing resources, namespace labels).
- Recommends Polaris as the only policy tool — Polaris checks best practices, not org-specific policies; combine with Kyverno or OPA for policy gates.
- Uses `trivy image` to check manifests — `trivy config` is for manifests; `trivy image` is for container CVEs; they are different subcommands.
- Generates CI validation without an explicit Kubernetes version for kubeconform — without `-kubernetes-version`, kubeconform defaults to the latest, which may not match the target cluster.
- Skips the render step and runs kubeconform directly on Helm template files — template files contain Go template syntax that is not valid YAML and will fail; always render first.
- Assumes `helm lint` is sufficient validation — lint checks chart structure and values schema only; it does not validate the rendered Kubernetes manifests.
- Recommends `kubectl diff` instead of `--dry-run=server` for CI — `kubectl diff` requires existing resources in the cluster; `--dry-run=server` works on new resources too.

---

**Back to:** [Main Skill File](../SKILL.md)
