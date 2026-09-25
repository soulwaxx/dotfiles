---
name: kubernetes-skill
disable-model-invocation: true
description: "Consult before writing, reviewing, or debugging any Kubernetes, Helm, Kustomize, or ArgoCD/Flux YAML — including when the user only shows a manifest, values.yaml, kustomization, Application, HelmRelease, NetworkPolicy, Ingress, or Gateway without saying \"Kubernetes\". Also for diagnosing scheduling failures, hung rollouts, failed helm upgrades, OOMKills/evictions, and GitOps sync/drift issues. Not for cluster substrate provisioning (Terraform), broad infra PR reviews (infra-review), or decision records."
---

# Kubernetes Skill for Claude

Diagnose-first guidance for Kubernetes, Helm, Kustomize, and GitOps delivery. This core file is a workflow; depth lives in `references/` loaded on demand. The discipline is the same as the Terraform skill: name the risk before you generate the YAML.

## House Defaults

Assume this context unless the user says otherwise, and still name the assumption in the Response Contract.

- **Distribution**: Amazon EKS is primary. Prefer EKS-native integrations — AWS Load Balancer Controller for Ingress/Gateway, EBS/EFS CSI for storage, Karpenter for compute, EKS Pod Identity for workload IAM. Flag where guidance is EKS-specific vs portable so the manifest survives a move to another distro.
- **Workload identity**: EKS Pod Identity is the default for new service accounts; IRSA remains valid for existing clusters and is **required** for Fargate (the Pod Identity Agent is a node DaemonSet). Never bake static AWS keys into a Pod.
- **Delivery**: GitOps owns in-cluster state. ArgoCD or Flux reconciles from Git; nobody runs `kubectl apply` against prod by hand. Terraform provisions the cluster substrate (VPC, node IAM, addons), not application manifests — the boundary mirrors the Terraform skill.
- **Packaging**: Helm for third-party and versioned releases; Kustomize overlays for environment deltas on first-party manifests. Don't template what an overlay can patch, and don't overlay what genuinely needs Go templating.
- **API currency**: Kubernetes APIs and CRDs drift fast. Verify the apiVersion against the target cluster's minor version before emitting — `PodSecurityPolicy` is gone (1.25), HPA is `autoscaling/v2`, PDB is `policy/v1`, Gateway API is `gateway.networking.k8s.io/v1`.

## Response Contract

Every Kubernetes/Helm/Kustomize/GitOps response must include:

1. **Assumptions & version floor** — cluster distro and minor version, packaging tool (raw/Helm/Kustomize), delivery path (kubectl/ArgoCD/Flux), namespace and its Pod Security Admission level, environment criticality. State assumptions explicitly when the user did not provide them.
2. **Risk category addressed** — one or more of: scheduling/eviction, rollout safety, RBAC/secret exposure, network reachability, resource starvation, drift/sync failure, chart/overlay correctness, API deprecation.
3. **Chosen remediation & tradeoffs** — what was chosen, what was traded off, why.
4. **Validation plan** — exact commands tailored to tool and risk tier (`kubeconform`, `kubectl --dry-run=server`, `helm lint`/`template`, `kustomize build`, policy check).
5. **Rollout & rollback notes** — for any change that mutates running workloads: rollout strategy, how to detect a bad rollout, how to undo it, what evidence to keep.

Never recommend a manual `kubectl apply`/`delete` against a GitOps-managed prod namespace — the controller will revert it or you will cause drift. Change Git, let the controller reconcile.

## Workflow

1. **Capture cluster context** — distro+version, packaging tool, delivery path, target namespace PSA level, environment criticality.
2. **Diagnose failure mode(s)** using the routing table below. If intent spans categories, load both references.
3. **Load only the matching reference file(s)** — do not preload depth the task does not need.
4. **Propose fix with risk controls** — why it addresses the mode, what could still go wrong, the guardrail (probe/PDB/policy/approval).
5. **Generate artifacts** — manifests, chart edits, overlays, ArgoCD/Flux resources, with the correct apiVersion for the target version.
6. **Validate before finalizing** — run the validation commands for the risk tier.
7. **Emit the Response Contract** at the end.

## Diagnose Before You Generate

| Failure category | Symptoms | Primary references |
| ------------------ | ---------- | -------------------- |
| **Scheduling / eviction** | `Pending` pods, `OOMKilled`, `Evicted`, no nodes provisioned, spread imbalance | [Scaling & Reliability](references/scaling-reliability.md), [Workloads](references/workloads.md) |
| **Rollout safety** | Rollout hangs, all replicas down at once, no `readinessProbe`, missing PDB, failed `StatefulSet` ordinal | [Workloads](references/workloads.md), [Scaling & Reliability](references/scaling-reliability.md) |
| **RBAC / secret exposure** | Over-broad `ClusterRole`, secrets in env/ConfigMap/Git, `automountServiceAccountToken`, privileged container | [Security](references/security.md) |
| **Network reachability** | Service has no endpoints, Ingress 502/504, NetworkPolicy blackhole, cross-namespace deny | [Networking & EKS](references/networking-eks.md), [Security](references/security.md) |
| **Resource starvation** | Noisy-neighbour, throttling, `BestEffort` QoS in prod, no `requests`, HPA not scaling | [Scaling & Reliability](references/scaling-reliability.md) |
| **Drift / sync failure** | ArgoCD `OutOfSync`/`Degraded`, Flux `Kustomization` not ready, `HelmRelease` upgrade retries exhausted, prune deleted live resources | [GitOps](references/gitops.md) |
| **Chart correctness** | `helm template` wrong output, values not overriding, `nil` map deref, hook ordering, CRD install race | [Helm](references/helm.md) |
| **Overlay correctness** | Patch not applied, wrong target, base mutated, generator name-suffix surprises | [Kustomize](references/kustomize.md) |
| **API deprecation / upgrade** | `no matches for kind`, removed apiVersion, admission rejects on upgrade | [Validation](references/validation.md), [Workloads](references/workloads.md) |
| **EKS integration** | IRSA/Pod Identity auth fails, LB not created, CSI volume won't attach, Karpenter mis-provisions | [Networking & EKS](references/networking-eks.md) |
| **Validation / policy gaps** | No schema check in CI, no policy gate, manifests fail only at apply | [Validation](references/validation.md) |

## Out Of Scope — Route Elsewhere

Triggering lives in this skill's description. Once active, route away when the task is: basic `kubectl` syntax Claude already knows; cluster substrate provisioning — VPC, node IAM, addon installation — which belongs in the Terraform skill; or a pure cloud-API question unrelated to in-cluster objects.

## Core Principles

### Packaging decision — Helm vs Kustomize vs raw

| Situation | Use | Why |
| ----------- | ----- | ----- |
| Third-party software, versioned, many knobs | **Helm** | Upstream ships a chart; you consume a release artifact |
| First-party app, environment deltas (image tag, replicas, resources) | **Kustomize** | Overlays patch a base without templating logic |
| Conditional/loop logic over values, distributable to others | **Helm** | Go templating expresses what patches can't |
| One environment, no variation | **raw manifests** | Don't add a tool for nothing |

Anti-pattern: deep Go templating to express what a Kustomize patch does declaratively, or a Kustomize overlay fighting a chart that already exposes the value. Helm charts can be post-rendered with Kustomize when you need both — see [Helm](references/helm.md) and [Kustomize](references/kustomize.md).

### Every workload carries its safety contract

A production workload manifest is incomplete without:

- **`resources.requests` and `limits`** — requests drive scheduling and QoS; missing requests give `BestEffort` QoS, first to be evicted. CPU limits cause throttling — set requests always, limits deliberately.
- **`readinessProbe`** — without it, a rollout sends traffic to a pod that isn't ready and a broken pod still counts as available.
- **`livenessProbe` and `startupProbe`** — liveness restarts a wedged pod; startup protects a slow starter from liveness killing it during boot.
- **A `PodDisruptionBudget`** — without it a node drain or cluster upgrade can take every replica down at once.
- **A non-root, read-only `securityContext`** — `runAsNonRoot`, `readOnlyRootFilesystem`, dropped capabilities; required to pass the `restricted` Pod Security Admission level.

See [Workloads](references/workloads.md) for the probe-tuning matrix and QoS rules, [Scaling & Reliability](references/scaling-reliability.md) for PDB and spread, [Security](references/security.md) for the securityContext baseline.

### GitOps is the only writer

In-cluster desired state lives in Git. The controller reconciles it. Three consequences:

- A manual `kubectl apply` to a managed namespace either gets reverted (self-heal on) or becomes silent drift (self-heal off). Change Git.
- Ordering is declarative: ArgoCD sync waves (`argocd.argoproj.io/sync-wave`), Flux `dependsOn`. Don't encode ordering in apply scripts.
- A failed sync is a diagnosis, not a retry target — read the controller's condition before re-syncing. See [GitOps](references/gitops.md).

### Validate before the cluster does

Catch errors left of apply: `kubeconform` for schema, `kubectl --dry-run=server` for admission, `helm lint`/`template` and `kustomize build` for render correctness, a policy engine (Kyverno/OPA) for org rules. Wire these into CI so a bad manifest fails the PR, not the rollout. See [Validation](references/validation.md). CI must own the enforceable gate.

## Reference Files

Progressive disclosure — essentials here, depth on demand:

- [Workloads](references/workloads.md) — controllers, probes, resources/QoS, securityContext baseline, rollout strategy, API-version guards
- [Scaling & Reliability](references/scaling-reliability.md) — HPA (`autoscaling/v2`)/VPA, PDB, topology spread, Karpenter v1, cluster autoscaler
- [Helm](references/helm.md) — chart structure, values contracts, templating pitfalls, hooks, OCI registries, lint/template/test, post-rendering
- [Kustomize](references/kustomize.md) — bases/overlays, strategic vs JSON6902 patches, components, generators, build
- [GitOps](references/gitops.md) — ArgoCD (Application, app-of-apps, sync waves, sync windows, self-heal, drift) and Flux (Kustomization, `HelmRelease` v2, `dependsOn`, image automation), sync-failure diagnosis
- [Security](references/security.md) — RBAC least-privilege, Pod Security Admission, securityContext, NetworkPolicy, secrets (External Secrets/SOPS/sealed-secrets), admission policy
- [Networking & EKS](references/networking-eks.md) — Services, Ingress, Gateway API v1.5, AWS Load Balancer Controller, IRSA vs Pod Identity, CSI drivers, Karpenter integration
- [Validation](references/validation.md) — kubeconform, server dry-run, helm/kustomize render checks, Kyverno/OPA/Polaris/Trivy, CI wiring
