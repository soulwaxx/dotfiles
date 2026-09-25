# Scaling & Reliability

> **Part of:** [kubernetes-skill](../SKILL.md)
> **Purpose:** HPA, VPA, PodDisruptionBudget, topology spread, Karpenter v1, cluster autoscaler

---

## TOC

1. [HPA — autoscaling/v2](#hpa--autoscalingv2)
2. [VPA — When and When Not](#vpa--when-and-when-not)
3. [PodDisruptionBudget — policy/v1](#poddisruptionbudget--policyv1)
4. [Topology Spread Constraints](#topology-spread-constraints)
5. [Karpenter v1 — NodePool and EC2NodeClass](#karpenter-v1--nodepool-and-ec2nodeclass)
6. [Cluster Autoscaler vs Karpenter](#cluster-autoscaler-vs-karpenter)
7. [LLM Mistake Checklist](#llm-mistake-checklist)

---

## HPA — autoscaling/v2

`autoscaling/v2` is the GA API since Kubernetes 1.23. `v2beta2` was removed in 1.26.

### Resource metrics (CPU/memory)

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-server
  namespace: production
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api-server
  minReplicas: 3
  maxReplicas: 20
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 60   # % of the pod's requests.cpu
    - type: Resource
      resource:
        name: memory
        target:
          type: AverageValue
          averageValue: 400Mi      # absolute value, not percentage
```

HPA targets a utilization percentage of `requests`, not `limits`. If a pod has no CPU request, HPA cannot compute utilization — it will report "unknown" and refuse to scale. Always set `resources.requests.cpu`.

### Custom and external metrics

```yaml
  metrics:
    - type: Pods
      pods:
        metric:
          name: http_requests_per_second   # served by custom-metrics-apiserver
        target:
          type: AverageValue
          averageValue: "500"
    - type: External
      external:
        metric:
          name: sqs_queue_depth            # served by external-metrics-apiserver
          selector:
            matchLabels:
              queue: order-processing
        target:
          type: AverageValue
          averageValue: "100"
```

### Behavior stabilization windows

Without `behavior`, HPA scales down aggressively: a traffic spike that clears will collapse the replica count immediately. Stabilization windows smooth this.

```yaml
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300   # hold the scale-down decision for 5 min
      policies:
        - type: Percent
          value: 25
          periodSeconds: 60             # remove at most 25% per minute
        - type: Pods
          value: 2
          periodSeconds: 60             # or at most 2 pods per minute
      selectPolicy: Min                 # apply the more conservative policy
    scaleUp:
      stabilizationWindowSeconds: 0    # scale up immediately
      policies:
        - type: Percent
          value: 100
          periodSeconds: 30            # can double replica count every 30 s
```

`selectPolicy: Min` picks the policy that results in the fewest replicas changed (most conservative). Use `Max` to pick the most aggressive.

---

## VPA — When and When Not

VPA (`VerticalPodAutoscaler`) adjusts a pod's CPU/memory requests based on observed usage. In `Auto` mode it evicts and restarts pods to apply the recommendation.

**Conflict with HPA on CPU:** HPA on CPU utilization reads the current `requests.cpu` as its denominator. VPA changing `requests.cpu` shifts that denominator, causing HPA to oscillate. Do not run both against the same resource metric on the same workload.

| VPA mode | What it does | Safe to pair with HPA? |
|----------|-------------|----------------------|
| `Off` | Computes recommendations, applies nothing | Yes — read-only |
| `Initial` | Sets requests at pod creation only | Yes — no live mutation |
| `Auto` | Evicts pods to apply recommendations | Only if HPA uses custom/external metrics, not CPU |

Use VPA `Off` for sizing insights on a new workload. Use VPA `Initial` for batch jobs where right-sizing at startup is sufficient. Avoid VPA `Auto` + HPA CPU on the same Deployment in production.

---

## PodDisruptionBudget — policy/v1

PDB protects availability during voluntary disruptions: `kubectl drain`, node upgrades, cluster autoscaler scale-down, and Karpenter consolidation. It does not protect against involuntary disruptions (OOMKill, hardware failure).

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: api-server-pdb
  namespace: production
spec:
  minAvailable: 2          # at least 2 pods must remain up during disruption
  # maxUnavailable: 1      # alternative: at most 1 pod may be down at once
  selector:
    matchLabels:
      app: api-server
```

Use `minAvailable` when you know the floor (e.g., 2 of 3 replicas must serve). Use `maxUnavailable` when you want relative disruption tolerance regardless of replica count.

**Interaction with drain and Karpenter consolidation:**

- `kubectl drain` and Karpenter disruption both respect PDB. If evicting a pod would violate the budget, the drain/consolidation blocks until another pod is ready.
- A PDB with `minAvailable` equal to the current replica count (e.g., `minAvailable: 3` on a 3-replica deployment) makes node drain impossible — it can never be satisfied. Leave at least one pod disruption budget.
- A Deployment's `maxUnavailable` in its rolling-update strategy is separate from the PDB. The PDB governs voluntary eviction; the rolling-update `maxUnavailable` governs how the Deployment controller replaces pods.

**Verify a drain respects your PDB:**
```bash
kubectl drain <node> --dry-run --ignore-daemonsets --delete-emptydir-data
# Look for "cannot evict pod as it would violate the pod's disruption budget" lines
```

---

## Topology Spread Constraints

Topology spread distributes pods across failure domains. NetworkPolicy and PDB can protect pods — topology spread ensures they aren't all in the same zone.

```yaml
spec:
  topologySpreadConstraints:
    - maxSkew: 1                          # at most 1 more pod in any zone than any other
      topologyKey: topology.kubernetes.io/zone
      whenUnsatisfiable: DoNotSchedule   # hard constraint: prefer ScheduleAnyway to soften
      labelSelector:
        matchLabels:
          app: api-server
      minDomains: 3                       # require at least 3 zones to be present (Kubernetes 1.25+)
    - maxSkew: 1
      topologyKey: kubernetes.io/hostname
      whenUnsatisfiable: ScheduleAnyway  # soft: spread across hosts but don't block scheduling
      labelSelector:
        matchLabels:
          app: api-server
```

**`whenUnsatisfiable` tradeoff:**
- `DoNotSchedule` — pods stay `Pending` if the constraint cannot be satisfied. Use for HA workloads in prod where zone-spread is non-negotiable.
- `ScheduleAnyway` — constraint is advisory; pods schedule even if skew is exceeded. Use for host-spread (less critical) or when zone counts may temporarily drop below `minDomains`.

**`minDomains`** (Kubernetes 1.25+, GA 1.28): specifies the minimum number of qualifying topology domains. Without it, if only 1 zone is available, `maxSkew: 1` is trivially satisfied — all pods land in one zone. Set `minDomains` to the zone count in your region to catch single-zone degradation.

**EKS note:** EKS node groups and Karpenter both label nodes with `topology.kubernetes.io/zone`. No extra setup needed for zone-based spread.

---

## Karpenter v1 — NodePool and EC2NodeClass

> **EKS-specific.** Karpenter v1.0 is GA. `karpenter.sh/v1beta1` and `karpenter.k8s.aws/v1beta1` are dropped after Karpenter v1.1.

### NodePool (karpenter.sh/v1)

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: general
spec:
  template:
    metadata:
      labels:
        intent: apps
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand", "spot"]
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["m", "c", "r"]
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["3"]
      expireAfter: 720h           # nodes rotate every 30 days; keeps AMIs current
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 1m          # wait 1 min after underutilization before consolidating
    budgets:
      - nodes: "10%"              # max 10% of nodes can be disrupted simultaneously
  limits:
    cpu: "200"
    memory: 800Gi
```

### EC2NodeClass (karpenter.k8s.aws/v1)

```yaml
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiSelectorTerms:
    - alias: al2023@latest         # Amazon Linux 2023, latest patched AMI
  role: KarpenterNodeRole          # instance profile role; must trust the Karpenter node IAM
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: my-cluster   # subnet must carry this tag
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: my-cluster
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 50Gi
        volumeType: gp3
        encrypted: true
```

### `do-not-disrupt` annotation

Prevent Karpenter from evicting a specific pod during consolidation:

```yaml
metadata:
  annotations:
    karpenter.sh/do-not-disrupt: "true"
```

Apply to pods running stateful workloads or long-running batch jobs that cannot tolerate mid-run eviction. Karpenter will not consolidate a node that has any pod carrying this annotation.

### Subnet and security group discovery

Karpenter finds subnets and security groups by tag. Both must carry `karpenter.sh/discovery: <cluster-name>`. If the LB isn't provisioning nodes or nodes land in the wrong subnet, check these tags first.

```bash
aws ec2 describe-subnets \
  --filters "Name=tag:karpenter.sh/discovery,Values=my-cluster" \
  --query 'Subnets[*].{ID:SubnetId,AZ:AvailabilityZone,Tags:Tags}'
```

---

## Cluster Autoscaler vs Karpenter

| | Cluster Autoscaler | Karpenter |
|--|---------------------|-----------|
| **Provisioning model** | Pre-defined node groups; picks the group that fits the pending pod | Directly provisions EC2 instances matching the pod's requirements |
| **Speed** | Minutes (ASG warm-up) | ~30–60 s (bypasses ASG) |
| **Bin-packing** | Group-level; limited cross-group optimization | Per-pod; selects optimal instance type |
| **Spot diversification** | Requires separate node groups per instance type | Single NodePool handles multiple types natively |
| **EKS managed node groups** | Required if using EKS MNG | Not compatible with MNG; uses standalone node bootstrap |
| **Migration path** | Available today on all EKS clusters | Recommended for new clusters on EKS 1.23+ |

For new EKS clusters: use Karpenter. For existing clusters with complex managed node group configurations: Cluster Autoscaler until migration is planned. The two should not both be managing the same nodes.

---

## LLM Mistake Checklist

- Uses `autoscaling/v2beta2` for HPA — removed in 1.26; correct is `autoscaling/v2`.
- Configures HPA on CPU without the Deployment having `resources.requests.cpu` set — HPA cannot compute utilization, reports "unknown", will not scale.
- Runs VPA in `Auto` mode and HPA on CPU for the same Deployment — VPA mutations destabilize HPA's denominator.
- Sets `minAvailable` equal to the total replica count in the PDB — makes node drain impossible.
- Emits PDB with `policy/v1beta1` — removed in 1.25; use `policy/v1`.
- Omits `topologySpreadConstraints` entirely and suggests `podAntiAffinity` for zone spread — topology spread is the correct modern API; anti-affinity still works but doesn't handle imbalanced clusters well.
- Emits `karpenter.sh/v1beta1` or `karpenter.k8s.aws/v1beta1` for NodePool/EC2NodeClass — dropped after Karpenter v1.1; use `karpenter.sh/v1` and `karpenter.k8s.aws/v1`.
- Uses `consolidationPolicy: WhenEmpty` when the user wants cost efficiency — `WhenEmptyOrUnderutilized` consolidates both empty and underutilized nodes.
- Omits `expireAfter` on NodePool — nodes never rotate, AMIs go stale, security patches miss.
- Suggests Cluster Autoscaler and Karpenter managing the same nodes simultaneously — they conflict.
- Sets `minDomains` without noting it requires Kubernetes 1.25+ and that it is only GA in 1.28.
- Emits HPA and PDB for a single-replica Deployment — a PDB with `minAvailable: 1` on a 1-replica deployment blocks all voluntary disruption; scale to ≥2 replicas.

---

**Back to:** [Main Skill File](../SKILL.md)
