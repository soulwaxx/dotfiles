# Workloads

> **Part of:** [kubernetes-skill](../SKILL.md)
> **Purpose:** Controllers, probes, resources/QoS, securityContext, rollout strategy, API-version guards

---

## TOC

1. [Controller Selection](#controller-selection)
2. [Probe Matrix](#probe-matrix)
3. [Resource Requests, Limits, and QoS](#resource-requests-limits-and-qos)
4. [SecurityContext Baseline](#securitycontext-baseline)
5. [Rollout Strategy](#rollout-strategy)
6. [API-Version Guard Table](#api-version-guard-table)
7. [LLM Mistake Checklist](#llm-mistake-checklist)

---

## Controller Selection

| Controller | Use when | Key invariant |
|------------|----------|---------------|
| `Deployment` | stateless services, multiple identical replicas, horizontal scale | pods are fungible; any replica can serve any request |
| `StatefulSet` | databases, message brokers, anything needing stable network identity or ordered startup | each pod gets a stable DNS name `<name>-<ordinal>.<svc>` and a dedicated PVC |
| `DaemonSet` | per-node agents — log collectors, CSI plugins, network CNI, Karpenter node-problem-detector | runs exactly one pod per node (or per matching node); not for user workloads |
| `Job` | one-shot batch, database migrations, report generation | runs to completion; set `backoffLimit` and `activeDeadlineSeconds` |
| `CronJob` (`batch/v1`) | scheduled batch — backups, aggregations, cleanup | wraps a `Job` spec; set `concurrencyPolicy: Forbid` unless jobs are idempotent, `startingDeadlineSeconds` to cap missed-run catchup |

**StatefulSet vs Deployment with a headless service:** if the app uses peer discovery via DNS (Kafka, Cassandra, Elasticsearch), it needs a StatefulSet. If it just needs persistent storage per replica, a StatefulSet is still correct — a Deployment gives every replica the same PVC claim name, which fails with `ReadWriteOnce` volumes.

```yaml
# CronJob — batch/v1 (Kubernetes 1.21+ GA)
apiVersion: batch/v1
kind: CronJob
metadata:
  name: db-backup
  namespace: ops
spec:
  schedule: "0 2 * * *"
  concurrencyPolicy: Forbid
  startingDeadlineSeconds: 300
  jobTemplate:
    spec:
      backoffLimit: 2
      activeDeadlineSeconds: 1800
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: backup
              image: backup-tool:1.2.3@sha256:<digest>
              resources:
                requests:
                  cpu: 100m
                  memory: 128Mi
```

---

## Probe Matrix

Three probes, three distinct purposes. Omitting one has a specific failure mode.

| Probe | Purpose | Failure mode if omitted | Typical action |
|-------|---------|-------------------------|----------------|
| `startupProbe` | Lets a slow-starting container finish initialising before other probes fire | `livenessProbe` kills the pod during a legitimate slow start, causing a restart loop | `httpGet` or `exec`; fires only until success |
| `readinessProbe` | Gates traffic; pod removed from Service endpoints when failing | Traffic reaches a pod that is not ready; broken pod still counts as available in rollout progress | `httpGet /ready`; fires continuously |
| `livenessProbe` | Restarts a wedged/deadlocked process | Stuck pod never restarts; workload silently dead | `httpGet /healthz`; fires continuously |

**Tuning fields:**

```yaml
startupProbe:
  httpGet:
    path: /healthz
    port: 8080
  failureThreshold: 30      # 30 × periodSeconds = max startup window
  periodSeconds: 5          # check every 5 s; total window = 150 s
  timeoutSeconds: 3

readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5    # head start after container starts (post-startup)
  periodSeconds: 10
  failureThreshold: 3       # 3 consecutive failures → remove from endpoints
  successThreshold: 1       # 1 success → re-add to endpoints

livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 15   # give app time to pass startup before liveness fires
  periodSeconds: 20
  failureThreshold: 3
  timeoutSeconds: 5
```

**Tuning guidance:**

- `failureThreshold × periodSeconds` is the total tolerance window. Three failures at 10 s = 30 s before action. Make this large enough to survive GC pauses and transient upstream latency.
- `startupProbe.failureThreshold` is the slow-start budget: 30 × 5 s = 150 s. Once the startup probe succeeds, Kubernetes switches to `readiness` and `liveness`.
- Liveness `initialDelaySeconds` should be at least as long as the startup window to avoid a race. If you have a `startupProbe`, set `initialDelaySeconds: 0` on liveness — the startup probe handles the delay.
- Never use `exec` probes against shell scripts that fork subprocesses — zombie accumulation will OOM the pod over time.

---

## Resource Requests, Limits, and QoS

### The three QoS classes

Kubernetes assigns QoS at scheduling time based on requests/limits. The class determines eviction priority under node memory pressure.

| QoS class | Condition | Eviction order (first evicted) |
|-----------|-----------|-------------------------------|
| **BestEffort** | No `requests` or `limits` set at all | Evicted first |
| **Burstable** | `requests` set; `limits` either unset or `limits > requests` | Evicted second |
| **Guaranteed** | `requests == limits` for **every** resource on **every** container | Evicted last; also pinned to CPUs on nodes with static CPU policy |

Production workloads must be at minimum **Burstable**. `BestEffort` pods are the first to go during any node pressure event.

### CPU limit throttling tradeoff

CPU limits are not eviction-related — they throttle via the Linux CFS scheduler. A pod at its CPU limit gets throttled even when the node has spare capacity.

**Rule:** set `resources.requests` always (drives scheduling and QoS). Set `resources.limits.cpu` deliberately — omit it if the workload has bursty traffic patterns and the node has headroom. Memory limits should always be set because OOM kills are preferable to slow node degradation.

```yaml
resources:
  requests:
    cpu: 250m      # scheduling and QoS anchor
    memory: 256Mi
  limits:
    # cpu omitted intentionally — bursty API service; throttling hurts p99 more than OOM risk
    memory: 512Mi  # OOM kill preferred over node pressure cascade
```

For **Guaranteed** QoS (CPU-sensitive, latency-critical):

```yaml
resources:
  requests:
    cpu: "2"
    memory: 4Gi
  limits:
    cpu: "2"       # equal to requests → Guaranteed
    memory: 4Gi
```

---

## SecurityContext Baseline

The `restricted` Pod Security Admission level requires all of these. Apply at the pod level where a field is pod-scoped, and at the container level where it is container-scoped. Fields below are the minimum to pass `restricted`.

```yaml
# Pod-level
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000          # non-zero UID; must match image's USER directive
    runAsGroup: 1000
    fsGroup: 1000            # group owns mounted volumes
    seccompProfile:
      type: RuntimeDefault   # required for restricted; enables seccomp filtering

  containers:
    - name: app
      securityContext:
        allowPrivilegeEscalation: false   # no setuid; no sudo
        readOnlyRootFilesystem: true      # immutable root — write to mounted volumes only
        runAsNonRoot: true
        capabilities:
          drop: ["ALL"]       # drop every capability; add back only what's needed
          # add: ["NET_BIND_SERVICE"]  # example: if port < 1024 required
        seccompProfile:
          type: RuntimeDefault
```

**Why each field:**

- `runAsNonRoot: true` — container process may not run as UID 0; admission rejects if image USER is root.
- `readOnlyRootFilesystem: true` — prevents an attacker from writing to `/tmp`, cron, or ld.so. App must write to an `emptyDir` or a mounted volume.
- `allowPrivilegeEscalation: false` — blocks `execve` with setuid bit and `no_new_privs` syscall flag.
- `capabilities.drop: ["ALL"]` — starts from zero. The restricted profile forbids any `add`.
- `seccompProfile: RuntimeDefault` — uses the container runtime's built-in syscall filter; required for `restricted`.

**Temporary writable dir for an otherwise restricted container:**

```yaml
volumes:
  - name: tmp
    emptyDir: {}
containers:
  - name: app
    volumeMounts:
      - name: tmp
        mountPath: /tmp
    securityContext:
      readOnlyRootFilesystem: true
```

---

## Rollout Strategy

### Deployment — RollingUpdate

```yaml
spec:
  replicas: 3
  minReadySeconds: 30          # pod must be ready this long before counted as available
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1              # at most 1 extra pod above desired (absolute or %)
      maxUnavailable: 0        # no replicas down during rollout — zero-downtime
```

`maxUnavailable: 0` + `maxSurge: 1` is the zero-downtime pattern: the new pod must become ready before any old pod is terminated. `minReadySeconds` adds a readiness-stable window before the old pod exits — catches flapping readiness probes.

For fast rollouts with tolerable brief reduction: `maxSurge: 25%`, `maxUnavailable: 25%`.

**Rollout commands:**

```bash
kubectl rollout status deployment/<name> -n <ns> --timeout=5m
kubectl rollout history deployment/<name> -n <ns>
kubectl rollout undo deployment/<name> -n <ns>          # rollback to previous revision
kubectl rollout undo deployment/<name> -n <ns> --to-revision=3
```

### StatefulSet

```yaml
spec:
  updateStrategy:
    type: RollingUpdate   # default: updates ordinals from highest to lowest
    rollingUpdate:
      maxUnavailable: 1   # Kubernetes 1.24+: update N at a time, not one-by-one
      # partition: 2      # optional: only update pods with ordinal >= partition (canary)
```

`OnDelete` strategy: Kubernetes does not auto-roll; pods update only when manually deleted. Use for databases where you want explicit control over each ordinal's upgrade.

### DaemonSet

```yaml
spec:
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 0
      maxUnavailable: 1   # update one node at a time
```

---

## API-Version Guard Table

Check these before emitting a manifest. Wrong `apiVersion` causes `no matches for kind` at apply time or silent schema validation failure.

| Kind | Correct apiVersion | Removed / deprecated | Notes |
|------|--------------------|----------------------|-------|
| `Deployment` | `apps/v1` | `extensions/v1beta1` removed 1.16 | |
| `StatefulSet` | `apps/v1` | `apps/v1beta1` removed 1.16 | |
| `DaemonSet` | `apps/v1` | `extensions/v1beta1` removed 1.16 | |
| `Job` | `batch/v1` | `batch/v1beta1` removed 1.25 | |
| `CronJob` | `batch/v1` | `batch/v1beta1` removed 1.25 | GA in 1.21 |
| `HorizontalPodAutoscaler` | `autoscaling/v2` | `autoscaling/v2beta2` removed 1.26 | |
| `PodDisruptionBudget` | `policy/v1` | `policy/v1beta1` removed 1.25 | |
| `PodSecurityPolicy` | — | **Removed 1.25** | Use Pod Security Admission |
| `Ingress` | `networking.k8s.io/v1` | `extensions/v1beta1` removed 1.22 | |
| `NetworkPolicy` | `networking.k8s.io/v1` | — | |
| `HTTPRoute` (Gateway API) | `gateway.networking.k8s.io/v1` | — | v1.5 GA Feb 2026 |
| `NodePool` (Karpenter) | `karpenter.sh/v1` | `karpenter.sh/v1beta1` dropped after v1.1 | |
| `EC2NodeClass` (Karpenter) | `karpenter.k8s.aws/v1` | `karpenter.k8s.aws/v1beta1` dropped after v1.1 | EKS-specific |

---

## LLM Mistake Checklist

- Emits `PodSecurityPolicy` — it was removed in Kubernetes 1.25; use Pod Security Admission namespace labels.
- Uses `autoscaling/v2beta2` for HPA — removed in 1.26; use `autoscaling/v2`.
- Uses `policy/v1beta1` for PodDisruptionBudget — removed in 1.25; use `policy/v1`.
- Uses `batch/v1beta1` for CronJob — removed in 1.25; use `batch/v1`.
- Sets `readinessProbe` identical to `livenessProbe` — they have different purposes; a failing readiness probe should not restart the pod.
- Omits `startupProbe` for slow-starting containers and sets a high `initialDelaySeconds` on liveness instead — the correct fix is a `startupProbe`.
- Sets `resources.requests` without `resources.limits.memory`, leaving OOM kills ungated.
- Omits `resources.requests` entirely — BestEffort QoS, first to be evicted.
- Sets `limits == requests` for CPU on a latency-sensitive service without noting the throttling consequence.
- Omits `seccompProfile: RuntimeDefault` from the securityContext — manifests will fail `restricted` PSA.
- Sets `capabilities.drop: ["ALL"]` at pod-level `securityContext` — `capabilities` is a container-level field only; the pod-level field is ignored.
- Uses `extensions/v1beta1` for Deployment, Ingress, or DaemonSet — removed since 1.16/1.22.
- Emits `maxUnavailable: 0` without also bumping `maxSurge`, resulting in a rollout that can never make progress (both constraints block all movement).
- Uses `concurrencyPolicy: Allow` on a CronJob for a non-idempotent job without noting the overlap risk.
- Emits `karpenter.sh/v1beta1` for NodePool or `karpenter.k8s.aws/v1beta1` for EC2NodeClass — these are dropped after Karpenter v1.1; use `v1` for both.

---

**Back to:** [Main Skill File](../SKILL.md)
