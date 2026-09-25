# GitOps

> **Part of:** [kubernetes-skill](../SKILL.md)
> **Purpose:** ArgoCD and Flux delivery patterns, sync-wave ordering, failure diagnosis

---

## TOC

1. [ArgoCD — Application Spec](#argocd--application-spec)
2. [ArgoCD — Automated Sync and Self-Heal](#argocd--automated-sync-and-self-heal)
3. [ArgoCD — App-of-Apps and ApplicationSet](#argocd--app-of-apps-and-applicationset)
4. [ArgoCD — Sync Waves and Hooks](#argocd--sync-waves-and-hooks)
5. [ArgoCD — Sync Windows](#argocd--sync-windows)
6. [ArgoCD — ignoreDifferences](#argocd--ignoredifferences)
7. [ArgoCD — Health and Degraded Diagnosis](#argocd--health-and-degraded-diagnosis)
8. [Flux — Core Resources](#flux--core-resources)
9. [Flux — HelmRelease v2](#flux--helmrelease-v2)
10. [Flux — dependsOn and Ordering](#flux--dependson-and-ordering)
11. [Flux — Image Automation](#flux--image-automation)
12. [Sync-Failure Diagnosis Flow](#sync-failure-diagnosis-flow)
13. [ArgoCD vs Flux Selection Note](#argocd-vs-flux-selection-note)
14. [LLM Mistake Checklist](#llm-mistake-checklist)

---

## ArgoCD — Application Spec

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: api-server
  namespace: argocd          # always in the argocd namespace
  finalizers:
    - resources-finalizer.argocd.argoproj.io   # enables cascade delete
spec:
  project: default
  source:
    repoURL: https://github.com/org/gitops-repo
    targetRevision: main
    path: apps/api-server/overlays/prod
    # For Helm:
    # chart: my-chart
    # helm:
    #   valueFiles:
    #     - values-prod.yaml
    #   values: |
    #     replicaCount: 5
  destination:
    server: https://kubernetes.default.svc     # in-cluster; use actual API URL for remote
    namespace: production
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true    # use SSA for field manager discipline; avoids annotation bloat
      - PruneLast=true          # delete old resources after new ones are healthy
```

`resources-finalizer.argocd.argoproj.io` causes ArgoCD to delete all managed resources when the Application is deleted. Remove the finalizer first if you want to abandon management without deleting resources.

---

## ArgoCD — Automated Sync and Self-Heal

| Setting | Effect | When to enable |
|---------|--------|----------------|
| `automated.prune: true` | ArgoCD deletes resources removed from Git | Always in production; without it, removed manifests accumulate as orphans |
| `automated.selfHeal: true` | ArgoCD overwrites manual `kubectl` changes back to Git state | Production; prevents silent drift from ad-hoc fixes |
| `syncPolicy: {}` (no automated) | Sync requires manual trigger or CI call | When you want human approval before each apply |

Without `selfHeal`, a manual `kubectl apply` to a managed namespace causes silent drift — ArgoCD shows `OutOfSync` but does not revert. Enable `selfHeal` or enforce policy that nobody runs `kubectl apply` against managed namespaces.

---

## ArgoCD — App-of-Apps and ApplicationSet

**App-of-Apps:** an Application whose `path` contains Application manifests. ArgoCD reconciles the parent, which creates/updates child Applications, which then sync their own workloads. Useful for bootstrapping a cluster with a single `kubectl apply`.

```
gitops-repo/
├── apps/
│   ├── api-server/
│   └── worker/
└── cluster-apps/
    ├── kustomization.yaml
    ├── api-server-app.yaml     # kind: Application
    └── worker-app.yaml         # kind: Application
```

**ApplicationSet:** generates Applications programmatically from a generator. More powerful than app-of-apps for multi-cluster or multi-tenant patterns.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: cluster-apps
  namespace: argocd
spec:
  generators:
    - git:
        repoURL: https://github.com/org/gitops-repo
        revision: main
        directories:
          - path: apps/*           # one Application per subdirectory
  template:
    metadata:
      name: "{{path.basename}}"
    spec:
      project: default
      source:
        repoURL: https://github.com/org/gitops-repo
        targetRevision: main
        path: "{{path}}"
      destination:
        server: https://kubernetes.default.svc
        namespace: "{{path.basename}}"
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

---

## ArgoCD — Sync Waves and Hooks

Sync waves control apply order within a single sync operation. Lower wave number applies first. ArgoCD waits for all resources in wave N to be healthy before starting wave N+1.

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "-1"    # apply before wave 0 (default)
```

Common wave assignments:

| Wave | What goes here |
|------|----------------|
| `-5` or `-10` | CRD installation (must exist before CRD-backed resources) |
| `-1` | Namespace, RBAC, ServiceAccount, ConfigMap, ExternalSecret |
| `0` | Deployments, StatefulSets (default wave) |
| `1` | Jobs, post-deploy config |
| `5` | Smoke-test hooks |

**Large CRDs need server-side apply.** Big CRD bundles (cert-manager, Prometheus Operator, Istio) exceed the 256 KB metadata limit on the client-side `kubectl.kubernetes.io/last-applied-configuration` annotation, so a default apply fails with `metadata.annotations: Too long`. Sync them with server-side apply (no last-applied annotation) or `Replace`:

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "-5"
    argocd.argoproj.io/sync-options: ServerSideApply=true   # or Replace=true
```

Prefer `ServerSideApply=true` over `Replace=true` — `Replace` deletes and recreates, which drops a CRD's existing custom resources. Set SSA cluster-wide on the Application (`syncOptions: [ServerSideApply=true]`) when most resources are large.

Hooks (`argocd.argoproj.io/hook: PreSync`, `Sync`, `PostSync`, `SyncFail`) run at phase boundaries and also respect wave annotations. A `PreSync` hook at wave `-5` runs before a `PreSync` hook at wave `0`.

Hook delete policies: `HookSucceeded`, `HookFailed`, `BeforeHookCreation` — same semantics as Helm hooks.

---

## ArgoCD — Sync Windows

Sync windows block automated sync outside defined periods. Use for change-freeze windows or to restrict prod deployments to business hours.

```yaml
# In AppProject spec
spec:
  syncWindows:
    - kind: allow
      schedule: "0 9 * * 1-5"    # Monday–Friday 09:00
      duration: 8h
      applications:
        - "*"
      clusters:
        - production-cluster
      namespaces:
        - "*"
      manualSync: true            # allow manual sync even outside window
```

`kind: deny` creates a blackout window. `allow` windows take precedence over `deny` windows when both match.

---

## ArgoCD — ignoreDifferences

Some controllers mutate resources after apply (defaulting fields, injecting sidecars). ArgoCD would otherwise report perpetual `OutOfSync`.

```yaml
spec:
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas             # HPA manages this; ArgoCD should ignore
    - group: ""
      kind: Service
      jsonPointers:
        - /spec/clusterIP            # assigned by kube-controller; not in Git
    - group: admissionregistration.k8s.io
      kind: MutatingWebhookConfiguration
      jqPathExpressions:
        - ".webhooks[].clientConfig.caBundle"   # injected by cert-manager
```

`jsonPointers` uses RFC6901 JSON Pointer. `jqPathExpressions` accepts jq expressions for more complex matching (ArgoCD 2.6+).

---

## ArgoCD — Health and Degraded Diagnosis

```bash
# Check app status
argocd app get <app-name>
argocd app conditions <app-name>

# Get resource-level health
argocd app resources <app-name>

# Force sync
argocd app sync <app-name>

# Force sync, replace (useful for immutable field conflicts)
argocd app sync <app-name> --replace

# Hard refresh (bypasses Git cache)
argocd app get <app-name> --hard-refresh
```

| ArgoCD status | Meaning | First action |
|---------------|---------|-------------|
| `OutOfSync` | Git state differs from cluster state | Check diff: `argocd app diff <name>` |
| `Degraded` | A managed resource's health check failed | `argocd app resources <name>`; check Pod events |
| `Missing` | Resource in Git not found in cluster | Check if namespace exists; check RBAC |
| `Progressing` | Resource exists but health check not yet passing | Wait for timeout; check Pod readiness |
| `SyncFailed` | Last sync operation errored | Read the sync operation message for the specific error |

---

## Flux — Core Resources

**GitRepository:** watches a Git repo and emits an artifact on new commits.

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: gitops-repo
  namespace: flux-system
spec:
  interval: 1m
  url: https://github.com/org/gitops-repo
  ref:
    branch: main
  secretRef:
    name: git-credentials    # SSH key or token; created separately
```

**Kustomization (Flux):** applies a Kustomize overlay from a GitRepository artifact.

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: api-server
  namespace: flux-system
spec:
  interval: 5m
  sourceRef:
    kind: GitRepository
    name: gitops-repo
  path: ./apps/api-server/overlays/prod
  prune: true                  # delete resources removed from Git
  wait: true                   # health-check all resources before marking ready
  timeout: 2m
  targetNamespace: production  # override namespace for all resources
  postBuild:
    substituteFrom:
      - kind: ConfigMap
        name: cluster-vars      # variable substitution in manifests using ${VAR}
```

---

## Flux — HelmRelease v2

`helm.toolkit.fluxcd.io/v2` is the GA API (Flux v2.x). `v2beta1` is deprecated and removed.

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: ingress-nginx
  namespace: flux-system
spec:
  interval: 30m
  chart:
    spec:
      chart: ingress-nginx
      version: ">=4.0.0 <5.0.0"
      sourceRef:
        kind: HelmRepository
        name: ingress-nginx
        namespace: flux-system
      interval: 12h           # how often to check for chart updates
  targetNamespace: ingress-nginx
  install:
    remediation:
      retries: 3
  upgrade:
    remediation:
      retries: 3
      remediateLastFailure: true
    cleanupOnFail: true
  values:
    controller:
      replicaCount: 2
  valuesFrom:
    - kind: ConfigMap
      name: ingress-values
      valuesKey: values.yaml
```

---

## Flux — dependsOn and Ordering

`dependsOn` between Flux Kustomizations or HelmReleases ensures one reconciles only after another reports `Ready`.

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: app-layer
  namespace: flux-system
spec:
  dependsOn:
    - name: infra-layer        # same namespace assumed
    - name: cert-manager
      namespace: flux-system
  path: ./apps
  ...
```

`dependsOn` does not create ordering within a single Kustomization — use Kustomize `components` or ArgoCD sync waves for that. `dependsOn` creates ordering between Flux objects.

**Drift detection:** Flux re-applies resources on every `interval`. A drift (manual kubectl change) is overwritten on the next reconcile. Flux does not distinguish "deliberate change" from "drift" — GitOps means Git wins.

---

## Flux — Image Automation

Flux image automation controllers update image tags in Git when new images are pushed.

```yaml
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: my-app
  namespace: flux-system
spec:
  image: 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app
  interval: 1m

---
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: my-app
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: my-app
  policy:
    semver:
      range: ">=1.0.0 <2.0.0"

---
apiVersion: image.toolkit.fluxcd.io/v1beta1
kind: ImageUpdateAutomation
metadata:
  name: flux-system
  namespace: flux-system
spec:
  interval: 1m
  sourceRef:
    kind: GitRepository
    name: gitops-repo
  git:
    checkout:
      ref:
        branch: main
    commit:
      author:
        email: fluxcdbot@example.com
        name: FluxCD
      messageTemplate: "chore: update {{range .Updated.Images}}{{println .}}{{end}}"
    push:
      branch: main
  update:
    path: ./apps
    strategy: Setters
```

In the manifest, mark the image field with a policy comment:
```yaml
image: my-app:v1.0.0 # {"$imagepolicy": "flux-system:my-app"}
```

---

## Sync-Failure Diagnosis Flow

A sync failure is a diagnosis problem, not a retry target. Never force-sync without understanding why it failed.

```
1. Read the sync/reconcile condition
   ArgoCD: argocd app get <name> --show-operation
   Flux:   kubectl get kustomization <name> -n flux-system -o jsonpath='{.status.conditions}'

2. Classify the failure:
   ┌─ "failed to render" / "error building templates"
   │   → Render error in the manifests themselves
   │   → Fix: check Helm values, Kustomize patches, variable substitution
   │
   ├─ "error applying" / "admission webhook denied"
   │   → Apply error — manifest is valid YAML but rejected at admission
   │   → Fix: check policy engine (Kyverno/OPA), PSA level, resource quotas
   │
   └─ "resource health" / "Degraded" / "Progressing timeout"
       → Resource exists but is unhealthy
       → Fix: kubectl describe / events on the specific resource

3. Fix Git, not the cluster.
   A manual kubectl patch on a GitOps-managed resource:
   - ArgoCD selfHeal=true: overwritten on next reconcile
   - Flux: overwritten on next interval
   Change Git → let the controller reconcile.

4. Verify the fix rendered correctly before re-syncing:
   kustomize build overlays/prod | kubectl apply --dry-run=server -f -
   helm template ... | kubectl apply --dry-run=server -f -
```

---

## ArgoCD vs Flux Selection Note

Both are production-grade. The choice is usually driven by existing tooling, not technical superiority.

| | ArgoCD | Flux |
|--|--------|------|
| **UI** | Rich web UI, RBAC per team | CLI-first; web UI via Weave GitOps |
| **Multi-tenancy** | AppProject RBAC | Separate namespaces + RBAC |
| **Ordering within sync** | Sync waves + hooks | `dependsOn` between objects |
| **Image automation** | External; needs image-updater plugin | Built-in image automation controllers |
| **Helm** | Native support in Application spec | HelmRelease CRD |
| **CRD surface** | Fewer CRDs | Larger CRD set (source, kustomize, helm, notification, image) |
| **Progressive delivery** | Argo Rollouts (separate install) | Flagger (separate install) |

For a platform team managing many teams' apps: ArgoCD ApplicationSet is the stronger fit. For a team that wants all config in Kubernetes YAML with no UI dependency: Flux is the cleaner fit.

---

## LLM Mistake Checklist

- Uses `helm.toolkit.fluxcd.io/v2beta1` for HelmRelease — deprecated; use `helm.toolkit.fluxcd.io/v2`.
- Uses `kustomize.toolkit.fluxcd.io/v1beta2` for Flux Kustomization — use `kustomize.toolkit.fluxcd.io/v1`.
- Sets `automated.selfHeal: false` without explaining that manual kubectl changes will persist as drift.
- Omits `prune: true` from ArgoCD automated sync or Flux Kustomization — removed resources in Git stay in the cluster as orphans.
- Puts the ArgoCD Application in the `production` namespace instead of `argocd` — Applications must live in the ArgoCD namespace (or a configured app-in-any-namespace setup).
- Uses sync waves to order resources within the same wave — waves only order between wave numbers; resources within the same wave have no guaranteed order.
- Recommends `argocd app sync <name>` to fix a `Degraded` status without first diagnosing why the resource is degraded — sync will just fail again.
- Emits `argocd.argoproj.io/sync-wave` as an integer annotation value — annotation values are strings; use `"-1"` not `-1`.
- Confuses ArgoCD `ignoreDifferences` with Flux drift detection — they are different tools; `ignoreDifferences` is ArgoCD-only.
- Uses `dependsOn` inside a Kustomize overlay to order resources — `dependsOn` is a Flux object-level field; within a single Kustomize overlay, use ArgoCD sync waves or Kustomize ordering.
- Recommends manually editing cluster resources to fix a sync failure when `selfHeal: true` — the fix must go into Git; manual changes will be reverted.
- Emits `argocd.argoproj.io/hook: PreSync` without a `hook-delete-policy` — completed hook pods accumulate in the cluster.
- Applies large CRD bundles (cert-manager, Prometheus Operator) without `ServerSideApply=true` — they exceed the 256 KB last-applied-configuration annotation limit and fail with `metadata.annotations: Too long`.

---

**Back to:** [Main Skill File](../SKILL.md)
