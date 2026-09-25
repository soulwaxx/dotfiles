# Networking & EKS

> **Part of:** [kubernetes-skill](../SKILL.md)
> **Purpose:** Services, Ingress, Gateway API, AWS LB Controller, IRSA vs Pod Identity, CSI, Karpenter networking

> **EKS-specific sections are marked [EKS].** Portable sections apply to any Kubernetes distribution.

---

## TOC

1. [Service Types](#service-types)
2. [Ingress vs Gateway API](#ingress-vs-gateway-api)
3. [AWS Load Balancer Controller [EKS]](#aws-load-balancer-controller-eks)
4. [IRSA vs EKS Pod Identity [EKS]](#irsa-vs-eks-pod-identity-eks)
5. [EBS and EFS CSI Drivers [EKS]](#ebs-and-efs-csi-drivers-eks)
6. [Karpenter Networking Interaction [EKS]](#karpenter-networking-interaction-eks)
7. [LLM Mistake Checklist](#llm-mistake-checklist)

---

## Service Types

| Type | What it does | When to use |
|------|-------------|-------------|
| `ClusterIP` | Stable virtual IP inside the cluster | Default; service-to-service within cluster |
| `headless` (`clusterIP: None`) | DNS returns Pod IPs directly, no virtual IP | StatefulSet peer discovery; client-side load balancing |
| `NodePort` | Exposes a port on every node's IP | Development only; not for production direct exposure |
| `LoadBalancer` | Provisions a cloud LB; on EKS triggers AWS LB Controller | Expose service directly to the internet or VPC without Ingress |
| `ExternalName` | DNS CNAME alias to an external hostname | Redirect cluster traffic to an external service by name |

### No endpoints diagnosis

When a Service shows no endpoints — `kubectl get endpoints <svc>` returns an empty address list — the cause is one of:

1. **Label selector mismatch.** `kubectl get pods -l <svc-selector> -n <ns>` returns nothing. Check `Service.spec.selector` against `Pod.metadata.labels`.
2. **Pod not Ready.** The pod exists but the `readinessProbe` is failing. Endpoints are only added for Ready pods. `kubectl describe pod <pod>` → look at `Conditions` and probe events.
3. **Wrong namespace.** Pod and Service are in different namespaces; cross-namespace Services need `ExternalName` or Gateway API.
4. **Pod not yet scheduled.** Pod is `Pending` due to insufficient resources or a missing node.

```bash
# Quick endpoint diagnosis
kubectl get endpoints <svc> -n <ns>
kubectl describe service <svc> -n <ns>    # check Events and Selector
kubectl get pods -n <ns> -l app=<label> --show-labels
kubectl describe pod <pod> -n <ns>        # check Readiness
```

---

## Ingress vs Gateway API

**Ingress** (`networking.k8s.io/v1`) is the current stable API, widely used, controller-specific annotations for advanced routing. It will not be removed but is not receiving new features.

**Gateway API** (`gateway.networking.k8s.io/v1`) reached v1.5 GA in February 2026. It is the forward path for new L7 routing. Use it for new setups; migration from Ingress is not required but is recommended for complex routing needs.

### Gateway API structure (portable, v1.5 GA)

```yaml
# GatewayClass — cluster-scoped, provisioned by the controller install
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: aws-application-lb
spec:
  controllerName: gateway.k8s.aws/alb   # [EKS] AWS LB Controller
  # For other controllers: traefio.io/gateway-controller, etc.

---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: prod-gateway
  namespace: production
spec:
  gatewayClassName: aws-application-lb
  listeners:
    - name: https
      protocol: HTTPS
      port: 443
      tls:
        mode: Terminate
        certificateRefs:
          - kind: Secret
            name: tls-cert
      allowedRoutes:
        namespaces:
          from: Selector
          selector:
            matchLabels:
              gateway-access: "true"

---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: api-server
  namespace: production
spec:
  parentRefs:
    - name: prod-gateway
      namespace: production
  hostnames:
    - "api.example.com"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api
      backendRefs:
        - name: api-server
          port: 8080
```

### Ingress (current, still valid)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-server
  namespace: production
  annotations:
    kubernetes.io/ingress.class: "alb"   # legacy annotation; prefer ingressClassName
spec:
  ingressClassName: alb                  # preferred way (Kubernetes 1.18+)
  rules:
    - host: api.example.com
      http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: api-server
                port:
                  number: 8080
  tls:
    - hosts:
        - api.example.com
      secretName: tls-cert
```

---

## AWS Load Balancer Controller [EKS]

The AWS Load Balancer Controller provisions ALBs (for Ingress/HTTPRoute) and NLBs (for `Service type: LoadBalancer`).

### NLB vs ALB

| | ALB | NLB |
|--|-----|-----|
| **OSI layer** | L7 (HTTP/HTTPS) | L4 (TCP/UDP/TLS) |
| **Use for** | HTTP routing, path/host-based rules, JWT auth, WAF | Any TCP/UDP, gRPC without HTTP inspection, static IP |
| **Kubernetes trigger** | `Ingress` or `HTTPRoute` | `Service type: LoadBalancer` |

### Key annotations

```yaml
metadata:
  annotations:
    # ALB (Ingress)
    kubernetes.io/ingress.class: alb                          # legacy; prefer spec.ingressClassName
    alb.ingress.kubernetes.io/scheme: internet-facing         # or internal
    alb.ingress.kubernetes.io/target-type: ip                 # ip = pods directly; instance = NodePort
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:...
    alb.ingress.kubernetes.io/healthcheck-path: /healthz
    alb.ingress.kubernetes.io/group.name: shared-alb          # share an ALB across Ingresses

    # NLB (Service type: LoadBalancer)
    service.beta.kubernetes.io/aws-load-balancer-type: external          # use LB controller, not legacy in-tree
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip     # ip or instance
    service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
```

`target-type: ip` registers pod IPs directly with the target group. No NodePort hop; better performance; requires VPC CNI (EKS default). `instance` mode uses NodePort — compatible with non-VPC-CNI setups.

### Why the LB isn't created — diagnosis checklist

1. **Controller not installed or not running.** `kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller`.
2. **Controller IAM permissions missing.** The controller ServiceAccount needs an IAM role with `elasticloadbalancing:*` and `ec2:Describe*` permissions. `kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller` for `AccessDenied` errors.
3. **Subnet tags missing.** Public subnets must have `kubernetes.io/role/elb: "1"`. Private subnets must have `kubernetes.io/role/internal-elb: "1"`. Without the tag, the controller does not know which subnet to place the LB in.
4. **`ingressClassName` mismatch.** The Ingress `spec.ingressClassName` must match the IngressClass the controller owns.
5. **SecurityGroup rules.** The ALB security group must allow inbound 443/80 from the internet (or VPC). The node/pod security groups must allow traffic from the ALB security group.

```bash
kubectl describe ingress <name> -n <ns>     # look at Events for controller errors
kubectl logs -n kube-system \
  -l app.kubernetes.io/name=aws-load-balancer-controller \
  --tail=100
```

---

## IRSA vs EKS Pod Identity [EKS]

Both grant Kubernetes workloads AWS IAM permissions without embedding static credentials.

### EKS Pod Identity (preferred for new clusters, Kubernetes 1.24+)

Pod Identity uses the EKS Pod Identity Agent (a DaemonSet add-on). No OIDC trust policy; the `PodIdentityAssociation` resource links a ServiceAccount to an IAM role.

```bash
# Create the association via AWS CLI (or Terraform)
aws eks create-pod-identity-association \
  --cluster-name my-cluster \
  --namespace production \
  --service-account api-server \
  --role-arn arn:aws:iam::123456789012:role/ApiServerRole
```

IAM role trust policy:
```json
{
  "Effect": "Allow",
  "Principal": {
    "Service": "pods.eks.amazonaws.com"
  },
  "Action": ["sts:AssumeRole", "sts:TagSession"]
}
```

No annotation on the ServiceAccount is required for Pod Identity. The agent injects credentials via a projected volume.

**Fargate caveat:** the Pod Identity Agent is a DaemonSet — it cannot run on Fargate nodes. Fargate pods must use IRSA.

### IRSA (still valid, required for Fargate)

IRSA annotates the ServiceAccount with the role ARN. The OIDC provider in the cluster signs a token that AWS STS validates.

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: api-server
  namespace: production
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/ApiServerRole
```

IAM role trust policy (IRSA):
```json
{
  "Effect": "Allow",
  "Principal": {
    "Federated": "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/<CLUSTER_ID>"
  },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringEquals": {
      "oidc.eks.us-east-1.amazonaws.com/id/<CLUSTER_ID>:sub": "system:serviceaccount:production:api-server"
    }
  }
}
```

IRSA requires the EKS OIDC provider to be enabled and a trust policy that references the cluster's OIDC issuer URL. Pod Identity does not.

### Side-by-side comparison

| | Pod Identity | IRSA |
|--|-------------|------|
| **Cluster setup** | Enable Pod Identity Agent add-on | Enable OIDC provider on cluster |
| **IAM trust policy** | `pods.eks.amazonaws.com` service principal | OIDC Federated principal + condition |
| **SA annotation** | Not required | `eks.amazonaws.com/role-arn` required |
| **Association object** | `PodIdentityAssociation` (AWS API) | IAM role trust + SA annotation |
| **Fargate support** | No (DaemonSet cannot run on Fargate) | Yes |
| **Cross-account** | Yes (via STS) | Yes |

---

## EBS and EFS CSI Drivers [EKS]

### EBS CSI

Provides `gp3`/`gp2` block volumes. `ReadWriteOnce` — one pod per volume.

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer   # wait until pod is scheduled; provisions in the pod's AZ
reclaimPolicy: Retain                     # Retain or Delete; use Retain for prod data
allowVolumeExpansion: true
parameters:
  type: gp3
  encrypted: "true"
  iops: "3000"
  throughput: "125"
```

`volumeBindingMode: WaitForFirstConsumer` is critical. Without it, EBS volumes provision immediately in a random AZ. If the pod later schedules in a different AZ, it cannot attach. `WaitForFirstConsumer` defers provisioning until the pod's AZ is known.

### EFS CSI

Provides NFS-backed shared storage. `ReadWriteMany` — multiple pods can mount the same volume simultaneously. Suitable for shared config, ML model storage, or legacy NFS workloads.

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: efs
provisioner: efs.csi.aws.com
parameters:
  provisioningMode: efs-ap      # EFS Access Point per PVC
  fileSystemId: fs-0abc1234
  directoryPerms: "700"
  gidRangeStart: "1000"
  gidRangeEnd: "2000"
  basePath: "/dynamic"
```

EFS volumes are not AZ-constrained — they work across zones. Use EFS for `ReadWriteMany`; use EBS for single-writer, higher-IOPS workloads.

---

## Karpenter Networking Interaction [EKS]

Karpenter discovers subnets and security groups by tag, not by explicit configuration in the NodePool. This is the most common provisioning failure point.

**Required subnet tag:**
```
karpenter.sh/discovery: <cluster-name>
```

**Required security group tag:**
```
karpenter.sh/discovery: <cluster-name>
```

If Karpenter cannot find subnets or security groups, it logs `no subnets found` or `no security groups found` and the NodeClaim stays `Pending`.

```bash
# Check subnet tags
aws ec2 describe-subnets \
  --filters "Name=tag:karpenter.sh/discovery,Values=<cluster-name>" \
  --query 'Subnets[*].{ID:SubnetId,AZ:AvailabilityZone}'

# Check NodeClaim status
kubectl get nodeclaims
kubectl describe nodeclaim <name>

# Check Karpenter controller logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=200
```

Nodes provisioned by Karpenter use the subnets tagged with `karpenter.sh/discovery`. For private clusters, subnets must also have a route to the EKS API endpoint (VPC endpoint or NAT gateway). Public clusters provision nodes with public IPs if the subnet has `MapPublicIpOnLaunch` or the EC2NodeClass specifies `associatePublicIPAddress`.

---

## LLM Mistake Checklist

- Uses `kubernetes.io/ingress.class` annotation instead of `spec.ingressClassName` — the annotation is legacy; `ingressClassName` is the correct field since Kubernetes 1.18.
- Emits `extensions/v1beta1` for Ingress — removed in 1.22; use `networking.k8s.io/v1`.
- Sets `target-type: instance` on an EKS cluster using VPC CNI — use `ip` to skip the NodePort hop; `instance` is for non-standard CNI setups.
- Omits `service.beta.kubernetes.io/aws-load-balancer-type: external` on an NLB Service — without it, Kubernetes uses the legacy in-tree LB controller, not the AWS LB Controller.
- Uses IRSA on Fargate without noting that Pod Identity does not work on Fargate — Pod Identity Agent is a DaemonSet.
- Annotates the Pod (not the ServiceAccount) with `eks.amazonaws.com/role-arn` for IRSA — the annotation goes on the ServiceAccount.
- Emits a Pod Identity setup without noting no ServiceAccount annotation is needed — models often add the IRSA annotation anyway.
- Uses `volumeBindingMode: Immediate` on an EBS StorageClass — volumes provision in a random AZ; use `WaitForFirstConsumer`.
- Recommends EFS for high-IOPS single-writer workloads — EFS is NFS-backed and higher latency than EBS; use EBS gp3 for databases and block IO.
- Omits the `karpenter.sh/discovery: <cluster-name>` tag from subnets and security groups — Karpenter cannot provision nodes without these tags.
- Configures Gateway API with `gateway.networking.k8s.io/v1beta1` instead of `gateway.networking.k8s.io/v1` — v1 is GA since v1.0 (Oct 2023); v1.5 GA Feb 2026.
- Emits an ALB Ingress without a subnet tag — ALB cannot be provisioned if the `kubernetes.io/role/elb: "1"` tag is absent from public subnets.
- Uses `clusterIP: None` (headless) Service without explaining that it returns pod IPs directly — client-side load balancing is the caller's responsibility; there is no virtual IP to round-robin.

---

**Back to:** [Main Skill File](../SKILL.md)
