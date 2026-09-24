---
title: "Two-Node + Arbiter for Edge OpenShift Virtualization"
description: >-
  SNO is one failure domain. Two-Node OpenShift with Arbiter (TNA) adds a
  tiny etcd voter so two edge hosts can run OpenShift Virtualization with
  live migration.
date: 2026-09-02 16:00:00 -0500
categories: [OpenShift, Virtualization]
tags: [openshift, openshift-virtualization, edge, sno, storage, gitops]
permalink: /posts/two-node-arbiter-edge-virtualization/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization.
{: .prompt-info }

The
[OpenShift edge architectures](/posts/openshift-edge-architectures/)
post maps the spectrum on
[Red Hat OpenShift](https://www.redhat.com/en/technologies/cloud-computing/openshift):
MicroShift when the box is an appliance,
[Single Node OpenShift (SNO)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/installing_on_a_single_node/index)
when rebuild-from-spare is the recovery model, three-node compact when the
site earns a full quorum. Architecture reviews for
[OpenShift Virtualization](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/index)
at the plant or store keep landing in the gap between those last two.

The plant cannot tolerate the node going dark. The bill of materials cannot
tolerate a third full hypervisor. That is
[Two-Node OpenShift with Arbiter (TNA)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/installing_a_two_node_openshift_cluster/about-two-node-arbiter-installation):
two schedulable control-plane hosts plus a tiny third voter that exists so
etcd does not lose quorum when one of the real nodes dies.

This post is that form factor, aimed at edge virtualization on
OpenShift Container Platform 4.22. It is a solutions-architect map, not an
install runbook. Confirm the
[Installing a two-node OpenShift cluster](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/installing_a_two_node_openshift_cluster/index)
procedure for the installer you will actually use.

## The gap SNO does not close

SNO is the right answer when platform consistency matters more than
site-local high availability (HA). Control plane and workloads share one
failure domain. Virtual machines (VMs) on that node share fate with the
box. There is nowhere to live-migrate. That is honest. It is also why a
VMware two-host cluster conversation rejects SNO on the first slide.

Three-node compact closes the HA conversation by buying a third full
control plane that also runs workloads. Many edge sites will not. Power,
rack units, and the cost of a third hypervisor-class server are the
constraint—not etcd theory. TNA is the topology OpenShift added so that
constraint does not force a false choice between “one box” and “three
equal boxes.”

```text
 Far / device edge          Site edge                      Near-edge hub
┌──────────────────┐     ┌─────────────────────────┐     ┌──────────────────┐
│ MicroShift       │     │ SNO                     │     │ RHACM + GitOps   │
│ Device Edge      │────▶│ Two-node + arbiter      │◀───▶│ content mirrors  │
│                  │     │ Three-node compact      │     │                  │
└──────────────────┘     └─────────────────────────┘     └──────────────────┘
   no Virt here             TNA is the virt step-up         fleet sameness
                            from SNO without a third
                            full hypervisor
```

MicroShift still does not host OpenShift Virtualization. SNO still can,
with no HA. TNA is where leftover VMs at a two-server site get a real
OpenShift control plane *and* a place for those VMs to go when you drain
a node.

## What the arbiter is

A TNA cluster is two control-plane nodes plus one **local** arbiter.
The arbiter stores a full etcd copy so Raft still has three voters. It
does **not** run `kube-apiserver` or `kube-controller-manager`. It does
**not** run workloads. Product documentation is explicit: remote arbiter
nodes are not supported. Keep it on the same site, on a different power
domain if you can, not in a region you called “the cloud arbiter.”

```text
 Manufacturing cell / retail store
┌──────────────────────────────────────────────────────────────┐
│  Two-Node OpenShift with Arbiter                             │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────┐  │
│  │ Control plane│  │ Control plane│  │ Arbiter            │  │
│  │ + workers    │  │ + workers    │  │ etcd voter only    │  │
│  │ (node 0)     │  │ (node 1)     │  │ no API, no VMs     │  │
│  │ pods + VMs   │  │ pods + VMs   │  │ 2 vCPU / 8 GiB /   │  │
│  └──────┬───────┘  └──────┬───────┘  │ 50 GB class        │  │
│         │                 │          └──────────┬─────────┘  │
│         └──────── etcd quorum (3 of 3) ─────────┘            │
│                           │                                  │
│                           v                                  │
│                 RWX block CSI (live migration)               │
└───────────────────────────┬──────────────────────────────────┘
                            │ WAN (may be thin)
                            v
                     hub / content source
```

Installer minimums on 4.22 (Agent-based Installer) are a floor, not a
virtualization bill of materials:

| Role | vCPU | Memory | Storage |
| ---- | ---- | ------ | ------- |
| Each control plane (also runs compute) | 4 | 16 GB | 120 GB SSD-class |
| Arbiter | 2 | 8 GB | 50 GB SSD-class |

Size the two control planes for the VMs, not for the installer table.
The arbiter can be NUC-class hardware. etcd still wants a fast disk:
the same `wal_fsync_duration_seconds` p99 under 10 ms story as any
control plane—see
[OpenShift storage performance](/posts/openshift-storage-performance/).
Product docs allow end-to-end latency under 500 ms including disk I/O,
with the etcd slow profile in high-latency environments. That is a
ceiling, not a design target. Colocate the three members. Design as if
etcd still wants tens of milliseconds, because it does.

**Topology lock-in, say it on the slide.** After install you can add
workers—do not add more than two. You cannot convert TNA into a standard
three-control-plane cluster later. Pick TNA because the site will stay
this shape, not because it is a stepping stone to a datacenter cluster.

Install paths that document the arbiter role today are the
[Agent-based Installer](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/installing_an_on-premise_cluster_with_the_agent-based_installer/preparing-to-install-with-agent-based-installer)
and the
[Assisted Installer](https://docs.redhat.com/en/documentation/assisted_installer_for_openshift_container_platform/2026/html/installing_openshift_container_platform_with_the_assisted_installer/index)
(control-plane count `2` plus at least one host with the arbiter role).
TNA is bare-metal. It has been generally available since OpenShift 4.20;
4.22 is the line this site uses. Confirm the support statement on the
installer you pick—Assisted Installer topics have lagged the dedicated
two-node book.

## Why this is the edge virt form factor

OpenShift Virtualization is supported on TNA. The two control-plane
nodes are schedulable. That is the whole point: two hypervisors, one
small quorum device, full OpenShift API.

What you actually buy with the second node:

- **Control-plane HA** — one full node can die and etcd still has
  quorum (surviving control plane plus arbiter). The API stays up.
- **A drain target** — you can live-migrate VMs off a node you are
  patching, *if* the disk is ReadWriteMany (RWX).
- **A restart target** — `runStrategy: Always` or `RerunOnFailure` can
  start the VM on the survivor after a crash, *if* the disk can attach
  there.

What you do not buy:

- A third hypervisor. The arbiter will not take the VMs.
- Headroom for two equal production loads. When one node is gone, every
  VM that still runs sits on the survivor. Size for N+1 on **two**
  boxes, not on three.
- Live migration during a dual failure. Two nodes plus an arbiter is
  still a small cluster.

Passthrough GPUs and other host devices still block live migration, same
as on a six-node cluster. Set `evictionStrategy: None` for those VMs and
accept a power-off on drain. TNA does not invent a workaround.

## Storage is the real architecture review

Control-plane quorum and VM HA are different slides. TNA gives you the
first. Storage decides the second.

Live migration needs
[RWX](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/live-migration)
and, for VM disks, **Block** volume mode. LVM Storage (LVMS) and the
Local Storage Operator bind a volume to one node. That is the SNO
pattern. It is still RWO on TNA. A VM on LVMS does not live-migrate; it
powers off with the node. Fine for a lab disk. Wrong for the reason you
bought a second hypervisor.

| Site storage | TNA virt fit | Notes |
| ------------ | ------------ | ----- |
| External array + certified CSI (NVMe/TCP, iSCSI, FC) | Default when the rack already has an array | Same model as [Dell Unity over iSCSI](/posts/openshift-virt-dell-unity-iscsi/) or a FlashArray; do not stack SDS on top |
| Partner HCI SDS on the two nodes (Portworx, LINSTOR, others) | Default when the disks are in the hosts | Arbiter stays storageless / metadata-only; replicas live on the two hypervisors. Shortlist: [vSAN-like storage for OpenShift Virtualization Engine](/posts/ove-vsan-storage-alternatives/) |
| LVMS / host-local RWO | Lab, or VMs that may die with the node | Coherent with SNO. Not why you added a second host |
| OpenShift Data Foundation (ODF) internal | Do not assume TNA | ODF 4.22 added support for **two-node with fencing**, not for TNA as the Ceph topology. Confirm the current ODF deployment guide before anyone draws OSDs on the arbiter |

The Portworx design for TNA is the clean mental model for local-disk
SDS: a three-member storage cluster where the arbiter holds metadata and
must not take volume replicas. Whatever CSI you pick, write that
constraint down. The arbiter is not a third vSAN-style fault domain for
data.

[OpenShift Virtualization Engine (OVE)](https://www.redhat.com/en/technologies/cloud-computing/openshift/virtualization-engine)
still does not include ODF. Edge TNA on OVE is almost always array CSI
or a certified partner SDS. That is the same OVE storage conversation as
the datacenter, on a smaller node count.

## What happens when a node fails

Walk this in the review. Do not skip to “we have HA.”

**One control-plane host is down, arbiter and the other host are up.**
etcd has two of three. The API works. VMs that were already on the
survivor keep running. VMs on the dead host restart on the survivor only
if the PVC can attach there (RWX, or a replica on that node). Live
migration does not apply to a dead host; that is a crash restart. Fence
the initiator before you start the disk somewhere else—see
[Fence gray host failures on OpenShift Virtualization](/posts/openshift-virt-gray-failure-ha/).
Until the failed host returns, you are running degraded: one hypervisor
and no second drain target.

**Arbiter is down, both control planes are up.** Workloads are fine.
etcd is two of three. Repair the NUC. Do not treat arbiter loss as a
reason to panic-reboot hypervisors.

**Network split between the two hypervisors, each still sees the
arbiter.** That is why the arbiter exists. Quorum stays well-defined.
Do not invent a second, remote voter to “make it safer.”

**Both hypervisors are gone.** The arbiter does not run VMs. Recovery is
rebuild or restore, same family of problem as SNO, with two boxes to
reimage instead of one.

## TNA versus two-node with fencing

OpenShift 4.22 ships a sibling topology:
[two-node OpenShift with fencing (TNF)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/installing_a_two_node_openshift_cluster/two-node-with-fencing),
generally available in this release. TNF is a true two-box cluster. There
is no arbiter. Pacemaker and Redfish on the BMC fence a node so etcd does
not split-brain. TNF does not support extra compute nodes. It needs
working BMCs. ODF 4.22’s two-node support landed on **fencing**, not on
the arbiter. GitOps Zero Touch Provisioning is not a validated topology
for TNF—use the Assisted Installer or an installer-provisioned method.
Do not assume a `ClusterInstance` covers TNA either; confirm the current
edge-computing docs before a fleet design depends on it.

| Constraint | Lean toward |
| ---------- | ----------- |
| Two hypervisor-class servers plus a tiny third host; etcd should stay Kubernetes-native | **TNA** |
| Strictly two boxes; BMC/Redfish is real and tested | TNF |
| First-party ODF on two data nodes | Confirm TNF + ODF 4.22, not TNA |
| Array already in the rack; want live migration | TNA or compact + that CSI |
| Cannot spare even a NUC, cannot fence via BMC | You do not have a two-node HA design. That is SNO. |

TNA is the default I put on the whiteboard for edge virt when the site
can find a small third machine. TNF is the conversation when it cannot,
and the account is willing to operate Pacemaker-backed etcd.

## Decision guide

| Constraint | Lean toward |
| ---------- | ----------- |
| Appliance, no OpenShift Virtualization | MicroShift / Device Edge |
| Full OpenShift API; rebuild-from-spare OK; VMs may die with the node | SNO |
| Two hypervisor-class servers; VMs must restart or migrate; a small third host exists | **TNA** |
| Same HA need; no third host; BMC fencing is acceptable | TNF |
| Three equal servers, or you might grow past two extra workers | Three-node compact or standard |
| Leftover VMs, local disks only, no RWX plan | SNO or TNA-as-SNO—do not sell live migration |
| Many similar sites | Same hub-and-spoke fleet model as other site shapes |

A useful facilitation line: *“If one hypervisor dies, where does the VM
run, and which disk does it attach?”* If the answer is “nowhere” or
“the PVC is on that host,” TNA without RWX is an expensive SNO. If the
answer is “the other node, same RWX volume,” TNA is doing its job.

Fleet operations do not change. Once you leave a handful of sites,
[Red Hat Advanced Cluster Management for Kubernetes (RHACM)](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/)
is still how you inventory and operate the VMs—see
[ACM as the fleet control plane for OpenShift VMs](/posts/acm-openshift-virtualization/).
GitOps still feeds the hub rather than every spoke—see
[GitOps should manage ACM, not the cluster](/posts/gitops-should-manage-acm/).
TNA is a spoke shape, not a new control-plane product.

## The solutions architect takeaway

1. **TNA sits between SNO and three-node compact** — two real
   hypervisors, one tiny etcd voter, full OpenShift API. It is the edge
   virt form factor when a third full server is the thing you cannot buy.
2. **The arbiter is local, small, and unschedulable** — etcd only. Remote
   arbiters are unsupported. It will not take VMs on a bad day.
3. **Quorum is not live migration** — RWX block (array CSI or certified
   SDS) is what makes the second node useful for Virtualization. LVMS is
   still one failure domain.
4. **You cannot grow this into a standard control plane later** — two
   extra workers is the documented ceiling. Pick TNA as a destination
   shape.
5. **TNF is the other two-node conversation** — no arbiter, BMC fencing,
   and where ODF 4.22’s two-node support actually landed. It is not a
   validated GitOps ZTP topology. Do not mix the two on one slide.

Start from the SNO question in the previous post: if this site dies, what
is the recovery unit? If the answer changed from “rebuild one node” to
“the other hypervisor must keep the VMs,” TNA is in scope. Then pick
storage that can attach on that hypervisor. Form factor first, disk
second, fleet tooling third.

## Related posts

- [OpenShift Edge Architectures: Form Factor, Then Fleet](/posts/openshift-edge-architectures/)
- [vSAN-like Storage for OpenShift Virtualization Engine](/posts/ove-vsan-storage-alternatives/)
- [OpenShift Hardware Vendor Reference Architectures](/posts/openshift-hardware-vendor-reference-architectures/)
- [Fence Gray Host Failures on OpenShift Virtualization](/posts/openshift-virt-gray-failure-ha/)
- [ACM as the Fleet Control Plane for OpenShift VMs](/posts/acm-openshift-virtualization/)

> Want help applying this in your environment? Reach out to your Red Hat
> account team—or evaluate one TNA site in a lab with RWX block and a
> drain test before you copy the shape across the fleet.
{: .prompt-tip }

## Further reading

- [Two-Node with Arbiter (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/installing_a_two_node_openshift_cluster/about-two-node-arbiter-installation)
- [Installing a two-node OpenShift cluster (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/installing_a_two_node_openshift_cluster/index)
- [About a local arbiter node (Agent-based Installer, 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/installing_an_on-premise_cluster_with_the_agent-based_installer/preparing-to-install-with-agent-based-installer)
- [Two-node with fencing (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/installing_a_two_node_openshift_cluster/two-node-with-fencing)
- [Live migration (OpenShift Virtualization 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/live-migration)
- [Recommended etcd practices (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/etcd/etcd-practices)
- [Edge computing (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/edge_computing/index)
- [ODF 4.22 new features — two-node fencing](https://docs.redhat.com/en/documentation/red_hat_openshift_data_foundation/4.22/html/4.22_release_notes/new_features)
- [Assisted Installer (2026)](https://docs.redhat.com/en/documentation/assisted_installer_for_openshift_container_platform/2026/html/installing_openshift_container_platform_with_the_assisted_installer/index)
- [Two-node OpenShift with fencing improves reliability at the edge (Red Hat blog)](https://www.redhat.com/en/blog/two-node-openshift-fencing-improves-reliability-edge)
- [Efficient two-node edge infrastructure with OpenShift and Portworx (Red Hat blog)](https://www.redhat.com/en/blog/efficient-two-node-edge-infrastructure-red-hat-openshift-and-portworxpure-storage)
- [OpenShift PoC overview](https://openshift-ssa.github.io/openshift-poc/home/)
- [Architecture — hub and spoke (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/home/architecture/)
- [OpenShift Virtualization (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/configure-the-cluster/virtualization/)
