# Helm

> **Part of:** [kubernetes-skill](../SKILL.md)
> **Purpose:** Chart structure, values contracts, templating pitfalls, hooks, OCI, lint/test, post-rendering

---

## TOC

1. [Chart Directory Structure](#chart-directory-structure)
2. [Values Contract Discipline](#values-contract-discipline)
3. [Templating Pitfalls](#templating-pitfalls)
4. [Hooks](#hooks)
5. [OCI Registry Push and Pull](#oci-registry-push-and-pull)
6. [Library Charts](#library-charts)
7. [Lint, Template, Test, Diff](#lint-template-test-diff)
8. [Post-Rendering with Kustomize](#post-rendering-with-kustomize)
9. [LLM Mistake Checklist](#llm-mistake-checklist)

---

## Chart Directory Structure

```
my-chart/
├── Chart.yaml          # chart metadata: name, version, appVersion, dependencies
├── values.yaml         # default values; the contract between chart and user
├── values.schema.json  # optional JSON Schema validation for values
├── templates/
│   ├── _helpers.tpl    # named templates; no YAML output; starts with underscore
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── serviceaccount.yaml
│   ├── hpa.yaml
│   ├── pdb.yaml
│   └── NOTES.txt       # printed to stdout after helm install/upgrade
├── charts/             # vendored subchart tarballs (populated by helm dep update)
└── .helmignore
```

**`Chart.yaml` minimum:**
```yaml
apiVersion: v2           # always v2 for Helm 3
name: my-chart
description: Single-line description.
type: application        # or "library" for shared template charts
version: 0.1.0           # chart version; bump on any change to templates or values
appVersion: "1.2.3"      # upstream app version; informational only
```

`version` and `appVersion` are independent. `version` governs Helm release history. `appVersion` is cosmetic — it often matches the image tag but Helm does not use it for anything except `helm list` display.

---

## Values Contract Discipline

`values.yaml` is the public interface of the chart. Treat it like a typed API.

```yaml
# Every key must have a comment explaining purpose and accepted values.
# Every key must have a type-stable default — never omit a key and rely on
# templates doing nil-checks; the schema should catch omissions.

replicaCount: 1

image:
  repository: my-app
  tag: ""                  # defaults to Chart.appVersion if empty (set in _helpers.tpl)
  pullPolicy: IfNotPresent
  digest: ""               # if set, takes precedence over tag

service:
  type: ClusterIP
  port: 80

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    memory: 256Mi

autoscaling:
  enabled: false
  minReplicas: 1
  maxReplicas: 10
  targetCPUUtilizationPercentage: 80

podAnnotations: {}         # map[string]string; type stable; {} not null
podLabels: {}

nodeSelector: {}
tolerations: []            # list stable; [] not null
affinity: {}
```

**Type stability rules:**
- Maps must default to `{}`, not `null` or absent. A template doing `range .Values.podAnnotations` over a null value panics.
- Lists must default to `[]`, not absent.
- Booleans must be `true`/`false` not `"true"`/`"false"` — Helm renders string `"false"` as truthy in `if`.
- Never use a nested key without declaring the parent. `image.pullPolicy` requires `image:` to exist in defaults.

---

## Templating Pitfalls

### nil map dereference

```yaml
# ❌ Panics if .Values.ingress is not set (nil map)
{{- if .Values.ingress.enabled }}

# ✅ Safe: hasKey check or dot-chain with default
{{- if and .Values.ingress (hasKey .Values.ingress "enabled") .Values.ingress.enabled }}

# ✅ Cleaner: declare ingress.enabled: false in values.yaml so it always exists
{{- if .Values.ingress.enabled }}
```

### default and required

```yaml
# Provide a fallback
image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"

# Fail fast if a required value is absent
{{- required "image.repository must be set" .Values.image.repository }}
```

### toYaml with nindent

`toYaml` serialises a map/list to YAML. `nindent N` adds a leading newline and indents by N spaces. The N must match the YAML context — wrong indentation silently produces invalid YAML that `helm template` may not catch.

```yaml
# ✅ Correct: 2-space indent inside a resource block, nindent 2
resources:
  {{- toYaml .Values.resources | nindent 2 }}

# ✅ Correct: 8-space context (inside spec.template.spec.containers[])
        resources:
          {{- toYaml .Values.resources | nindent 10 }}

# ❌ Wrong nindent produces misaligned YAML:
resources:
  {{- toYaml .Values.resources | nindent 4 }}  # extra indent breaks parsing
```

Count the spaces from the start of the line to the key, then use that number for `nindent`.

### Scope inside range

`range` changes `.` to the current loop item. To access chart-level context (`.Values`, `.Chart`, `.Release`) inside a loop, capture the outer scope with `$`.

```yaml
{{- range .Values.ingress.hosts }}
  - host: {{ .host }}
    http:
      paths:
        {{- range .paths }}
          - path: {{ .path }}
            # ❌ .Values is nil inside range — this is the loop item's Values
            # ✅ use $ to reach chart scope
            backend:
              service:
                name: {{ $.Release.Name }}-svc
                port:
                  number: {{ $.Values.service.port }}
        {{- end }}
{{- end }}
```

### if with empty string vs false

```yaml
# "" is falsy in Go templates
{{- if .Values.image.tag }}   # skips the block if tag is ""
  image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
{{- end }}
```

Boolean string trap: `enabled: "false"` (string) evaluates truthy. Always use unquoted YAML booleans.

---

## Hooks

Hooks run at defined lifecycle points. They are Jobs or Pods annotated with `helm.sh/hook`.

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migrate
  annotations:
    helm.sh/hook: pre-upgrade,pre-install      # runs before main manifest apply
    helm.sh/hook-weight: "-5"                  # lower runs first; default 0
    helm.sh/hook-delete-policy: before-hook-creation,hook-succeeded
```

**Hook phases:**

| Hook | When | Typical use |
|------|------|-------------|
| `pre-install` | Before any resources installed | Cert provisioning, pre-flight checks |
| `post-install` | After all resources installed and ready | Seed data, smoke test |
| `pre-upgrade` | Before upgrade starts | DB migration, backup |
| `post-upgrade` | After upgrade completes | Validation |
| `pre-delete` | Before `helm uninstall` | Drain queues |
| `post-delete` | After deletion | Audit log |
| `test` | When `helm test` runs | Integration smoke test |

**Hook delete policies:**

| Policy | When it deletes the hook resource |
|--------|-----------------------------------|
| `before-hook-creation` | Before creating the hook (replaces the previous run) |
| `hook-succeeded` | After the hook completes successfully |
| `hook-failed` | After the hook fails (useful for preserving logs) |

**CRD install race:** if a chart installs CRDs and then immediately uses them, the templates render correctly but the API server may not have registered the CRD yet. Put CRDs in `crds/` directory — Helm installs them before any other resource and does not touch them on `helm upgrade`. If you need upgrade management for CRDs, use a `pre-install`/`pre-upgrade` hook Job with `kubectl apply`.

---

## OCI Registry Push and Pull

Helm 3.8+ supports OCI registries as first-class chart repositories.

```bash
# Push
helm package my-chart                          # creates my-chart-0.1.0.tgz
helm push my-chart-0.1.0.tgz oci://123456789012.dkr.ecr.us-east-1.amazonaws.com/charts

# Authenticate to ECR
aws ecr get-login-password --region us-east-1 \
  | helm registry login \
      --username AWS \
      --password-stdin \
      123456789012.dkr.ecr.us-east-1.amazonaws.com

# Pull and install
helm install my-release \
  oci://123456789012.dkr.ecr.us-east-1.amazonaws.com/charts/my-chart \
  --version 0.1.0

# In Chart.yaml dependency (OCI)
dependencies:
  - name: my-chart
    version: "0.1.0"
    repository: "oci://123456789012.dkr.ecr.us-east-1.amazonaws.com/charts"
```

OCI registries do not need `helm repo add`. The `oci://` scheme replaces the repo URL everywhere.

---

## Library Charts

A library chart (`type: library` in `Chart.yaml`) provides shared named templates and cannot be installed directly. It produces no Kubernetes resources.

```yaml
# library/Chart.yaml
apiVersion: v2
name: my-helpers
type: library
version: 0.1.0
```

```yaml
# _labels.tpl in the library
{{- define "my-helpers.commonLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
```

Consumer chart declares the library as a dependency:

```yaml
# consumer/Chart.yaml
dependencies:
  - name: my-helpers
    version: "0.1.0"
    repository: "oci://..."
```

Then calls: `{{- include "my-helpers.commonLabels" . | nindent 4 }}`

---

## Lint, Template, Test, Diff

```bash
# Schema and structure validation
helm lint ./my-chart

# Lint with a specific values file
helm lint ./my-chart -f values-prod.yaml

# Render templates locally — pipe to kubeconform for schema check
helm template my-release ./my-chart -f values-prod.yaml \
  | kubeconform -strict -summary

# Dry-run against a live cluster (real admission webhooks fire)
helm install my-release ./my-chart --dry-run --debug

# Install/upgrade with server-side dry-run (Helm 3.13+)
helm upgrade --install my-release ./my-chart --dry-run=server

# Run hook-annotated test Pods/Jobs
helm test my-release -n production

# Diff before upgrade (requires helm-diff plugin)
helm diff upgrade my-release ./my-chart -f values-prod.yaml
```

`helm template` is purely local — it does not call the API server. Admission webhooks, CRD validation, and server-side defaults are all skipped. `--dry-run=server` or `kubectl apply --dry-run=server` on the rendered output is required to catch admission rejections.

---

## Post-Rendering with Kustomize

Post-rendering runs a command on the rendered YAML before apply. Use it to apply Kustomize patches to a chart you do not own.

```bash
helm upgrade --install my-release my-chart/chart \
  --post-renderer ./kustomize-wrapper.sh
```

```bash
#!/usr/bin/env bash
# kustomize-wrapper.sh — reads stdin (helm output), passes through kustomize build
cat > /tmp/helm-output.yaml
cd /tmp/kustomize-overlay
cat helm-output.yaml > all.yaml
kustomize build .
```

Kustomize overlay adds a patch:
```yaml
# /tmp/kustomize-overlay/kustomization.yaml
resources:
  - all.yaml
patches:
  - path: add-annotations.yaml
    target:
      kind: Deployment
```

Post-rendering is the escape hatch when the chart does not expose a value you need to change. Prefer exposing a proper chart value when you own the chart.

---

## LLM Mistake Checklist

- Emits `apiVersion: v1` in `Chart.yaml` — correct for Helm 2 only; Helm 3 uses `apiVersion: v2`.
- Does not declare `type: library` in a library chart — Helm will try to install it directly and fail.
- Writes `{{- toYaml .Values.resources | indent 2 }}` — `indent` does not add a leading newline, causing YAML merge issues; use `nindent`.
- Uses `.Values.something.key` without declaring `something: {}` in `values.yaml` — panics at nil map dereference when the user omits the key.
- Uses `{{ .Values.autoscaling.enabled | toString }}` to get a boolean string — renders `"false"` which is truthy in a subsequent `if`; compare directly or use `eq .Values.x true`.
- Places CRDs in `templates/` and expects them installed before other resources in the same chart — Helm does not guarantee ordering within `templates/`; put CRDs in `crds/` or a pre-install hook.
- Omits `helm.sh/hook-delete-policy` on hook Jobs — previous runs accumulate and eventually cause `AlreadyExists` errors.
- Uses `helm repo add` for an OCI registry — OCI registries use `oci://` scheme and do not require `helm repo add`.
- Emits hook weight as an integer (`helm.sh/hook-weight: -5`) — hook weights must be string values (`"-5"`).
- Accesses `.Values` inside `range` without `$` prefix — `.Values` inside a range loop is the loop item; outer context requires `$.Values`.
- Does not note that `helm template` skips admission webhooks — callers need `--dry-run=server` or a server-side check to catch webhook rejections.
- Sets `appVersion` with a leading `v` (`v1.2.3`) without noting that Helm strips it inconsistently across versions — use `"1.2.3"` for consistency.

---

**Back to:** [Main Skill File](../SKILL.md)
