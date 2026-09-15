---
title: "OpenShift Edge Architectures: Form Factor, Then Fleet"
description: >-
  Compare MicroShift, Single Node OpenShift, two-node HA, compact, and
  hub-and-spoke edge patterns—plus LVMS, external CSI, and ODF storage
  that matches each site’s failure domain.
date: 2026-08-04 16:00:00 -0500
categories: [OpenShift]
tags: [openshift, edge, sno, gitops, storage, two-node]
og_image: /assets/img/og/openshift-edge-architectures.png
permalink: /posts/openshift-edge-architectures/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization.
{: .prompt-info }

> Updated 15 Sep 2026: OpenShift 4.22 two-node form factors (arbiter and
> fencing), current Device Edge components and URL, and relocated OpenShift
> PoC links.
{: .prompt-info }

Architecture reviews rarely fail because someone forgot to say “OpenShift at
the edge.” They fail because that phrase hides five different designs. A
resource-constrained gateway, a two-server store that still needs HA, a
single-rack plant cell, and a regional hub that installs a thousand spokes are
all “edge”—and they want different form factors, different failure domains, and
different day-2 muscle memory.

This post is a solution-architect map of common
[Red Hat OpenShift](https://www.redhat.com/en/technologies/cloud-computing/openshift)
edge architectures. The thesis is simple: **name the constraints first, pick a
form factor second, then standardize how the fleet is managed.** Examples below
are representative patterns, not install runbooks.

## What “edge” means in an OpenShift conversation

Treat edge as a spectrum of constraints, not a zip code.

- **Device / far edge** — appliance-class hosts, tight CPU/RAM/storage, often
  intermittent WAN, and little or no skilled hands on site.
- **Site edge** — factory cell, retail store, branch, or cell site. Usually one
  or a few servers. Workloads must keep running when the WAN blips.
- **Near edge / regional aggregation** — a fuller cluster (or small set of them)
  that hubs content, policy, and lifecycle for many spokes.

Across that spectrum, four design questions show up every time:

1. **Footprint** — how much hardware and power does the site allow?
2. **Failure domain** — is site-local HA required, or is rebuild-from-spare the
   recovery model?
3. **Connectivity** — online, bandwidth-limited, or intentionally disconnected?
4. **Fleet sameness** — one lab cluster, or hundreds of identical sites?

Answer those before debating product names. The form factor follows.

In practice the topologies stack like this:

```text
 Far / device edge          Site edge                      Near-edge hub
┌──────────────────┐     ┌─────────────────────────┐     ┌──────────────────────┐
│ MicroShift       │     │ SNO                     │     │ RHACM + GitOps ZTP   │
│ Device Edge      │────▶│ Two-node (TNA / TNF)    │◀───▶│ content mirrors      │
│ (appliance host) │     │ Three-node compact      │     │ fleet lifecycle      │
└──────────────────┘     └─────────────────────────┘     └──────────────────────┘
   footprint first          full OCP API                    scale the sameness
```

Installer floors on OpenShift 4.22 (not a virtualization bill of materials):
MicroShift is 2 cores / 2 GB RAM / 10 GB disk; SNO is 4 vCPU / 16 GB / 120 GB
(4 vCPU leaves almost no app headroom); each two-node control plane is 4 vCPU /
16 GB / 120 GB, plus a 2 vCPU / 8 GB / 50 GB arbiter for TNA.

## Example A — Device edge with MicroShift

**Scenario:** An industrial gateway or kiosk-class host that must run a small
set of containerized services next to sensors or a local UI. Power and rack
space are scarce; WAN is unreliable; nobody wants a full OpenShift control plane
on the box.

**Architecture:** [Red Hat build of MicroShift](https://docs.redhat.com/en/documentation/red_hat_build_of_microshift/4.22/html/understanding_microshift/microshift-understanding)
on edge-optimized Red Hat Enterprise Linux—image mode (`bootc`) or RHEL for
Edge (`rpm-ostree`). That pairing is
[Red Hat Device Edge](https://www.redhat.com/en/technologies/device-edge):
a single-node Kubernetes runtime aimed at resource-constrained field
environments, with a focused API surface for orchestration, networking, ingress,
storage, and security. Device fleets are an OS/device control plane
([Red Hat Edge Manager](https://www.redhat.com/en/resources/edge-manager-datasheet)
on the standard SKU, or Ansible)—not GitOps ZTP on a hub cluster.

```text
 Field site (gateway / kiosk)
┌──────────────────────────────────────────────┐
│  Red Hat Device Edge                         │
│                                              │
│  ┌────────────────────────────────────────┐  │
│  │ MicroShift                             │  │
│  │  pods / routes / SCCs (focused APIs)   │  │
│  └──────────────────▲─────────────────────┘  │
│                     │ runs on                │
│  ┌──────────────────┴─────────────────────┐  │
│  │ RHEL (image mode / RHEL for Edge)      │  │
│  │  OS lifecycle, updates, local storage  │  │
│  └────────────────────────────────────────┘  │
└───────────────────────┬──────────────────────┘
                        │ intermittent / thin WAN
                        v
              Edge Manager / Ansible / image source
              (not a full OCP control plane)
```

**Why it fits**

- Footprint and networking constraints are first-class design goals, not
  afterthoughts. The supported floor is 2 cores, 2 GB RAM, and 10 GB disk.
- Devices are largely self-managing; OS-level image and update patterns carry
  much of the lifecycle that a full OpenShift cluster would handle with
  operators and OLM.
- Teams can still speak Kubernetes/`oc` for the workloads that matter locally.

**What you give up (say it out loud)**

- MicroShift is **not** full OpenShift Container Platform. It does not bring the
  console or multi-node HA story with it. OLM has been present since 4.15, but
  it does not ship the OpenShift OperatorHub catalog—you bring the operators
  you actually need.
- It does not support workload HA or horizontal scale by adding workers.
- Virtual machines, when needed, are an OS/host concern—not OpenShift
  Virtualization on that device.

**Wrong answer when:** stakeholders assume every OpenShift API, OperatorHub
catalog, or multi-node pattern will “just work” on the gateway. If the site
needs the full platform surface, step up to SNO, two-node, or compact—not a
stretched definition of MicroShift.

## Example B — Single Node OpenShift at the site

**Scenario:** A manufacturing cell or retail store with one capable bare-metal
server (or equivalent). The team wants the **full OpenShift API** for operators,
GitOps, and familiar platform services, but site HA is not the priority.
Rebuild-from-spare or overnight recovery is acceptable; dual control-plane
racks are not in the budget.

**Architecture:**
[Single Node OpenShift (SNO)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/installing_on_a_single_node/index)—
control plane and workers co-located on one node. The 4.22 floor is 4 vCPU /
16 GB RAM / 120 GB disk; that threshold leaves almost no headroom for
workloads, so size for the apps, not the installer table. Common companions at
the site:

- Local storage such as LVM Storage (LVMS) for PVCs without a full external
  array
- OpenShift GitOps for app and config drift control
- Optional [OpenShift Virtualization](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/index)
  when a handful of leftover VMs must land beside containers
- Mirrored catalogs and pinned images when the WAN is thin or the site is
  disconnected for stretches

```text
 Manufacturing cell / retail store
┌────────────────────────────────────────────────────┐
│  Single Node OpenShift (one host = one failure     │
│  domain)                                           │
│                                                    │
│  ┌──────────────┐  ┌────────────┐  ┌────────────┐  │
│  │ Control plane│  │ Workloads  │  │ Optional   │  │
│  │ + workers    │  │ (pods)     │  │ OpenShift  │  │
│  │ (same node)  │  │            │  │ Virt VMs   │  │
│  └──────┬───────┘  └─────┬──────┘  └─────┬──────┘  │
│         └────────────────┼───────────────┘         │
│                          v                         │
│               ┌────────────────────┐               │
│               │ LVMS / local disks │               │
│               │ GitOps (desired)   │               │
│               │ local image mirror │               │
│               └────────────────────┘               │
└──────────────────────────┬─────────────────────────┘
                           │ WAN (may be thin)
                           v
                    hub / content source
                    (rebuild-from-spare model)
```

**Why it fits**

- One machine, full OpenShift operational model—ideal when platform consistency
  with the datacenter matters more than site-local quorum.
- Assisted service and fleet tooling can install SNO the same way they install
  larger bare-metal shapes, which matters once you leave “one lab” behind.

**Trade-off to put on the slide**

SNO is a **single failure domain**. Control plane and workloads share fate.
Design for backup, image-based rebuild, spare hardware, and tested recovery—not
for multi-AZ HA. OpenShift Virtualization on SNO is supported, without live
migration. If the plant cannot tolerate that node going dark, step up to
two-node or compact—SNO is the wrong form factor no matter how attractive the
BOM looks.

**Connectivity reality:** plan content delivery and upgrade windows before day
1. Disconnected or bandwidth-limited sites need mirrors, release images, and a
break-glass story that works when the hub is unreachable.

## Example C — Two-node HA at the site

**Scenario:** A plant or store that cannot tolerate the single node going dark,
but cannot (or will not) buy a third hypervisor-class server. Leftover VMs need
somewhere to live-migrate. Rebuild-from-spare is no longer the recovery model.

**Architecture:** OpenShift 4.22 adds two supported
[two-node](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/installing_a_two_node_openshift_cluster/index)
topologies. Pick by whether a tiny third host exists and whether BMC fencing is
real.

[Two-Node with Arbiter (TNA)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/installing_a_two_node_openshift_cluster/about-two-node-arbiter-installation)
is two schedulable control-plane hosts plus one **local** arbiter that stores a
full etcd copy so Raft still has three voters. The arbiter does not run
`kube-apiserver`, `kube-controller-manager`, or workloads. Remote or “cloud”
arbiters are not supported. After install you can add at most two extra workers;
you cannot convert the cluster to a standard multi-node shape.

[Two-Node with Fencing (TNF)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/installing_a_two_node_openshift_cluster/two-node-with-fencing)
is two control-plane hosts and no arbiter. Pacemaker fences an unresponsive node
via the BMC (Redfish) so etcd does not split-brain. TNF does not support extra
compute nodes. GitOps ZTP is **not** a validated topology for TNF—use assisted
or installer-provisioned methods.

```text
 Manufacturing cell / retail store
┌──────────────────────────────────────────────────────────────┐
│  Two-Node OpenShift with Arbiter (TNA)                       │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────┐  │
│  │ Control plane│  │ Control plane│  │ Arbiter            │  │
│  │ + workers    │  │ + workers    │  │ etcd voter only    │  │
│  │ (node 0)     │  │ (node 1)     │  │ no API, no VMs     │  │
│  │ pods + VMs   │  │ pods + VMs   │  │                    │  │
│  └──────┬───────┘  └──────┬───────┘  └──────────┬─────────┘  │
│         └──────── etcd quorum (3 of 3) ─────────┘            │
│                           │                                  │
│                           v                                  │
│              shared CSI (RWX if you need live migration)     │
└───────────────────────────┬──────────────────────────────────┘
                            │ WAN (may be thin)
                            v
                     hub / content source
```

**Why it fits**

- Site-local HA without a third full hypervisor. TNA is the default I put on
  the whiteboard when a NUC-class third box exists; TNF is the conversation
  when it does not and BMC fencing is tested.
- OpenShift Virtualization can live-migrate if storage is RWX. Local LVMS on
  each node is still one failure domain per disk—do not sell migration on
  host-local PVs.

**Wrong answer when:** there is no third host *and* BMC fencing is not real, or
the only copy of VM disks is a local LV. That is still SNO economics with extra
etcd theory. If you can buy three equal servers, compact is simpler than
explaining an arbiter to the plant.

## Example D — Compact site and a hub that runs the fleet

**Scenario:** A larger plant, campus, or regional facility that either (a) needs
more than two nodes of capacity/HA at the site, or (b) acts as the management
hub for dozens to thousands of spoke sites. Telco and far-edge fleets made this
pattern famous; manufacturing and retail fleets hit the same operational wall.

**Site shape:** Assisted service and
[GitOps Zero Touch Provisioning (ZTP)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/edge_computing/index)
support single-node, **three-node**, and standard bare-metal clusters. A
three-node compact-style site (combined control/worker roles) is the step up
from two-node when you want a full OpenShift quorum on three equal boxes
without a datacenter footprint. Dedicated control-plane nodes plus workers
appear when the site justifies separating those roles. Confirm current
edge-computing docs before you assume `ClusterInstance` covers TNA; TNF is
explicitly not a validated ZTP topology.

**Hub shape:** A hub cluster runs
[Red Hat Advanced Cluster Management (RHACM)](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/)
in a hub-and-spoke model. GitOps ZTP keeps site definitions and desired
configuration in Git; the hub’s assisted service provisions spokes; policies
and lifecycle tooling keep day-2 aligned across the fleet. At scale, that is how
you avoid “SSH to each site and hope.” For a PoC-sized hub (SNO + RHACM + spoke
provisioning), follow
[how to get started with an OpenShift PoC](/posts/getting-started-openshift-poc/)
and the
[hub-and-spoke (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/install-the-cluster/other-installation-methods/hub-and-spoke/)
guide.

```text
 Git (site defs + policies)
        │
        v
┌───────────────────────────────────────────┐
│ Near-edge / regional hub                  │
│  RHACM + assisted service                 │
│  OpenShift GitOps (ZTP pipeline)          │
│  content mirrors / release images         │
└───────┬─────────────┬─────────────┬───────┘
        │ provision   │ provision   │ policy +
        │ + lifecycle │ + lifecycle │ content
        v             v             v
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│ Spoke site   │ │ Spoke site   │ │ Spoke site   │
│ SNO /        │ │ two-node     │ │ three-node / │
│              │ │ TNA or TNF   │ │ standard     │
│ local apps   │ │ local apps   │ │ local apps   │
│ local cache  │ │ local cache  │ │ local cache  │
└──────────────┘ └──────────────┘ └──────────────┘
        ▲             ▲             ▲
        └─────────────┴─────────────┘
           sites keep running if WAN
           blips; hub owns fleet sameness
```

**What belongs where**

| Concern                                  | Spoke / site                                              | Hub / near edge                                      |
| ---------------------------------------- | --------------------------------------------------------- | ---------------------------------------------------- |
| Production workloads                     | Yes — keep them local                                     | Aggregate only when latency/policy requires it       |
| Install & desired config                 | Declared per site (`ClusterInstance` and related CRs)     | Git + RHACM/assisted service drive provisioning      |
| Content (releases, operators, app images) | Local cache/mirror as needed                              | Central mirrors and channel policy                   |
| Fleet policy & compliance                | Enforced locally once applied                             | Author and distribute from the hub                   |
| Observability                            | Local signals for break-glass                             | Aggregation and alerting for the NOC                 |

Keep ZTP discussions architectural in early reviews: declarative site
definitions, policy groups for single-node vs three-node vs standard shapes,
and Topology Aware Lifecycle Manager patterns for controlled rollouts. Two-node
sites use the documented installer path until ZTP coverage is explicit. Full
policy YAML belongs in the Git repo, not on the first architecture slide.

## Storage options at the edge

Form factor picks the cluster shape. Storage picks whether that shape can host
stateful workloads without pretending the site is a datacenter. Keep the
conversation on **where the disks live**, **what failure domain you accept**,
and **whether you need block only or also file/object**.

```text
 Workloads (PVC / VM disk)
           │
           v
 ┌─────────────────────┐
 │ StorageClass choice │
 └──────────┬──────────┘
            │
   ┌────────┼─────────┬──────────────────┐
   v        v         v                  v
 LVMS    LSO/local  External CSI      ODF (when
 (host    volumes   (array / SAN)     footprint +
 disks)                               HA justify)
```

### Logical Volume Manager Storage (LVMS)

The default answer for many edge sites. [LVM Storage](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/storage/persistent-storage-using-local-storage)
(TopoLVM CSI) turns unused disks or partitions on the node into dynamically
provisioned PVs. It shows up in two places you already met above:

- **MicroShift** ships LVMS as the built-in CSI provider for dynamic
  provisioning on the device ([MicroShift storage](https://docs.redhat.com/en/documentation/red_hat_build_of_microshift/4.22/html/storage/index)).
- **SNO / two-node / compact** commonly install LVM Storage when there is a raw
  disk and you want PVCs without standing up an array stack.

**Fits when:** local disks are enough, dynamic PVC provisioning matters, and
you accept that data lives with the node (or thin-pool snapshot discipline you
actually test). On multi-node clusters, LVMS still provisions *local* storage—it
does not magically replicate across nodes.

**Lab path:** attaching an external NVMe namespace and consuming it with LVMS on
SNO is exactly the pattern in
[Pure FlashArray on SNO with NVMe/TCP](/posts/pure-flasharray-sno-nvme-tcp/).

### Local Storage Operator (and friends)

[Local Storage Operator (LSO)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/storage/persistent-storage-using-local-storage)
and related local-volume patterns still matter when you want explicit PVs from
named devices, or when another stack (for example OpenShift Data Foundation
internal mode) expects local volumes as the underlying capacity. Prefer LVMS
for most greenfield SNO “just give me a StorageClass” conversations; reach for
LSO when the design calls for static local PVs or a documented dependency on
them.

### External array CSI (site has a real array)

Some sites already own SAN/NAS gear—or a small flash array in the rack. Then
the edge cluster is a *consumer*, not the storage product:

- Block over **NVMe/TCP**, **iSCSI**, Fibre Channel, or vendor CSI
- Array features (snapshots, clones, QoS) stay on the array; OpenShift binds
  PVCs through the CSI driver
- Network design matters: storage VLANs, multipath, and “what happens when the
  array path blips” belong in the architecture review

Examples from this site:
[Dell Unity over iSCSI for OpenShift Virtualization](/posts/openshift-virt-dell-unity-iscsi/)
and the Pure NVMe/TCP + LVMS lab above (array presents a namespace; LVMS or CSI
owns the Kubernetes surface).

**Fits when:** capacity, performance, or backup already lives on shared storage
and the OpenShift node should not be the only copy of truth. **Wrong answer
when:** the “array” is really one USB disk and you are inventing operational
complexity for a single failure domain.

### OpenShift Data Foundation (ODF)

[OpenShift Data Foundation](https://docs.redhat.com/en/documentation/red_hat_openshift_data_foundation/)
is the consolidated block/file/object answer when the site needs Ceph-backed
services, replication, or S3-style object—not merely a local PVC. It is also
the heavier footprint: more CPU/RAM/disk, more day-2, and clearer multi-disk /
multi-node expectations.

**Fits when:** three-node (or larger) sites need resilient storage services,
object storage, or a storage platform that matches regional/datacenter ODF
muscle memory. Two-node ODF, where it exists, landed on **fencing** in ODF
4.22—not on the arbiter—so confirm the current ODF guide before anyone draws
OSDs on TNA. **Usually wrong for:** MicroShift appliances and lean SNO cells
whose recovery model is rebuild-from-spare—LVMS (or external CSI) is the
smaller honest design.

None of LVMS, LSO, or host-local patterns replace object storage by themselves.
If the app needs S3 APIs at the site, plan ODF (or an external object endpoint)
explicitly—do not assume a local `StorageClass` covers it.

### Storage chooser (edge)

| Site reality                                                                          | Lean toward                                                                                                          |
| ------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| Device Edge / MicroShift, local disks                                                 | Built-in LVMS                                                                                                        |
| SNO, spare disk, dynamic PVCs, rebuild-from-spare OK                                  | LVM Storage                                                                                                          |
| Two-node HA, live migration required                                                  | Shared RWX CSI (array or ODF)—not host-local LVMS                                                                    |
| Named local devices / ODF internal dependency                                         | Local Storage Operator                                                                                               |
| Existing array in the rack; CSI or NVMe/TCP/iSCSI path                                | External array + CSI (or array LUN → LVMS when that is the documented pattern)                                       |
| Multi-node site needs replicated block/file/object                                    | OpenShift Data Foundation                                                                                            |
| App needs S3 at the edge                                                              | ODF or external object—call it out early                                                                             |

Storage should match the failure domain you already accepted for the form
factor. SNO plus LVMS is coherent. SNO plus “datacenter HA storage expectations”
is how edge projects get stuck in review.

## Decision guide

| Constraint                                                       | Lean toward                                                              |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------ |
| Extreme footprint, intermittent WAN, appliance lifecycle         | MicroShift / Device Edge                                                 |
| Full OpenShift API on one host; rebuild-from-spare OK            | Single Node OpenShift                                                    |
| Two hypervisor-class servers; a small third host exists          | Two-node with arbiter (TNA)                                              |
| Strictly two boxes; BMC/Redfish fencing is real and tested       | Two-node with fencing (TNF)                                              |
| Site needs three-node quorum / more local capacity               | Three-node compact or small multi-node                                   |
| Many similar sites, bare-metal factory installs                  | RHACM + GitOps ZTP early (not TNF)                                       |
| Disconnected or thin WAN                                         | Content mirrors and pinned upgrades before day 1                         |
| Leftover VMs at a site that already needs full OCP               | SNO (no live migration), two-node, or compact—not MicroShift             |
| Stateful PVCs on local disks at SNO/MicroShift                   | LVM Storage (LVMS)                                                       |
| Shared array already in the rack                                 | External CSI / NVMe/TCP / iSCSI                                          |
| Replicated block/file/object at a larger site                    | OpenShift Data Foundation                                                |

A useful facilitation line: *“If this site dies, what is the recovery
unit—reimage a device, rebuild one OpenShift node, fail over across two, or
quorum across three?”*
That answer selects the form factor faster than a feature matrix.

## The solutions architect takeaway

1. **Edge is a spectrum** — device, site, and hub are different architectures
   that share a brand name only at the marketing layer.
2. **Form factor follows failure domain and footprint** — MicroShift, SNO,
   two-node, and compact/multi-node solve different constraints; do not stretch
   one to cover the others.
3. **Fleet ops is the multiplier** — once you leave a handful of sites, RHACM
   and GitOps ZTP are how install and drift stay intentional. The same hub is
   how you operate VMs across those clusters—see
   [ACM as the fleet control plane for OpenShift VMs](/posts/acm-openshift-virtualization/).
   After install, GitOps should feed that hub’s policies rather than push
   platform CRs to every spoke—see
   [GitOps should manage ACM, not the cluster](/posts/gitops-should-manage-acm/).
4. **Connectivity is a day-0 design input** — mirrors, upgrade windows, and
   break-glass access decide whether the pretty topology survives first contact
   with the WAN.
5. **Storage follows the failure domain** — LVMS for local disks, external CSI
   when an array is real, ODF when the site earns replicated block/file/object.
   Disk types, IOPS, and what fails per architecture are in
   [OpenShift storage performance](/posts/openshift-storage-performance/).

Start the next conversation with constraints, not product logos: how much
hardware, how much downtime, how bad the network, how many identical sites,
and where state is allowed to live. Pick the form factor that matches, then
make the fleet boring on purpose.

Hub-and-spoke densification of *control planes* (hosted vs virtualized) is a
related fleet conversation—see
[hosted vs virtualized control planes](/posts/hosted-vs-virtualized-control-planes/).
In bare-metal PoCs that reboot constantly while you prove a site shape,
[temporarily disabling firmware memory checks](/posts/poc-faster-bare-metal-boot-disable-memory-check/)
can reclaim hours of POST wait (restore before handback).

## Related posts

- [How to Get Started with an OpenShift PoC](/posts/getting-started-openshift-poc/)
- [OpenShift Storage Performance: Disks, IOPS, Architectures](/posts/openshift-storage-performance/)
- [Hosted vs Virtualized Control Planes on OpenShift 4.22](/posts/hosted-vs-virtualized-control-planes/)
- [Pure FlashArray on Single Node OpenShift with NVMe/TCP](/posts/pure-flasharray-sno-nvme-tcp/)
- [ACM as the fleet control plane for OpenShift VMs](/posts/acm-openshift-virtualization/)

> Want help applying this in your environment? Reach out to your Red Hat
> account team—or evaluate one representative site pattern in a lab before you
> scale the GitOps factory.
{: .prompt-tip }

## Further reading

- [Edge computing (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/edge_computing/index)
- [Installing on a single node (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/installing_on_a_single_node/index)
- [Installing a two-node OpenShift cluster (4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/installing_a_two_node_openshift_cluster/index)
- [Two-node with arbiter (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/installing_a_two_node_openshift_cluster/about-two-node-arbiter-installation)
- [Two-node with fencing (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/installing_a_two_node_openshift_cluster/two-node-with-fencing)
- [Understanding MicroShift (4.22)](https://docs.redhat.com/en/documentation/red_hat_build_of_microshift/4.22/html/understanding_microshift/microshift-understanding)
- [Red Hat Device Edge](https://www.redhat.com/en/technologies/device-edge)
- [MicroShift storage (4.22)](https://docs.redhat.com/en/documentation/red_hat_build_of_microshift/4.22/html/storage/index)
- [Persistent storage using local storage (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/storage/persistent-storage-using-local-storage)
- [Red Hat OpenShift Data Foundation documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_data_foundation/)
- [ODF 4.22 new features — two-node fencing](https://docs.redhat.com/en/documentation/red_hat_openshift_data_foundation/4.22/html/4.22_release_notes/new_features)
- [Red Hat Advanced Cluster Management documentation](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/)
- [OpenShift PoC overview](https://openshift-ssa.github.io/openshift-poc/home/)
- [Architecture — hub and spoke (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/home/architecture/)
- [Hub and spoke install (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/install-the-cluster/other-installation-methods/hub-and-spoke/)
- [OpenShift GitOps (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/configure-the-cluster/openshift-gitops/)
- [OpenShift Data Foundation (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/configure-the-cluster/storage/odf/)
