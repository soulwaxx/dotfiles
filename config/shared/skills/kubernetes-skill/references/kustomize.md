# Kustomize

> **Part of:** [kubernetes-skill](../SKILL.md)
> **Purpose:** Base + overlay layout, patches, generators, components, namePrefix, build and apply

---

## TOC

1. [Base and Overlay Layout](#base-and-overlay-layout)
2. [kustomization.yaml Fields](#kustomizationyaml-fields)
3. [Patches — Strategic Merge vs JSON6902](#patches--strategic-merge-vs-json6902)
4. [ConfigMapGenerator and SecretGenerator](#configmapgenerator-and-secretgenerator)
5. [Components](#components)
6. [namePrefix, nameSuffix, Labels](#nameprefix-namesuffix-labels)
7. [Build and Apply](#build-and-apply)
8. [When Templating Beats Patching](#when-templating-beats-patching)
9. [LLM Mistake Checklist](#llm-mistake-checklist)

---

## Base and Overlay Layout

```
k8s/
├── base/
│   ├── kustomization.yaml   # references all base resources
│   ├── deployment.yaml
│   ├── service.yaml
│   └── serviceaccount.yaml
└── overlays/
    ├── dev/
    │   ├── kustomization.yaml
    │   └── replicas-patch.yaml
    ├── staging/
    │   ├── kustomization.yaml
    │   └── resources-patch.yaml
    └── prod/
        ├── kustomization.yaml
        ├── replicas-patch.yaml
        └── hpa.yaml
```

The base is environment-agnostic. Overlays are the delta — they reference the base via `resources` and layer patches, images, or generators on top. The base itself should produce valid manifests; overlays only add or override.

**Never edit the base to accommodate a single overlay.** If only prod needs a sidecar, add it in the prod overlay via a patch, not in the base.

---

## kustomization.yaml Fields

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# --- Resources ---
resources:
  - ../../base              # reference a base directory
  - extra-rbac.yaml         # or a specific file
  - https://example.com/manifest.yaml   # remote (avoid in prod — supply chain risk)

# --- Image overrides ---
images:
  - name: my-app                     # matches image field in all manifests
    newName: 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app
    newTag: "1.2.3"
    # digest: sha256:<hash>           # use digest for immutable references

# --- Replica overrides ---
replicas:
  - name: api-server                 # matches Deployment/StatefulSet name
    count: 5

# --- Patches ---
patches:
  - path: replicas-patch.yaml        # strategic merge patch (default)
  - path: resources-patch.yaml
    target:                          # target selector (for JSON6902 or multi-match)
      kind: Deployment
      name: api-server

# --- Generators ---
configMapGenerator:
  - name: app-config
    files:
      - config/app.properties
    literals:
      - LOG_LEVEL=info

secretGenerator:
  - name: db-creds
    envs:
      - secrets.env       # KEY=value format
    type: kubernetes.io/opaque
```

---

## Patches — Strategic Merge vs JSON6902

### Strategic merge patch

A strategic merge patch is a partial manifest. Fields present in the patch override the base; absent fields are unchanged. Arrays are merged (by name field) rather than replaced, unless a `$patch: replace` directive is used.

```yaml
# overlays/prod/replicas-patch.yaml
# No apiVersion/kind/metadata required if the patch file contains them,
# but including them makes the file self-documenting and allows direct kubectl apply
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-server
spec:
  replicas: 10
  template:
    spec:
      containers:
        - name: api                   # matched by name field
          resources:
            requests:
              cpu: 500m
              memory: 512Mi
            limits:
              memory: 1Gi
```

Reference in `kustomization.yaml`:
```yaml
patches:
  - path: replicas-patch.yaml
```

### JSON6902 patch

More precise: explicitly states the operation (add/replace/remove) and the exact JSON Pointer path. Required when the field does not exist in the base or when you need to remove a field.

```yaml
# overlays/prod/remove-debug.yaml
- op: remove
  path: /spec/template/spec/containers/0/env/0   # remove first env var

- op: replace
  path: /spec/replicas
  value: 10

- op: add
  path: /spec/template/metadata/annotations/prometheus.io~1scrape
  value: "true"
```

Note: `/` in a JSON Pointer key is escaped as `~1`. `~` is escaped as `~0`.

Reference in `kustomization.yaml` with a `target` selector:
```yaml
patches:
  - path: remove-debug.yaml
    target:
      group: apps
      version: v1
      kind: Deployment
      name: api-server
      namespace: production
```

**When to use each:**

| | Strategic Merge | JSON6902 |
|--|-----------------|---------|
| Override existing field | ✅ simple | ✅ precise |
| Remove a field | ❌ cannot | ✅ `op: remove` |
| Add to an array positionally | Merges by name | ✅ `op: add /path/-` appends |
| Replace an entire array | `$patch: replace` directive | ✅ `op: replace` |
| Multi-resource targeting | One file per resource | Single file, `target` selector |

---

## ConfigMapGenerator and SecretGenerator

Generators create ConfigMaps and Secrets from files, literals, or env files. By default, they append a content hash to the name (`app-config-abc1234f`). Any Deployment referencing the ConfigMap by base name gets the hash injected automatically.

**Why the hash suffix:** a change to the ConfigMap content produces a new name, which triggers a Pod rollout. Without this, updating a ConfigMap does not restart Pods consuming it as an env source.

```yaml
configMapGenerator:
  - name: app-config
    literals:
      - LOG_LEVEL=info
      - MAX_CONNECTIONS=50
    files:
      - config/feature-flags.yaml
    options:
      disableNameSuffixHash: false   # default: hash enabled
```

**Disable the hash** when the ConfigMap is referenced by a fixed external name (e.g., a mounted volume by name, or a third-party operator watching a specific ConfigMap name):

```yaml
configMapGenerator:
  - name: prometheus-config
    files:
      - prometheus.yml
    options:
      disableNameSuffixHash: true
```

**Merge behavior across overlays:**

```yaml
# overlay/prod/kustomization.yaml
configMapGenerator:
  - name: app-config        # same name as base
    behavior: merge         # merge adds/overrides keys from base generator
    literals:
      - LOG_LEVEL=warn      # overrides base value
    # behavior: replace     # replaces the entire configmap, ignoring base
    # behavior: create      # creates a new one (default; errors if name exists)
```

`SecretGenerator` works identically but produces `kind: Secret`. Use `envs:` for `.env`-style files (one `KEY=value` per line). Never commit secret source files to Git — pipe them from a secrets manager in CI, or use External Secrets Operator instead.

---

## Components

Components are reusable Kustomize modules — partial configurations that multiple overlays can opt into. Unlike a base (which is always applied), a component is only applied when an overlay explicitly includes it.

```
k8s/
└── components/
    ├── monitoring/
    │   ├── kustomization.yaml
    │   └── servicemonitor.yaml
    └── tls/
        ├── kustomization.yaml
        └── certificate.yaml
```

```yaml
# components/monitoring/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component
resources:
  - servicemonitor.yaml
patches:
  - path: add-metrics-port.yaml
    target:
      kind: Deployment
```

An overlay opts in:
```yaml
# overlays/prod/kustomization.yaml
resources:
  - ../../base
components:
  - ../../components/monitoring
  - ../../components/tls
```

Components solve the diamond problem: if both `monitoring` and `tls` need to patch the same Deployment, each component patches it independently and they compose.

---

## namePrefix, nameSuffix, Labels

```yaml
namePrefix: prod-      # prepended to every resource name
nameSuffix: -v2        # appended to every resource name
```

Both transformations propagate through cross-references: a Service referenced by a Deployment's `selector`, an Ingress backend, or a ConfigMap referenced by name all get the prefix/suffix applied consistently.

**`commonLabels` is deprecated.** It mutated selector labels on Deployments, which are immutable after creation — a prefix change would require deleting and recreating the Deployment. Use `labels` instead:

```yaml
labels:
  - pairs:
      app.kubernetes.io/part-of: my-system
      environment: prod
    includeSelectors: false    # do NOT add to pod selector (avoids immutability trap)
    includeTemplates: true     # add to pod template labels (for metrics/logging)
```

`includeSelectors: true` is the old `commonLabels` behavior and carries the same immutability risk. Leave it `false` unless you are intentionally setting selectors on all resources.

---

## Build and Apply

```bash
# Render to stdout — inspect before applying
kustomize build overlays/prod

# Pipe to kubeconform for schema validation
kustomize build overlays/prod \
  | kubeconform -strict -schema-location default \
    -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
    -summary

# Apply directly with kubectl
kubectl apply -k overlays/prod

# Dry-run (client side — does not call admission webhooks)
kubectl apply -k overlays/prod --dry-run=client

# Server dry-run (real admission, real API validation)
kubectl apply -k overlays/prod --dry-run=server
```

`kubectl apply -k` uses the kustomize library bundled with kubectl, which may lag standalone `kustomize`. For features added after the bundled version, install standalone kustomize and pipe: `kustomize build ... | kubectl apply -f -`.

---

## When Templating Beats Patching

Kustomize excels at structural deltas (replicas, images, resources). It does not express conditional logic.

Use Helm instead when:
- A resource should be conditionally included or excluded based on a flag (`if .Values.hpa.enabled`).
- You need to loop over a variable-length list to generate resources (`range .Values.ingresses`).
- The chart is distributed to others who need a documented, typed values interface.

A common mistake is fighting Kustomize to express what Go templating does in two lines:

```yaml
# ❌ Kustomize cannot conditionally include a whole resource based on a variable.
# You end up maintaining separate overlay dirs just to omit a file.

# ✅ Helm:
{{- if .Values.autoscaling.enabled }}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
...
{{- end }}
```

For first-party apps with simple environment deltas, Kustomize is the right fit. For anything with conditional rendering or distribution to external users, Helm wins.

---

## LLM Mistake Checklist

- Uses `commonLabels` to set environment or version labels — deprecated; mutates pod selectors, breaks in-place updates; use `labels` with `includeSelectors: false`.
- Patches a field that does not exist in the base using a strategic merge patch — strategic merge cannot add net-new top-level fields in some versions; use JSON6902 `op: add` for that.
- Escapes `/` in a JSON Pointer path as `\/` — correct escape is `~1`; `~/` is wrong.
- Puts secrets in a `secretGenerator` with `literals:` and commits the `kustomization.yaml` to Git — the secret value is in plaintext in Git; use External Secrets Operator, SOPS, or sealed-secrets.
- Disables name suffix hash on a ConfigMap that Pods consume as an env source — content changes will not trigger a rollout.
- Uses `behavior: merge` without a base generator of the same name — merge requires the name to already exist in the base; it errors if absent.
- References a remote URL in `resources:` for production overlays — network-fetched resources at apply time are a supply-chain risk and break air-gapped clusters.
- Uses `kubectl apply -k` and expects the latest kustomize features — the bundled version lags; pipe through standalone `kustomize build | kubectl apply -f -` for new features.
- Applies a JSON6902 patch with an array index (`/spec/containers/0`) on a multi-container Pod — index-based paths break when containers are reordered; use a strategic merge patch matched by container name instead.
- Sets `namePrefix` or `nameSuffix` without noting that cross-references (Service selectors, Ingress backends, volume mounts by name) are updated automatically — callers sometimes add manual patches for these unnecessarily.
- Puts `components:` under `resources:` — components are a separate top-level field; placing them under `resources:` causes a parse error.

---

**Back to:** [Main Skill File](../SKILL.md)
