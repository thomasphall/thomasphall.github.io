---
title: "OpenShift Edge Architectures: Form Factor, Then Fleet"
description: >-
  Compare MicroShift, Single Node OpenShift, and hub-and-spoke edge
  patterns—plus LVMS, external CSI, and ODF storage that matches each
  site’s failure domain.
date: 2026-08-04 16:00:00 -0500
categories: [OpenShift]
tags: [openshift, edge, sno, gitops, storage]
permalink: /posts/openshift-edge-architectures/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization.
{: .prompt-info }

Architecture reviews rarely fail because someone forgot to say “OpenShift at
the edge.” They fail because that phrase hides five different designs. A
resource-constrained gateway, a single-rack plant cell, and a regional hub that
installs a thousand spokes are all “edge”—and they want different form factors,
different failure domains, and different day-2 muscle memory.

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
 Far / device edge          Site edge                 Near-edge hub
┌──────────────────┐     ┌──────────────────┐     ┌──────────────────────┐
│ MicroShift       │     │ SNO or           │     │ RHACM + GitOps ZTP   │
│ Device Edge      │────▶│ three-node       │◀───▶│ content mirrors      │
│ (appliance host) │     │ (plant / store)  │     │ fleet lifecycle      │
└──────────────────┘     └──────────────────┘     └──────────────────────┘
   footprint first          full OCP API              scale the sameness
```

## Example A — Device edge with MicroShift

**Scenario:** An industrial gateway or kiosk-class host that must run a small
set of containerized services next to sensors or a local UI. Power and rack
space are scarce; WAN is unreliable; nobody wants a full OpenShift control plane
on the box.

**Architecture:** [Red Hat build of MicroShift](https://docs.redhat.com/en/documentation/red_hat_build_of_microshift/4.22/html/understanding_microshift/microshift-understanding)
on an edge-optimized OS such as RHEL for Edge. Together, that pairing is the
[Red Hat Device Edge](https://www.redhat.com/en/technologies/linux-platforms/device-edge)
story: a single-node Kubernetes runtime aimed at resource-constrained field
environments, with a focused API surface for orchestration, networking, ingress,
storage, and security.

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
│  │ RHEL for Edge (rpm-ostree image)       │  │
│  │  OS lifecycle, updates, local storage  │  │
│  └────────────────────────────────────────┘  │
└───────────────────────┬──────────────────────┘
                        │ intermittent / thin WAN
                        v
              optional fleet / image source
              (not a full OCP control plane)
```

**Why it fits**

- Footprint and networking constraints are first-class design goals, not
  afterthoughts.
- Devices are largely self-managing; OS-level image and update patterns carry
  much of the lifecycle that a full OpenShift cluster would handle with
  operators and OLM.
- Teams can still speak Kubernetes/`oc` for the workloads that matter locally.

**What you give up (say it out loud)**

- MicroShift is **not** full OpenShift Container Platform. It does not bring the
  whole operator, console, and multi-node HA story with it.
- It does not support workload HA or horizontal scale by adding workers.
- Virtual machines, when needed, are an OS/host concern—not OpenShift
  Virtualization on that device.

**Wrong answer when:** stakeholders assume every OpenShift API, OperatorHub
catalog, or multi-node pattern will “just work” on the gateway. If the site
needs the full platform surface, step up to SNO or compact—not a stretched
definition of MicroShift.

## Example B — Single Node OpenShift at the site

**Scenario:** A manufacturing cell or retail store with one capable bare-metal
server (or equivalent). The team wants the **full OpenShift API** for operators,
GitOps, and familiar platform services, but site HA is not the priority.
Rebuild-from-spare or overnight recovery is acceptable; dual control-plane
racks are not in the budget.

**Architecture:**
[Single Node OpenShift (SNO)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/installing_on_a_single_node/index)—
control plane and workers co-located on one node. Common companions at the
site:

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
for multi-AZ HA. If the plant cannot tolerate that node going dark, SNO is the
wrong form factor no matter how attractive the BOM looks.

**Connectivity reality:** plan content delivery and upgrade windows before day
1. Disconnected or bandwidth-limited sites need mirrors, release images, and a
break-glass story that works when the hub is unreachable.

## Example C — Compact site and a hub that runs the fleet

**Scenario:** A larger plant, campus, or regional facility that either (a) needs
more than one node of capacity/HA at the site, or (b) acts as the management
hub for dozens to thousands of spoke sites. Telco and far-edge fleets made this
pattern famous; manufacturing and retail fleets hit the same operational wall.

**Site shape:** Assisted service and
[GitOps Zero Touch Provisioning (ZTP)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/edge_computing/index)
support single-node, **three-node**, and standard bare-metal clusters. A
three-node compact-style site (combined control/worker roles) is the usual step
up from SNO when you want OpenShift quorum and more local capacity without a
full datacenter footprint. Dedicated control-plane nodes plus workers appear
when the site justifies separating those roles.

**Hub shape:** A hub cluster runs
[Red Hat Advanced Cluster Management (RHACM)](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/)
in a hub-and-spoke model. GitOps ZTP keeps site definitions and desired
configuration in Git; the hub’s assisted service provisions spokes; policies
and lifecycle tooling keep day-2 aligned across the fleet. At scale, that is how
you avoid “SSH to each site and hope.” For a PoC-sized hub (SNO + RHACM + spoke
provisioning), follow
[how to get started with an OpenShift PoC](/posts/getting-started-openshift-poc/)
and the
[OpenShift PoC fleet management](https://openshift-ssa.github.io/openshift-poc/fleet-management/)
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
│ SNO          │ │ three-node   │ │ standard /   │
│              │ │ compact      │ │ larger       │
│ local apps   │ │ local apps   │ │ local apps   │
│ local cache  │ │ local cache  │ │ local cache  │
└──────────────┘ └──────────────┘ └──────────────┘
        ▲             ▲             ▲
        └─────────────┴─────────────┘
           sites keep running if WAN
           blips; hub owns fleet sameness
```

**What belongs where**

| Concern | Spoke / site | Hub / near edge |
| ------- | ------------ | --------------- |
| Production workloads | Yes — keep them local | Aggregate only when latency/policy requires it |
| Install & desired config | Declared per site (`ClusterInstance` and related CRs) | Git + RHACM/assisted service drive provisioning |
| Content (releases, operators, app images) | Local cache/mirror as needed | Central mirrors and channel policy |
| Fleet policy & compliance | Enforced locally once applied | Author and distribute from the hub |
| Observability | Local signals for break-glass | Aggregation and alerting for the NOC |

Keep ZTP discussions architectural in early reviews: declarative site
definitions, policy groups for single-node vs three-node vs standard shapes,
and Topology Aware Lifecycle Manager patterns for controlled rollouts. Full
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
- **SNO / compact** commonly install LVM Storage when there is a raw disk and
  you want PVCs without standing up an array stack.

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
muscle memory. **Usually wrong for:** MicroShift appliances and lean SNO cells
whose recovery model is rebuild-from-spare—LVMS (or external CSI) is the
smaller honest design.

None of LVMS, LSO, or host-local patterns replace object storage by themselves.
If the app needs S3 APIs at the site, plan ODF (or an external object endpoint)
explicitly—do not assume a local `StorageClass` covers it.

### Storage chooser (edge)

| Site reality | Lean toward |
| ------------ | ----------- |
| Device Edge / MicroShift, local disks | Built-in LVMS |
| SNO, spare disk, dynamic PVCs, rebuild-from-spare OK | LVM Storage |
| Named local devices / ODF internal dependency | Local Storage Operator |
| Existing array in the rack; CSI or NVMe/TCP/iSCSI path | External array + CSI (or array LUN → LVMS when that is the documented pattern) |
| Multi-node site needs replicated block/file/object | OpenShift Data Foundation |
| App needs S3 at the edge | ODF or external object—call it out early |

Storage should match the failure domain you already accepted for the form
factor. SNO plus LVMS is coherent. SNO plus “datacenter HA storage expectations”
is how edge projects get stuck in review.

## Decision guide

| Constraint | Lean toward |
| ---------- | ----------- |
| Extreme footprint, intermittent WAN, appliance lifecycle | MicroShift / Device Edge |
| Full OpenShift API on one host; rebuild-from-spare OK | Single Node OpenShift |
| Site needs quorum / more local capacity | Three-node or small multi-node |
| Many similar sites, bare-metal factory installs | RHACM + GitOps ZTP early |
| Disconnected or thin WAN | Content mirrors and pinned upgrades before day 1 |
| Leftover VMs at a site that already needs full OCP | SNO/compact + OpenShift Virtualization—not MicroShift |
| Stateful PVCs on local disks at SNO/MicroShift | LVM Storage (LVMS) |
| Shared array already in the rack | External CSI / NVMe/TCP / iSCSI |
| Replicated block/file/object at a larger site | OpenShift Data Foundation |

A useful facilitation line: *“If this site dies, what is the recovery
unit—reimage a device, rebuild one OpenShift node, or fail over across three?”*
That answer selects the form factor faster than a feature matrix.

## The SA takeaway

1. **Edge is a spectrum** — device, site, and hub are different architectures
   that share a brand name only at the marketing layer.
2. **Form factor follows failure domain and footprint** — MicroShift, SNO, and
   compact/multi-node solve different constraints; do not stretch one to cover
   the others.
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
- [Hosted vs Virtualized Control Planes on OpenShift 4.22](/posts/hosted-vs-virtualized-control-planes/)
- [GitOps Should Manage ACM, Not the Cluster](/posts/gitops-should-manage-acm/)
- [Pure FlashArray on Single Node OpenShift with NVMe/TCP](/posts/pure-flasharray-sno-nvme-tcp/)

> Want help applying this in your environment? Reach out to your Red Hat
> account team—or evaluate one representative site pattern in a lab before you
> scale the GitOps factory.
{: .prompt-tip }

## Further reading

- [Edge computing (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/edge_computing/index)
- [Installing on a single node (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/installing_on_a_single_node/index)
- [Understanding MicroShift (4.22)](https://docs.redhat.com/en/documentation/red_hat_build_of_microshift/4.22/html/understanding_microshift/microshift-understanding)
- [MicroShift storage (4.22)](https://docs.redhat.com/en/documentation/red_hat_build_of_microshift/4.22/html/storage/index)
- [Persistent storage using local storage (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/storage/persistent-storage-using-local-storage)
- [Red Hat OpenShift Data Foundation documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_data_foundation/)
- [Red Hat Advanced Cluster Management documentation](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/)
- [OpenShift PoC overview](https://openshift-ssa.github.io/openshift-poc/home/)
- [Architecture — hub and spoke (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/home/architecture/)
- [Fleet management (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/fleet-management/)
- [Hub install on SNO (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/fleet-management/sno-hub/)
- [Advanced Cluster Management (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/fleet-management/acm-install/)
- [OpenShift GitOps (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/post-installation/openshift-gitops/)
- [OpenShift Data Foundation (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/post-installation/storage/odf/)
