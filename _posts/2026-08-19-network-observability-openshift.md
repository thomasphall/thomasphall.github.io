---
title: "How to Install Network Observability on OpenShift 4.22"
description: >-
  Install LokiStack and the Network Observability Operator on OpenShift
  4.22, then use FlowCollector for eBPF flows, Topology, and traffic
  troubleshooting.
date: 2026-08-19 07:00:00 -0500
categories: [OpenShift, Security]
tags: [openshift, networking, gitops, security, openshift-virtualization]
permalink: /posts/network-observability-openshift/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization.
{: .prompt-info }

Policy without proof is a slide. After you write
[NetworkPolicy, AdminNetworkPolicy, and MultiNetworkPolicy](/posts/openshift-network-policies/),
someone still has to answer *is that drop actually happening, and between which
workloads?* Packet captures do not scale. Node `tcpdump` is a last resort, not
an operations model.

The [Network Observability Operator](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/network_observability/index)
on [Red Hat OpenShift](https://www.redhat.com/en/technologies/cloud-computing/openshift)
Container Platform 4.22 is the cluster-native answer: an eBPF agent on every
node, Kubernetes enrichment in `flowlogs-pipeline`, and
**Observe → Network Traffic** in the console. This post is a solution-architect
runbook for OpenShift 4.22 with Operator **1.12**. It is not a substitute for
product procedure. Confirm channels and CR fields against the
[4.22 Network Observability docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/network_observability/index)
before you paste YAML into production.

For a compact PoC checklist, use
[Network Observability (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/post-installation/network-observability/)
after CSI and the underlay in
[How to Get Started with an OpenShift PoC](/posts/getting-started-openshift-poc/).
If virtualization is in the story, masquerade flows are already in the
pipeline. VLAN, localnet, and SR-IOV are not—that is a privileged-agent
decision.

## What you are installing

The Operator does not store flows by itself. `FlowCollector` named `cluster` is
the only instance allowed. It reconciles three layers:

| Piece                         | Namespace                      | Role                                              |
| ----------------------------- | ------------------------------ | ------------------------------------------------- |
| Loki Operator                 | `openshift-operators-redhat`   | Cluster-wide; you may already have it for logging |
| `LokiStack` (`openshift-network` tenant) | `netobserv-loki`      | Indexes flow logs                                 |
| Network Observability Operator | `openshift-netobserv-operator` | Owns `FlowCollector`                              |
| Pipeline and console plugin   | `netobserv`                    | Enrichment plus **Observe → Network Traffic**     |
| eBPF agents                   | `netobserv-privileged`         | DaemonSet; samples packets on each node           |

> Do not reuse the logging `LokiStack`. Share the **Loki Operator**. Give
> Network Observability its own stack with `tenants.mode: openshift-network`.
{: .prompt-warning }

Loki is recommended. Skip it only if you want Prometheus dashboards, Topology,
and exporters (Kafka, IPFIX, OpenTelemetry) and can live without the Traffic
flows table, per-pod filters, and packet-drop statistics.

| Capability                         | With Loki | Without Loki |
| ---------------------------------- | --------- | ------------ |
| Metrics and NetObserv dashboards   | Yes       | Yes          |
| Topology                           | Yes       | Yes          |
| Traffic flows table                | Yes       | No           |
| Per-pod filter and aggregation     | Yes       | No           |
| Packet-drop statistics             | Yes       | No           |
| Kafka / IPFIX / OTLP exporters     | Yes       | Yes          |

On 4.22, `FlowCollector` enables Prometheus metrics by default. That is the
right floor. Loki is still what makes the table useful.

## Decide the pipeline before you subscribe

Changing `FlowCollector` later restarts agents and the pipeline. Set sampling,
Loki, and the deployment model on create.

**Loki vs metrics-only.** Full console investigation wants Loki. A metrics-only
PoC saves roughly 20–65% memory and 10–30% CPU, depending on sampling.

**`Service` vs `Kafka` vs `Direct`.** `Service` is the default: eBPF DaemonSet
plus a scalable `flowlogs-pipeline` Deployment. Use
[Red Hat Streams for Apache Kafka](https://docs.redhat.com/en/documentation/red_hat_streams_for_apache_kafka/)
(still called AMQ Streams in some Network Observability pages) when flow volume
overruns the pipeline buffer, you need replay, or you are in the documented
25-node and 250-node size bands. `Direct` colocates the processor as a
DaemonSet. It is a small-cluster assessment path, not a large-cluster default.

**Sampling.** Default `spec.agent.ebpf.sampling` is `50` (1 in 50 packets).
`0` or `1` is every packet. Start at 50. Tighten only when a case needs it.

Documented resource baselines (AWS M6i test beds) are a starting point, not a
quote for your cluster:

| Criterion           | Extra small (~10 nodes) | Small (~25 nodes) | Large (~250 nodes) |
| ------------------- | ----------------------- | ----------------- | ------------------ |
| LokiStack size      | `1x.extra-small`        | `1x.small`        | `1x.medium`        |
| Deployment model    | `Service`               | `Kafka`           | `Kafka`            |
| Processor replicas  | 3                       | 6                 | 18                 |
| eBPF sampling       | 50                      | 50                | 50                 |

Labs can drop processor replicas to `1`. Do not take that into a size you would
call production.

## Prerequisites

- `cluster-admin` and OVN-Kubernetes as the default CNI
- Block `StorageClass` with `ReadWriteOnce` for LokiStack WAL and working
  volumes (`oc get storageclass`)
- S3-compatible object storage for chunks (AWS S3 in `us-east-2`,
  [OpenShift Data Foundation](https://docs.redhat.com/en/documentation/red_hat_openshift_data_foundation/)
  NooBaa, or equivalent)
- Loki Operator **6.0 or later** (`stable-6.5` in current catalogs; pick the
  current `stable-6.y` from Software Catalog)
- Supported arch: `amd64`, `ppc64le`, `arm64`, or `s390x`

LokiStack needs **both** storage types. Missing object storage is a common
silent failure: the stack reports Ready and no flows land.

Keep the S3 secret out of git. Sync it with
[External Secrets Operator](/posts/external-secrets-vs-secrets-store-csi/)
from AWS Secrets Manager or your vault. The Kubernetes `Secret` must still be
named what `LokiStack` expects (`loki-s3` below).

## Install the Loki Operator

Skip this if `oc get csv -n openshift-operators-redhat` already shows a
Succeeded Loki Operator CSV. Use the Red Hat catalog (`redhat-operators`), not
community.

Console path: **Ecosystem → Software Catalog → Loki Operator**, channel
`stable-6.5`, namespace `openshift-operators-redhat`, enable recommended
cluster monitoring.

GitOps belongs in the **cluster** repo (namespace wave 0, OperatorGroup 1,
Subscription 2). Example `loki-operator.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-operators-redhat
  annotations:
    openshift.io/node-selector: ""
  labels:
    openshift.io/cluster-monitoring: "true"
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: loki-operator
  namespace: openshift-operators-redhat
spec:
  upgradeStrategy: Default
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: loki-operator
  namespace: openshift-operators-redhat
spec:
  channel: stable-6.5
  installPlanApproval: Automatic
  name: loki-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
```

```bash
oc apply -f loki-operator.yaml
oc get csv -n openshift-operators-redhat
```

Wait for `Succeeded`.

## Create the network LokiStack

```bash
oc create namespace netobserv-loki
oc label namespace netobserv-loki openshift.io/cluster-monitoring=true
```

Shape of the object-store secret (do not commit real keys). AWS S3 in
`us-east-2`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: loki-s3
  namespace: netobserv-loki
stringData:
  access_key_id: "<aws-access-key-id>"
  access_key_secret: "<aws-secret-access-key>"
  bucketnames: netobserv-loki
  endpoint: https://s3.us-east-2.amazonaws.com
  region: us-east-2
```

On-prem S3-compatible endpoints often need `forcepathstyle: "true"`. In-cluster
ODF NooBaa uses the service CA and
`https://s3.openshift-storage.svc:443`—see the
[PoC object-storage section](https://openshift-ssa.github.io/openshift-poc/post-installation/network-observability/).

Example `netobserv-lokistack.yaml`. Replace `gp3-csi` with a block class that
exists on the cluster:

```yaml
apiVersion: loki.grafana.com/v1
kind: LokiStack
metadata:
  name: loki
  namespace: netobserv-loki
spec:
  size: 1x.extra-small
  storage:
    schemas:
      - version: v13
        effectiveDate: "2022-06-01"
    secret:
      name: loki-s3
      type: s3
  storageClassName: gp3-csi
  tenants:
    mode: openshift-network
```

```bash
oc apply -f netobserv-lokistack.yaml
oc get lokistack loki -n netobserv-loki
oc get pvc -n netobserv-loki
```

PVCs must be Bound. If Console plugin queries fail later, raise
`spec.limits.global.ingestion` and query caps on this `LokiStack`—do not point
Network Observability at the logging stack to “save a bucket.”

## Install the Network Observability Operator

Install it in `openshift-netobserv-operator`. Do not park it in
`openshift-operators`.

Console: **Ecosystem → Software Catalog → Network Observability Operator**,
`stable` channel, enable recommended cluster monitoring.

Example `netobserv-operator.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-netobserv-operator
  labels:
    openshift.io/cluster-monitoring: "true"
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-netobserv-operator
  namespace: openshift-netobserv-operator
spec:
  upgradeStrategy: Default
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: netobserv-operator
  namespace: openshift-netobserv-operator
spec:
  channel: stable
  installPlanApproval: Automatic
  name: netobserv-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
```

```bash
oc apply -f netobserv-operator.yaml
oc get csv -n openshift-netobserv-operator
```

If the Operator pod fails to start and the cluster uses custom product logos
on the Console CR (`spec.customization.logos`), that is a known 1.12 issue.
Enable the `netobserv-plugin-static` Console plugin manually under
**Administration → Cluster Settings → Configuration → Console**.

## Create FlowCollector `cluster`

Console: **Ecosystem → Installed Operators → Network Observability Operator →
Flow Collector**, then the setup wizard. Or apply `flowcollector.yaml`:

```yaml
apiVersion: flows.netobserv.io/v1beta2
kind: FlowCollector
metadata:
  name: cluster
spec:
  namespace: netobserv
  deploymentModel: Service
  networkPolicy:
    enable: true
    additionalNamespaces:
      - openshift-console
      - openshift-monitoring
  agent:
    type: eBPF
    ebpf:
      sampling: 50
      privileged: false
      features: []
  processor:
    addZone: false
    subnetLabels:
      openShiftAutoDetect: true
      customLabels: []
    consumerReplicas: 3
  loki:
    enable: true
    mode: LokiStack
    lokiStack:
      name: loki
      namespace: netobserv-loki
  consolePlugin:
    enable: true
  exporters: []
```

`spec.networkPolicy.enable` defaults to `true`. If Loki, Kafka, or an exporter
lives in another namespaced NetworkPolicy domain, add that namespace to
`additionalNamespaces` so the pipeline can still reach it.

```bash
oc apply -f flowcollector.yaml
oc get flowcollector cluster
oc get pods -n netobserv-privileged
oc get pods -n netobserv
```

You want `STATUS` Ready, one `netobserv-ebpf-agent` per node, and
`flowlogs-pipeline` plus `netobserv-plugin` Running in `netobserv`. Then open
**Observe → Network Traffic**. If you see “No results,” click **Clear all
filters**—the default application-traffic filter is empty on a quiet cluster.

Quick sampling change without opening the YAML tab:

```bash
oc patch flowcollector cluster --type=json \
  -p '[{"op": "replace", "path": "/spec/agent/ebpf/sampling", "value": 50}]'
```

## Use Observe → Network Traffic

Three tabs, one investigation path.

**Overview** is aggregated rates: namespace, owner, pod, node, zone. Use it to
find *who is talking* before you open a table. **Observe → Dashboards** also
ships **NetObserv** and **NetObserv/Health**. Health is how you tell “the
network is broken” from “the pipeline is broken.”

**Traffic flows** is the Loki table: source and destination, ports, bytes,
drops when enabled. Expand a row. Export CSV when a ticket needs evidence.
This is how you prove a
[tenant or admin NetworkPolicy](/posts/openshift-network-policies/) is
dropping east-west traffic instead of arguing from YAML.

**Topology** is the graph. Scope it to Namespace, then Owner, then Pod. On 1.12,
TLS metadata can mark encrypted edges with lock icons once `TLSTracking` is on.
That is handshake metadata (`ClientHello` / `ServerHello`). It does not decrypt
payloads.

Filter by namespace, name, kind, port, or protocol. Quick filters for
Applications, Infrastructure, Pods, and Services are enough for most demos.
For a 10-minute capture without installing the Operator, `oc netobserv` streams
flows to an ephemeral collector and copies output locally. Use that for a
break-glass capture, not as the platform’s observability story.

## Features you turn on on purpose

Each extra eBPF feature costs CPU and memory. Privileged agents are required
for some of them. Least privilege means leave `privileged: false` until a
feature needs it.

```yaml
spec:
  agent:
    type: eBPF
    ebpf:
      privileged: true
      features:
        - PacketDrop
        - DNSTracking
        - FlowRTT
        - TLSTracking
```

| Feature          | What you gain                                      | Privileged |
| ---------------- | -------------------------------------------------- | ---------- |
| `PacketDrop`     | Host `SKB_DROP_*` and OVS `OVS_DROP_*` reasons     | Yes        |
| `DNSTracking`    | Query name, RCODE, DNS latency (port 53)           | No         |
| `FlowRTT`        | TCP smoothed RTT                                   | No         |
| `TLSTracking`    | TLS version and cipher metadata (1.12)             | No         |
| `UDNMapping`     | Map flows to user-defined networks                 | Yes        |
| `IPSec`          | Node IPsec status on flows                         | No         |
| `NetworkEvents`  | Correlate flows with OVN network policy events     | Yes; Tech Preview |

`OVS_DROP_LAST_ACTION` is the interesting drop when you are validating
NetworkPolicy: OVN dropped the packet because of an implicit drop, often
policy. `PacketDrop` is how that shows up in Overview panels and the side
panel of a flow. That proves tenant `NetworkPolicy` on the **pod network**.
It does not prove
[`MultiNetworkPolicy` on a VM extra NIC](/posts/openshift-network-policies/).

DNS tracking is how you separate “CoreDNS NXDOMAIN” from “the packet never
left the node.” TLS tracking is how you find TLS 1.0/1.1 or weak ciphers
without a decrypting middlebox.

## OpenShift Virtualization

[OpenShift Virtualization](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/index)
VMs are Kubernetes workloads. Each guest runs in a `virt-launcher` pod. Network
Observability follows that model: the flow’s owner is the
`VirtualMachineInstance`, not a hypervisor port group. How you attach the guest
decides whether the default `FlowCollector` is enough. The attach patterns are
in
[OpenShift Virtualization networking](/posts/openshift-virtualization-networking/).

| Guest attachment | Captured by default? | What to set |
| ---------------- | -------------------- | ----------- |
| Default pod network (masquerade) | Yes | Nothing extra |
| Primary user-defined network (UDN) | After `UDNMapping` | Privileged plus `features: [UDNMapping]` |
| Secondary localnet / CUDN, extra Multus NAD | No | Privileged agents |
| SR-IOV VF | No | Privileged agents (the VF lives in the pod netns) |

Masquerade is the easy demo: filter Traffic flows by the virt-launcher pod or
the VM IP and you already have east-west on the cluster network. The moment the
story is “the guest is on VLAN 100” or “the VF bypasses OVS,” the eBPF agent
must run privileged so it can see namespaces other than the host.

```yaml
spec:
  agent:
    type: eBPF
    ebpf:
      privileged: true
      features:
        - UDNMapping
        - PacketDrop
  processor:
    advanced:
      secondaryNetworks:
        - index:
            - MAC
```

Operator **1.12** ignores `spec.processor.advanced.secondaryNetworks[].name`.
With `privileged: true` and no list, it auto-detects secondary networks. Keep
an explicit `index` when enrichment is wrong: **MAC** first, then `IP` or
`Interface` if MAC addresses collide across pods. Guessing the NAD name from
GitOps is the old workflow; it is not how 1.12 binds flows.

Confirm the guest’s extra NIC from the launcher annotation, then filter the
console by that IP:

```bash
oc get pod -n '<namespace>' -l 'kubevirt.io/domain=<vm-name>' \
  -o jsonpath="{.items[0].metadata.annotations['k8s.v1.cni.cncf.io/network-status']}{'\n'}"
```

The default `ovn-kubernetes` entry is masquerade (`eth0`). Additional objects
are the extra NICs: `name` (often `<namespace>/<nad>`), `interface`, `ips`,
`mac`. In **Observe → Network Traffic → Traffic flows**, filter Source IP to
the secondary address. Source and Destination should enrich to the
virt-launcher pod and the VM instance as owner. Empty owner with a raw MAC
means privileged is off, or the index is not unique.

`UDNMapping` adds `SrcK8S_NetworkName` and `DstK8S_NetworkName`. Topology can
scope or group by **Network**. That is the right view when primary Layer2 UDNs
are how you isolate VM tenants. Sampling `1` is what the product example uses
for UDN mapping; do not copy that onto a busy cluster. Leave sampling at `50`
unless a case needs every packet.

Policy still splits by NIC.
[`NetworkPolicy` / ANP](/posts/openshift-network-policies/)
apply to the pod network and primary UDNs. `MultiNetworkPolicy` applies to
secondary attachments only. Use `PacketDrop` on the right plane: masquerade
drops show `OVS_DROP_*` for pod-network policy; a localnet NIC that never
appears in Traffic flows is usually missing privileged, not missing
`NetworkPolicy`.

## Kafka when Service is not enough

Install Streams for Apache Kafka separately. Create a dedicated topic. Then
set the deployment model and compression (1.12):

```yaml
spec:
  deploymentModel: Kafka
  kafka:
    address: kafka-cluster-kafka-bootstrap.netobserv:9093
    topic: network-flows
    compression: lz4
    tls:
      enable: true
```

`lz4` is the usual default when you want compression: low CPU, roughly 2–3×
smaller messages. `zstd` trades more CPU for more compression. Put CA (and
mTLS user certs, if used) in both `netobserv` and `netobserv-privileged`.

Exporters (`spec.exporters`) are a different knob: copy **enriched** flows to
another Kafka topic, IPFIX, or OpenTelemetry while the console still reads
Loki. That is how you feed a SIEM without making the SIEM the console.

## Tenants, RBAC, and FlowCollectorSlice

Cluster admins see all flows. Project admins see their namespaces. Developers
need explicit roles.

Cluster-wide read for a non-admin:

```bash
oc adm policy add-cluster-role-to-user netobserv-loki-reader '<user>'
oc adm policy add-cluster-role-to-user cluster-monitoring-view '<user>'
oc adm policy add-cluster-role-to-user netobserv-metrics-reader '<user>'
```

Per-namespace metrics plus Loki read:

```bash
oc adm policy add-cluster-role-to-user netobserv-loki-reader '<user>'
oc adm policy add-role-to-user netobserv-metrics-reader '<user>' -n '<namespace>'
```

`FlowCollectorSlice` (`flows.netobserv.io/v1alpha1`) is the 4.22 path for
tenant-scoped collection: the cluster `FlowCollector` stays the control plane;
a namespace-scoped slice can tighten sampling or subnets. Enable it only when
you intend that split:

```yaml
spec:
  processor:
    slicesConfig:
      enable: true
      collectionMode: AllowList
      namespacesAllowList:
        - /openshift-.*|netobserv.*/
```

`AllowList` collects only namespaces that have a slice (plus the allow list).
`AlwaysCollect` keeps global collection and still applies slice sampling. Leave
slices off until a hosted-control-plane or multi-tenant landing zone needs
self-service visibility. Do not enable AllowList on a cluster that already
depends on seeing every namespace.

## GitOps placement

Subscriptions, `LokiStack`, `FlowCollector`, and the object-store
`ExternalSecret` live in the **cluster** configuration repo, not the
application repo. Same split as
[GitOps Should Manage ACM, Not the Cluster](/posts/gitops-should-manage-acm/):
platform owns the pipeline; tenants do not ship a second `FlowCollector`.

If you later enable slices, the global `slicesConfig` stays in the cluster
repo. Tenant `FlowCollectorSlice` objects can ride with the application repo
the same way tenant `NetworkPolicy` does.

## The SA takeaway

1. **Install Loki first, as a dedicated `openshift-network` LokiStack.** Share
   the Operator, never the logging stack.
2. **One `FlowCollector` named `cluster`.** Set sampling, Loki, and
   `Service` vs `Kafka` on create. Edits restart the pipeline.
3. **Leave sampling at 50 and privileged off** until packet drops, UDNs, or
   VM secondary NICs require more.
4. **Use the console to prove policy.** Overview to find the talkers, Traffic
   flows for the row, `PacketDrop` when you need OVN drop reasons.
5. **Virtualization is two networks.** Masquerade is automatic. Localnet,
   SR-IOV, and other extra NICs need privileged agents; `UDNMapping` if
   Topology should group by UDN.
6. **GitOps the cluster repo.** Operator subscriptions, LokiStack, and
   FlowCollector are platform objects. Keep S3 credentials in External Secrets.

## Related posts

- [OpenShift Network Policies: Tenant, Admin, Secondary](/posts/openshift-network-policies/)
- [OpenShift Virtualization Networking: Pod to Localnet](/posts/openshift-virtualization-networking/)
- [How to Get Started with an OpenShift PoC](/posts/getting-started-openshift-poc/)
- [GitOps Should Manage ACM, Not the Cluster](/posts/gitops-should-manage-acm/)

> Want help sizing LokiStack and FlowCollector for a landing zone? Reach out
> to your Red Hat account team—or stand up Loki plus a default `FlowCollector`
> on a non-prod cluster, prove one NetworkPolicy drop, then enable privileged
> agents and capture a VM secondary NIC before you standardize on localnet.
{: .prompt-tip }

## Further reading

- [Network Observability (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/network_observability/index)
- [Network Observability Operator (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/network_observability_operator/index)
- [Secondary networks (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/network_observability/network-observability-secondary-networks)
- [OpenShift Virtualization networking (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/networking)
- [Network Observability (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/post-installation/network-observability/)
- [Networking (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/post-installation/networking/)
- [Installing the Loki Operator (Logging 6.5)](https://docs.redhat.com/en/documentation/red_hat_openshift_logging/6.5/html/installing_logging/installing-the-loki-operator)
- [Streams for Apache Kafka](https://docs.redhat.com/en/documentation/red_hat_streams_for_apache_kafka/)
