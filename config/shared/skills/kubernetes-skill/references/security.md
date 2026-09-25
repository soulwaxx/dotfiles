# Security

> **Part of:** [kubernetes-skill](../SKILL.md)
> **Purpose:** RBAC, Pod Security Admission, securityContext, NetworkPolicy, secrets management, admission policy

---

## TOC

1. [RBAC — Roles and Bindings](#rbac--roles-and-bindings)
2. [ServiceAccount Tokens](#serviceaccount-tokens)
3. [Pod Security Admission](#pod-security-admission)
4. [SecurityContext Baseline](#securitycontext-baseline)
5. [NetworkPolicy — Default-Deny Pattern](#networkpolicy--default-deny-pattern)
6. [Secrets — Never in Git Plaintext](#secrets--never-in-git-plaintext)
7. [Image Provenance](#image-provenance)
8. [Admission Policy Engines](#admission-policy-engines)
9. [LLM Mistake Checklist](#llm-mistake-checklist)

---

## RBAC — Roles and Bindings

### Role vs ClusterRole

| | Role | ClusterRole |
|--|------|-------------|
| **Scope** | Single namespace | Cluster-wide |
| **Use for** | Workload service accounts that only need access within their namespace | Node-scoped resources, CRDs, cluster-level reads, cross-namespace controllers |
| **Bound by** | `RoleBinding` | `ClusterRoleBinding` (cluster-wide) or `RoleBinding` (namespace-scoped) |

A `ClusterRole` bound by a `RoleBinding` (not `ClusterRoleBinding`) grants access only within that namespace. This is the preferred pattern for workloads that need a ClusterRole's resource definitions but should not have cluster-wide access.

### Least-privilege Role

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: configmap-reader
  namespace: production
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list", "watch"]   # read-only; no create/update/delete
    resourceNames: ["app-config"]     # further narrow to a specific resource name
```

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: app-configmap-reader
  namespace: production
subjects:
  - kind: ServiceAccount
    name: api-server
    namespace: production
roleRef:
  kind: Role
  apiVersion: rbac.authorization.k8s.io/v1
  name: configmap-reader
```

**Wildcard rules are never least-privilege:**
```yaml
# ❌ Grants everything in the API group
rules:
  - apiGroups: ["*"]
    resources: ["*"]
    verbs: ["*"]
```

Do not bind to `cluster-admin` unless the workload is a cluster-management operator. Audit bindings regularly:

```bash
kubectl auth can-i --list --as=system:serviceaccount:production:api-server
kubectl get rolebindings,clusterrolebindings -A \
  -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}: {.roleRef.name}{"\n"}{end}' \
  | grep cluster-admin
```

---

## ServiceAccount Tokens

Kubernetes auto-mounts a ServiceAccount token at `/var/run/secrets/kubernetes.io/serviceaccount/token` unless you opt out. Most application pods have no reason to call the Kubernetes API — the mounted token is an unnecessary credential.

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: api-server
  namespace: production
automountServiceAccountToken: false   # default opt-out for the ServiceAccount
```

Override per-pod when a specific workload does need API access:
```yaml
spec:
  automountServiceAccountToken: true   # pod-level override; wins over ServiceAccount default
  serviceAccountName: controller-sa
```

For workloads that need to call AWS APIs: use EKS Pod Identity or IRSA — do not mount AWS credentials as environment variables or `Secret` volumes. See [Networking & EKS](networking-eks.md) for both patterns.

---

## Pod Security Admission

PSP was removed in Kubernetes 1.25. PSA is the replacement, built into the API server.

**Three levels:**

| Level | What it allows | Use for |
|-------|---------------|---------|
| `privileged` | Anything | System namespaces (`kube-system`), node agents, CSI drivers |
| `baseline` | Blocks known privilege escalation; allows host networking/PID off by default | Legacy apps being migrated |
| `restricted` | Enforces secure defaults: non-root, no privilege escalation, seccomp required | All new application workloads |

**Three modes:**

| Mode | Effect |
|------|--------|
| `enforce` | Rejects pods that violate the policy |
| `audit` | Logs violations to audit log; pods still run |
| `warn` | Returns a warning in API responses; pods still run |

Apply via namespace labels:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: v1.28    # pin to a Kubernetes version
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

**Migration strategy for existing workloads:**
1. Start with `warn` + `audit` on `baseline`. Watch audit logs and warnings.
2. Move to `enforce: baseline` once no violations remain.
3. Upgrade to `warn` + `audit` on `restricted`, fix securityContext fields.
4. Promote to `enforce: restricted`.

Running all three modes simultaneously (`enforce: baseline`, `audit: restricted`, `warn: restricted`) catches restricted violations early without blocking deploys.

---

## SecurityContext Baseline

The securityContext fields required for `restricted` PSA are described in full in [Workloads](workloads.md#securitycontext-baseline). Summary here for cross-reference:

- `runAsNonRoot: true` — pod and container level
- `runAsUser: <non-zero>` — container level
- `readOnlyRootFilesystem: true` — container level
- `allowPrivilegeEscalation: false` — container level
- `capabilities.drop: ["ALL"]` — container level; `capabilities` is container-only
- `seccompProfile.type: RuntimeDefault` — pod level (required for `restricted`)

If the app needs write access, mount an `emptyDir` volume at `/tmp` — do not relax `readOnlyRootFilesystem`.

---

## NetworkPolicy — Default-Deny Pattern

Kubernetes defaults to "allow all" — every pod can reach every other pod. Without NetworkPolicy, a compromised pod can reach any service in the cluster.

**Default-deny ingress and egress:**

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: production
spec:
  podSelector: {}      # matches all pods in the namespace
  policyTypes:
    - Ingress
    - Egress
  # No ingress/egress rules = deny all
```

Apply this to every application namespace. Then explicitly allow what is needed:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-api-server
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: api-server
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ingress-nginx   # allow from ingress controller
        - podSelector:
            matchLabels:
              app: frontend
      ports:
        - protocol: TCP
          port: 8080
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: postgres
      ports:
        - protocol: TCP
          port: 5432
    - to: []              # allow DNS
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
```

**DNS egress is always required.** The default-deny policy blocks UDP/53. Applications cannot resolve DNS without an explicit egress rule to port 53. A NetworkPolicy that denies DNS causes mysterious timeouts, not connection-refused errors.

**"No policy = allow all" trap:** once ANY NetworkPolicy selects a pod (by `podSelector`), all traffic not explicitly allowed by that or another policy is denied. A single policy on a pod converts it from "allow all" to "deny everything not listed". Combine with the namespace default-deny for defense-in-depth.

---

## Secrets — Never in Git Plaintext

Three patterns for secrets in Kubernetes, in order of operational maturity:

| Approach | How it works | Trade-off |
|----------|-------------|-----------|
| **External Secrets Operator** | Pulls secrets from AWS Secrets Manager, SSM, Vault etc. into Kubernetes Secrets at runtime | Secret values never in Git; requires cluster connectivity to secret store; ESO manages rotation |
| **SOPS + age/KMS** | Encrypts secret files in Git with age key or AWS KMS; decrypt at apply time | Secret-encrypted-in-Git is auditable; decryption key must be available at deploy time; Flux has native SOPS support |
| **Sealed Secrets** | Controller generates public/private key; `kubeseal` encrypts secrets into `SealedSecret` CRs committed to Git; controller decrypts | Secrets in Git as sealed CRs; controller private key is a single point of failure; rotation requires re-sealing all secrets |

**External Secrets Operator (preferred for EKS + AWS Secrets Manager):**

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-credentials
  namespace: production
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secretsmanager        # SecretStore or ClusterSecretStore
    kind: ClusterSecretStore
  target:
    name: db-credentials            # creates this Kubernetes Secret
    creationPolicy: Owner
  data:
    - secretKey: DB_PASSWORD
      remoteRef:
        key: prod/api-server/db     # AWS Secrets Manager secret name
        property: password          # JSON key in the secret value
```

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secretsmanager
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa
            namespace: external-secrets
```

**SOPS with Flux (native integration):**

```yaml
# flux-system/kustomization.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
spec:
  decryption:
    provider: sops
    secretRef:
      name: sops-age     # Secret containing the age private key
```

---

## Image Provenance

**Digest pinning** over tags. Tags are mutable; `sha256:` digests are not.

```yaml
image: my-app:1.2.3@sha256:abc123...   # tag for readability, digest for immutability
```

**`imagePullPolicy`:**

| Value | When to use |
|-------|-------------|
| `IfNotPresent` | Default for most workloads; uses local cache |
| `Always` | Use with `latest` tag or in environments where cache staleness is a concern |
| `Never` | Air-gapped; image must already be on node |

Never use `latest` tag in production — a new image push to `latest` does not trigger a rollout, and the running image diverges from the tracked version.

**Admission scanning:** pair with an OPA/Kyverno policy that rejects images not coming from the approved registry, and a CI step that scans with Trivy before push.

```yaml
# Kyverno policy — require approved registry
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-approved-registry
spec:
  validationFailureAction: Enforce
  rules:
    - name: check-registry
      match:
        any:
          - resources:
              kinds: ["Pod"]
      validate:
        message: "Images must be from the approved registry"
        pattern:
          spec:
            containers:
              - image: "123456789012.dkr.ecr.us-east-1.amazonaws.com/*"
```

---

## Admission Policy Engines

| Engine | Model | Strength | When to choose |
|--------|-------|----------|----------------|
| **ValidatingAdmissionPolicy** (built-in, Kubernetes 1.26+ GA 1.30) | CEL expressions in-cluster | No controller install; low latency; native | Simple org-wide rules; no external dependency tolerance |
| **Kyverno** | Kubernetes-native policies as CRDs | Rich policy library, mutation + generation + validation, `kyverno test` CLI | Teams that prefer YAML/Kubernetes-native; good for generation (auto-add labels) |
| **OPA Gatekeeper** | Rego policy language + Constraint/ConstraintTemplate | Most flexible; Rego handles complex logic | Teams already using OPA/Rego; complex multi-resource policies |

**ValidatingAdmissionPolicy (built-in, portable):**

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: require-non-root
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
      - apiGroups: ["apps"]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources: ["deployments"]
  validations:
    - expression: >
        object.spec.template.spec.securityContext.runAsNonRoot == true
      message: "Pods must not run as root"
```

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: require-non-root-binding
spec:
  policyName: require-non-root
  validationActions: [Deny]
  matchResources:
    namespaceSelector:
      matchLabels:
        environment: production
```

---

## LLM Mistake Checklist

- Binds a ServiceAccount to `cluster-admin` for convenience — never appropriate for workloads; use least-privilege Role.
- Emits wildcard `resources: ["*"]` or `verbs: ["*"]` in a Role — never least-privilege.
- Omits `automountServiceAccountToken: false` on ServiceAccounts that never call the Kubernetes API.
- Emits `PodSecurityPolicy` — removed in 1.25; use Pod Security Admission namespace labels.
- Applies PSA via label on the Pod spec instead of the Namespace — PSA labels go on the Namespace, not the Pod.
- Emits a NetworkPolicy without a DNS egress rule (UDP/53) — default-deny plus no DNS egress rule causes silent name resolution failure.
- Assumes "no NetworkPolicy = NetworkPolicy allows all" is still safe — it is not; the correct assumption is "no NetworkPolicy = no restriction at all; first policy creates deny-by-default for selected pods".
- Puts Kubernetes Secret YAML with base64-encoded values in Git — base64 is not encryption; these are plaintext secrets.
- Uses `imagePullPolicy: Always` with a pinned digest — pointless; `IfNotPresent` with a digest is already immutable.
- Uses image tag `latest` in production without noting that it does not trigger a rollout on re-push.
- Conflates `audit` PSA mode with `enforce` — `audit` logs but does not block; `warn` warns but does not block; only `enforce` rejects.
- Emits `capabilities.drop: ["ALL"]` at pod-level `securityContext` — it is a container-level field; pod-level setting is ignored.
- Emits a `ClusterRoleBinding` when a `RoleBinding` would scope the access to the needed namespace — always prefer namespace-scoped binding.
- Suggests generating a Kubernetes Secret directly in CI and committing it — use ESO, SOPS, or sealed-secrets so plaintext never touches Git.

---

**Back to:** [Main Skill File](../SKILL.md)
