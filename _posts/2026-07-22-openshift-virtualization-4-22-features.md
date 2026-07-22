---
title: "What's New in OpenShift Virtualization 4.22"
description: >-
  A themed digest of OpenShift Virtualization 4.22—management, infrastructure,
  networking, storage, lifecycle—plus Technology Preview and deprecation notes.
date: 2026-07-22 13:00:00 -0500
categories: [OpenShift, Virtualization]
tags: [openshift-virtualization, "4.22", release-notes, vms, hybrid-cloud]
permalink: /posts/openshift-virtualization-4-22-features/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization.
{: .prompt-info }

Virtual machines on [Red Hat OpenShift](https://www.redhat.com/en/technologies/cloud-computing/openshift)
are no longer a side quest for platform teams. They are a first-class workload
class sitting next to containers—and day-2 operations are where virtualization
projects succeed or stall. [OpenShift Virtualization](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/index)
4.22 is a release about that operational surface: clearer multi-cluster views,
safer storage and networking changes, accelerator support for AI-leaning
platforms, and a longer support runway for estates that cannot churn every few
months.

This post is a themed digest, not a complete changelog. For the authoritative
list—including fixed and known issues—start with the
[OpenShift Virtualization 4.22 release notes](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/release-notes).

## VM management and operations

Day-2 virtualization is mostly inventory, capacity, and control. 4.22 improves
all three in the OpenShift console experience.

The Overview experience now presents a dynamic, hierarchical view of VM data that
adapts to your tree selection at both cluster and multi-cluster levels. That
matters when you are talking to customers who run more than one OpenShift
cluster and still want a single operational mental model. Paired with CSV export
of VM inventory fields—hostname, IP address, node, namespace, memory, disk, OS
version, and more—you can feed CMDB or capacity reviews without hand-building
spreadsheets from `oc` output.

Capacity planning gets a dedicated signal: the VM memory overcommit and
utilization dashboard. Administrators can see whether a cluster is underutilized,
at risk from overcommit, or ready for expansion. For mixed estates, Application-Aware
Quota (AAQ) can track utilization for VMs only, for pods and VMs together, or
separately with dedicated quotas—useful when you need fair-share behavior without
pretending every workload is a Deployment.

Run strategy is now editable in the console Scheduling experience across creation
flows and the VM details view. Choosing among behaviors such as rerun-on-failure,
always, halted, and manual is a small UI change with a large operational impact:
it makes recovery policy visible instead of buried in YAML.

Two governance-oriented console controls round out the management theme.
Administrators can hide the YAML tab on VMs and other resources so changes go
through approved channels. Cluster admins can also add an internal certificate
authority or self-signed certificate for URL-based VM images in the Add Volume
dialog—closing a common “works on the CLI, fails in the UI” friction for private
HTTPS registries and image servers.

Finally, Windows guests fit better into Ansible-driven operations: you can
configure PSRP, WinRM, or SSH as the connection method between Windows-detected
hosts on OpenShift Virtualization and your Ansible environment, with the Ansible
inventory plugin using that protocol.

## Infrastructure and accelerators

Not every Virtualization estate is x86 cloud. 4.22 continues to widen the
hardware and guest-media management story for platforms where the VM *is* the
application boundary.

PCI passthrough for the IBM Spyre Accelerator is generally available for VMs on
IBM z17 and IBM LinuxONE Emperor 5 or later. For customers building AI
inferencing next to existing mainframe and LinuxONE estates, that is a concrete
platform conversation—not a slide about “accelerators someday.” Pair it with the
broader OpenShift story on IBM Z and LinuxONE (including hosted control planes
where relevant) so virtualization does not feel bolted onto an otherwise
container-only roadmap.

Live CD-ROM management is also GA via declarative hot-plug: with the
`DeclarativeHotplugVolumes` feature gate enabled on the `HyperConverged` custom
resource, you can insert and eject CD-ROM storage on a running VM without a
reboot. That is the difference between a maintenance window and a routine media
change for installers, tools, or recovery images. If you still rely on the older
`HotplugVolume` feature gate, treat the move to declarative hot-plug as an
explicit upgrade decision—especially if you use ephemeral volumes today (see
Deprecated and removed below).

## Networking

Networking changes in 4.22 are practical for teams that already live in
secondary networks and VLAN segmentation—the common pattern when VMs must speak
to existing data-center fabrics rather than only the cluster’s default pod
network.

IPv6 single-stack support for OpenShift Virtualization is generally available for
VMs connected through OVN-Kubernetes localnet, Linux bridge CNI, or SR-IOV.
If your data center or regulatory environment is pushing IPv6-first designs, you
can now talk about Virtualization workloads on that footing without a Technology
Preview caveat. Be explicit in designs about *which* attachment types you are
using; the GA statement is tied to those connectivity paths.

Secondary-network day-2 work gets a live path: administrators and VM owners can
update the Network Attachment Definition (NAD) reference on a running VM’s
secondary interface—for example to move to a different VLAN—triggering live
migration while preserving the guest interface name and MAC address. That is a
stronger story than “edit the CR and schedule a reboot,” and it keeps guest
network identity stable when the underlay segment changes.

Physical networks can also be defined from existing Node Network Configuration
Policies (NNCPs) in the UI. A physical network becomes a logical grouping you can
extend to new nodes, attach to OVN-Kubernetes localnet-backed VMs, and reuse when
creating new node network configurations. For GitOps-led clusters, NNCP remains
the declarative source of truth; the console path is the on-ramp for operators
who start visually and then promote the resulting intent into git.

## Storage and data lifecycle

Storage migrations and clones are where virtualization estates accumulate
operator toil. 4.22 chips away at that toil with naming and cleanup defaults that
match how automation actually works.

After a storage migration, you can optionally clean up source persistent volume
claims automatically instead of leaving orphans for a later cleanup ticket.
Default behavior still retains source PVCs until you opt into cleanup—so
conservative estates are not surprised, while automation-friendly teams can stop
accumulating unused volumes. When cloning, `volumeNamePolicy` lets you produce
predictable PVC and data volume names that include the target VM name—important
for orchestrators and Ansible jobs that expect stable names after restore.

Snapshot restore can keep original PVC names through the in-place volume restore
policy in the Restore Snapshot dialog (setting `spec.volumeRestorePolicy` on the
`VirtualMachineRestore` resource), or accept randomized names when that is
preferred. The default `volumeRestorePolicy` is now `PrefixTargetName`, so
restore and clone flows prefix new PVC names with the target VM name unless you
choose otherwise. Small default changes like this prevent a surprising amount of
“why doesn’t my automation find the disk?” support work after an upgrade—worth
calling out in any 4.22 readiness checklist.

## Lifecycle and observability

Extended Upgrade Support (EUS) add-ons enable a 36-month cluster lifecycle policy
for OpenShift Virtualization. For mission-critical VM platforms, that is often
the first question after “does it run my OS?”—how long can we stay stable without
losing support. Point customers at the OpenShift Container Platform life cycle
policy when you discuss EUS subscription options.

On the observability side, recording rule names were updated to the Prometheus
convention `<level>:<metric>:<operations>`. If you maintain custom alerts or
dashboards, review the Knowledgebase article on OpenShift Virtualization 4.22
recording rule naming before you upgrade—not after the graph goes blank.

## Technology Preview

These capabilities are experimental and not intended for production. Confirm
support scope on the Red Hat Customer Portal before you design around them.

- **KubeVirt Redfish** — Expose OpenShift Virtualization VMs through the standard
  Redfish API for power state, boot configuration, and virtual media workflows.
- **Golden images on heterogeneous clusters** — Create and use golden images when
  node configurations differ across the cluster.
- **Custom video devices** — Override default video configuration for guest OS or
  performance needs.
- **VM-to-template in the UI** — Create a user-generated template from an existing
  VM (stop the VM first for consistency); filter and delete those templates.
- **In-cluster native templates** — Create VMs from cluster-native template custom
  resources that track periodically updated golden images.
- **Dual stream RHCOS** — Provision clusters with RHCOS 9.8 (default) and RHCOS
  10.2 on OpenShift 4.22, including live migration between 9.x and 10.x worker
  nodes.

## Deprecated and removed

Upgrade planners should not skip this section.

**Deprecated**
- Recording rules `kubevirt_vm_created_total` and
  `kubevirt_cnao_kubemacpool_duplicate_macs` — remove references from custom
  alerts or dashboards before a future removal.
- The `HotplugVolume` feature gate — deprecated in favor of
  `DeclarativeHotplugVolumes`. Ephemeral volumes are not supported with the
  declarative gate; existing ephemeral hot-plugged volumes are detached when you
  switch.

**Removed**
- The predefined latency checkup between two VMs on a secondary network is gone.
  If your runbooks depended on it, replace that validation path before upgrade.
- The console no longer labels localnet NAD types as deprecated—an important UI
  clarification that localnet remains fully supported.

## The SA takeaway

When you frame OpenShift Virtualization 4.22 for a customer or internal platform
review, lead with outcomes rather than a feature laundry list:

1. **Operate** — Multi-cluster Overview, CSV inventory, AAQ, run strategy, and
   Windows/Ansible connection options reduce day-2 friction.
2. **Connect** — IPv6 single-stack GA, live NAD updates, and NNCP-based physical
   networks make secondary networking a managed capability.
3. **Store cleanly** — Predictable PVC naming, optional source cleanup, and
   clearer restore defaults keep automation honest after migrations and clones.
4. **Stay longer** — EUS for a 36-month Virtualization lifecycle is the stability
   conversation many regulated and mainframe-adjacent estates need.
5. **Plan the edges** — Treat Technology Preview as evaluation fodder; treat
   deprecated recording rules and `HotplugVolume` as upgrade homework.

Validate in non-production first: exercise storage migration cleanup, confirm
custom Prometheus rules still resolve after the recording-rule rename, and decide
whether `DeclarativeHotplugVolumes` belongs in your `HyperConverged` baseline.
If you run IBM Z or LinuxONE AI paths, put Spyre passthrough on the same lab
agenda rather than discovering hardware prerequisites in production.

Hybrid should mean *where* the cluster runs—not a different quality bar for VM
operations. Use 4.22 to make the VM control plane look as intentional as the
container one.

> Dig into the
> [OpenShift Virtualization 4.22 release notes](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/release-notes)
> for fixed and known issues, then try the patterns that matter on a non-prod
> cluster—or talk with your Red Hat account team about upgrade planning.
{: .prompt-tip }
