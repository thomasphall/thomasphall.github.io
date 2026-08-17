---
title: "Hosted vs Virtualized Control Planes on OpenShift 4.22"
description: >-
  How hosted and virtualized control planes differ on OpenShift 4.22—isolation,
  densification, and day-2 operations—when OpenShift Virtualization is the
  hosting substrate.
date: 2026-07-27 16:00:00 -0500
categories: [OpenShift, Virtualization]
tags: [hosted-control-planes, virtualized-control-planes, openshift-virtualization, "4.22", hypershift]
permalink: /posts/hosted-vs-virtualized-control-planes/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization.
{: .prompt-info }

Platform teams rarely struggle to stand up *one* OpenShift cluster. The hard
problem shows up when the fleet grows: every standalone control plane wants
dedicated machines, quorum, patching, and capacity headroom. Densification—more
clusters on less dedicated control-plane hardware—is the conversation behind
both [hosted control planes](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/hosted_control_planes/index)
and [virtualized control planes](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualized_control_planes/vcp-overview)
in OpenShift Container Platform 4.22. A PoC walkthrough of hosted clusters on
an existing management cluster is
[OpenShift on OpenShift (Hosted Control Planes)](https://openshift-ssa.github.io/openshift-poc/installation/openshift-on-openshift/).

[OpenShift Virtualization](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/index)
often sits underneath that conversation as the hosting substrate. That does
**not** mean "hosted control planes versus OpenShift Virtualization." It means
you can densify control planes *on* virtualization in more than one way. The
real choice is isolation model and day-2 operations model. This post is a
solution-architect comparison for platform architects and virtualization teams
making that call—not an install runbook.

## Two densification models

**Hosted control planes (HCP)** decouple the control plane from the data plane.
Control-plane components—API server, etcd, controllers, and related operators—
run as pods on a *management cluster* (also called a hosting cluster). Worker
capacity for each tenant cluster is attached separately through `NodePool`
resources. Multicluster engine for Kubernetes Operator ships the HyperShift
Operator that drives this lifecycle. By default, isolation between hosted
control planes is container-level: namespaces, network policy, SCCs, and
related Kubernetes boundaries on shared management-cluster nodes.

**Virtualized control planes (VCP)** take a different cut. The *target*
cluster's control-plane *nodes* run as virtual machines on a *hosting* cluster
that already has OpenShift Virtualization. Those VMs look like servers with
BMC-style management through KubeVirt Redfish, so familiar installers—
Agent-based Installer or GitOps ZTP patterns—can treat them like physical
nodes. Isolation between target clusters is hypervisor-level: each control
plane lives inside VMs, not as pods sharing the management cluster's kernel
by default.

Red Hat documentation draws the contrast cleanly: virtualized control planes
run as VMs with hypervisor-level isolation; hosted control planes run as pods
with container-level isolation.

## Technology Preview

KubeVirt Redfish—the piece that exposes those control-plane VMs through
Redfish API endpoints for VCP—is a Technology Preview in 4.22. Technology
Preview features are not covered by Red Hat production SLAs and may change.
Treat that as a program-risk input for production architecture decisions, then
compare the two models on their architectural merits. Hosted control planes,
including OpenShift Virtualization as a hosting platform, are the denser GA
path for most fleet conversations today.

## Side-by-side

| Dimension | Hosted control planes | Virtualized control planes |
| --------- | --------------------- | -------------------------- |
| Control-plane form factor | Pods on a management cluster | VMs on a hosting cluster with OpenShift Virtualization |
| Isolation default | Container-level | Hypervisor-level |
| Cluster shape | Hosted cluster + `NodePool` workers | Target cluster with VM control-plane nodes; workers on separate infra |
| Primary APIs | `HostedCluster`, `NodePool` (`hypershift.openshift.io`) | Installer / ZTP workflows against Redfish-backed VM "BMCs" |
| Install familiarity | New form factor; not a classic `openshift-install` standalone cluster | Looks like a normal cluster install against virtual BMCs |
| Densification lever | Many control planes as workloads on fewer management nodes | Many control-plane VM sets consolidated on a shared virt hosting cluster |
| Typical management stack | Multicluster engine / HyperShift Operator | OpenShift Virtualization + KubeVirt Redfish on the hosting cluster |

## Day-2 differences that matter

Densification slides are easy. Operations is where the architectures diverge.

### Lifecycle and updates

In a standalone-style cluster—including a VCP target cluster that was installed
like one—the Cluster Version Operator and `ClusterVersion` resource remain the
familiar upgrade surface: control plane and compute tend to move together under
that model's rules.

Hosted clusters split the story. Updating the hosted control plane is a change
to the release image on the `HostedCluster` (and related control-plane
configuration). Worker updates are a separate `NodePool` concern. That split
is powerful for fleets that want to roll data planes independently; it is also
a training and tooling change for teams whose muscle memory is "upgrade the
cluster" as a single act. Machine Config Operator does not exist in hosted
control planes the way it does in standalone; node configuration is projected
through node-pool config maps and related hosted-cluster mechanisms.

### etcd and storage posture

Standalone and VCP-style control planes keep etcd with the control-plane nodes
(on those VMs for VCP). Hosted control planes place etcd in the hosted control
plane namespace on the management cluster, typically backed by persistent volume
claims and managed by the Control Plane Operator rather than a classic etcd
cluster Operator on dedicated control-plane machines. Capacity planning, backup,
and failure domains therefore shift from "three control-plane nodes" to "PVC
placement, storage class, and management-cluster resiliency."

### Networking

Standalone clusters usually keep the API server and nodes in a shared network
domain with direct communication patterns. Hosted control planes commonly
separate those domains: the kube-apiserver talks to workers through Konnectivity,
and nodes reach the API through an external load balancer or node-port style
path on the management side. That is not a footnote—it changes firewall
designs, private-network assumptions, and troubleshooting playbooks. If your
security team's mental model is "control plane VLAN equals worker VLAN," HCP
will force an update to that diagram.

### Operators and day-2 surface

A standalone OpenShift cluster exposes a familiar constellation of control-plane
Operators inside the cluster. A hosted cluster collapses much of that into the
Control Plane Operator running in the hosted control plane namespace on the
management cluster. Ingress-related, networking, and Operator Lifecycle Manager
pieces associated with the control plane also live on the management side.
Cluster-instance admins still get a working OpenShift API endpoint; they do not
get the same "SSH to a control-plane node and poke etcd" operational habits.

VCP keeps more of the standalone operational silhouette: the target cluster
*is* an OpenShift cluster whose control-plane nodes happen to be VMs. That is
often the point for teams that need densification without adopting the hosted
form factor.

### Install and provisioning familiarity

This is where virtualization and platform teams sometimes talk past each other.

VCP is designed so Agent-based Installer or GitOps Zero Touch Provisioning can
target Redfish URLs that front KubeVirt VMs—same shape as talking to a BMC on
bare metal. If your factory already speaks Redfish, image-based installs, and
ZTP policies, VCP extends that factory onto OpenShift Virtualization. That
fleet shape—hub, spokes, and GitOps ZTP—is the same conversation as
[OpenShift edge architectures](/posts/openshift-edge-architectures/), just aimed
at densifying control planes rather than plant cells.

HCP asks you to think in `HostedCluster` and `NodePool` objects. Provisioning
is fast because control planes are pods, but the API surface and personas
(cluster service provider on the management cluster versus cluster instance
administrator on the hosted cluster) are different from a classic install. For
fleet platforms and ROSA-like operating models, that is usually a feature. For
a team that just finished standardizing on Agent/ZTP for every site, it is a
conscious platform bet.

## OpenShift Virtualization is the substrate, not the rival

Both architectures can involve OpenShift Virtualization. Do not let the naming
collapse them into one idea.

- With **HCP on OpenShift Virtualization**, the management cluster can use CNV
  as a platform provider for hosted clusters. Control planes are still the
  hosted (pod-based) form factor. Isolation remains the hosted model unless you
  deliberately pursue stronger isolation patterns documented for hosted control
  planes (for example, dedicated-node / shared-nothing approaches when you need
  more than default container isolation).
- With **VCP**, OpenShift Virtualization *is* where the target cluster's
  control-plane VMs run. Hypervisor isolation is the product intent, and the
  install path deliberately resembles physical server provisioning.

If a stakeholder asks "should we use hosted control planes or OpenShift
Virtualization?" the precise answer is usually "hosted or virtualized control
planes—and OpenShift Virtualization may host either story." That clarification
alone prevents a surprising number of architecture-review loops. For broader
4.22 virtualization context, see
[What's New in OpenShift Virtualization 4.22](/posts/openshift-virtualization-4-22-features/).

## When to choose which

**Lean hosted control planes when:**

- You want maximum densification of control planes as Kubernetes workloads
- You are building a fleet or cluster-as-a-service operating model with
  multicluster engine / HyperShift
- You accept (or prefer) split control-plane and node-pool lifecycles
- Container-level isolation on the management cluster meets your tenancy and
  compliance story—or you will invest in the stronger HCP isolation patterns
  Red Hat documents for that form factor
- Fast control-plane bring-up matters more than preserving classic installer
  semantics

**Lean virtualized control planes when:**

- Hypervisor-level isolation for control-plane components is a hard requirement
- You need the target cluster to behave like a standalone OpenShift install for
  people, tooling, and mental models
- Your provisioning factory already centers on Agent, ZTP, and Redfish-shaped
  BMCs
- You are consolidating control-plane *nodes* onto a shared OpenShift
  Virtualization hosting cluster while keeping worker capacity elsewhere
- You can accept Technology Preview program risk for KubeVirt Redfish in 4.22,
  or you are evaluating the architecture ahead of broader support

**A practical sequencing note for many customers:** use hosted control planes
as the default densification architecture on OpenShift Virtualization when the
operating model fits, and treat virtualized control planes as the path when
isolation or installer-compatibility requirements outweigh the hosted form
factor—and when TP constraints are acceptable for the engagement.

## Closing

Hosted and virtualized control planes solve the same densification pressure with
different boundaries. HCP optimizes for control planes as managed workloads and
a modern multicluster API. VCP optimizes for VM-isolated control-plane nodes and
familiar install workflows on top of OpenShift Virtualization. Pick the
isolation and operations model you can run at 2 a.m.—not only the slide that
shows the highest cluster count per rack.

In bare-metal PoCs that reboot constantly while you prove either path, reclaiming
POST time is often worth a temporary BIOS tweak—see
[speeding up bare-metal boots by disabling memory checks](/posts/poc-faster-bare-metal-boot-disable-memory-check/)
(PoC only; restore before handback).

## Related posts

- [What's New in OpenShift Virtualization 4.22](/posts/openshift-virtualization-4-22-features/)
- [OpenShift Edge Architectures: Pick the Form Factor, Then the Fleet](/posts/openshift-edge-architectures/)
- [Speed Up Bare Metal Boots in OpenShift PoCs by Disabling Memory Checking](/posts/poc-faster-bare-metal-boot-disable-memory-check/)

Authoritative starting points:

- [Hosted control planes (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/hosted_control_planes/index)
- [Virtualized control planes overview (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualized_control_planes/vcp-overview)
- [OpenShift on OpenShift — Hosted Control Planes (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/installation/openshift-on-openshift/)
- [Architecture — hub and spoke (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/home/architecture/)
- [Fleet management (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/fleet-management/)
- [OpenShift Virtualization (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/post-installation/virtualization/)

If you are mapping either pattern into a broader platform or virtualization
architecture conversation, that is exactly the kind of design discussion Red Hat
solution architects exist for.
