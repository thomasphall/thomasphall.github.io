---
title: "OpenShift Virtualization 5.0: The Updates That Matter"
description: >-
  OpenShift Virtualization 5.0 brings automatic balancing, RHCOS 10 support,
  storage improvements, and new dashboards. Learn what changes and what to validate.
date: 2026-11-07 00:00:00 -0700
categories: [OpenShift, Virtualization]
tags: [openshift, openshift-virtualization, gitops, storage, networking]
permalink: /posts/openshift-virtualization-5-0-features/
social_title: |-
  OpenShift Virtualization 5.0
  The updates that matter
social_label: OpenShift Virtualization
social_subtitle: Automation · Storage · Lifecycle
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization.
{: .prompt-info }

Getting a virtual machine onto a new platform is one milestone. Keeping
hundreds of guests balanced, observable, and maintainable is the work
that follows.

That is where the most important updates in Red Hat OpenShift
Virtualization 5.0 land. The platform takes on more configuration work,
supports live migration across the RHCOS 9 and 10 transition, and improves
the everyday handling of VM storage, networks, and monitoring.

**My priority for this release is understanding which operational
decisions the platform now makes automatically.** Those defaults can
reduce setup work, but they also change what belongs in an upgrade plan
and what a GitOps controller should own.

These are the changes I would put first in a platform review, based on
the [5.0 release notes](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/release-notes)
as of November 7, 2026. KubeVirt's CNCF graduation is a separate
question from this release. See
[KubeVirt Graduated. What Buyers Should Check](/posts/kubevirt-cncf-graduation/).

## 1. Autopilot makes configuration and balancing part of normal operations

The `virt-platform-autopilot` controller is now generally available.
It applies and maintains configuration for virtualization and installed
optional components, including the Kube Descheduler Operator and Cluster
Observability Operator. It also replaces the removed `wasp-agent`
component for higher VM workload density.

The balancing change deserves particular attention: **when the Kube
Descheduler Operator is installed, OpenShift Virtualization configures
load-aware balancing using both CPU and memory utilization.** The
descheduler is still optional. Autopilot does not install it, and a
cluster without it does not rebalance VMs. Installing it later allows
autopilot to detect and configure it. The
[postinstallation documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/postinstallation-configuration#virt-about-platform-autopilot_virt-platform-autopilot)
explains this dependency model.

For a team coming from VMware, this is worth testing with the actual
workload mix: a quiet cluster, a busy application period, and a maintenance
window. Watch which guests move and whether application response times
remain acceptable. The presence of a balancing controller does not tell
you how your applications will behave under load.

For GitOps teams, decide who owns each managed resource. Autopilot
continuously corrects drift and can pause reconciliation when it detects
repeated competing changes. Its documented customization and opt-out
controls are therefore part of the design. The ownership question in
[Virtualization Autopilot vs GitOps on OpenShift](/posts/virt-platform-autopilot-vs-gitops/)
still applies; that earlier post describes the 4.22 Developer Preview,
while 5.0 provides the GA controller.

Higher density still needs a storage decision. Enabling memory
overcommitment lets autopilot configure the relevant node settings;
administrators must provision swap storage. The
[density documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/postinstallation-configuration#virt-configuring-higher-vm-workload-density)
covers dedicated NVMe and file-based approaches, and notes the potential
performance cost on heavily utilized systems. I would validate density
against application latency and maintenance capacity before increasing
the number of guests per node.

## 2. The host transition and upgrade lifecycle need a fresh plan

OpenShift Virtualization 5.0 supports Red Hat Enterprise Linux CoreOS
(RHCOS) 9.8 and 10.2, with 10.2 as the default. Live migration between
RHCOS 9.x and 10.x worker nodes is supported. That is a meaningful change
from the Technology Preview status discussed in the earlier
[RHCOS 10 on OpenShift 4.22](/posts/rhcos-10-openshift/)
post. It gives teams a supported migration path between those host OS
streams, subject to their VMs meeting the other migration requirements.

There is also an API change for configuration repositories: the
`HyperConverged` resource defaults to `hco.kubevirt.io/v1`. The
`v1beta1` version is deprecated, and new fields are added only to `v1`.
Existing upgrades require no manual conversion action, according to the
[new-feature notes](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/release-notes#virt-5-0-new_virt-5-0-release-notes).
Use `v1` when maintaining manifests and automation for 5.0.

The longer-term planning change is Extended Life Cycle (ELC). OpenShift
5 replaces the EUS release model with ELC releases every third minor,
starting at 5.2. **OpenShift 5.0 is not an ELC release.**

For future ELC-to-ELC Control Plane Only updates, the documented sequence
passes through two intermediate minor versions. At each intermediate
version, update OpenShift Container Platform first and then OpenShift
Virtualization to that minor's latest patch release. The
[Control Plane Only update guide](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/updating#virt-about-control-plane-only-updates_upgrading-virt)
uses 5.2 through 5.3 and 5.4 to 5.5 as its example. Treat that as the
future lifecycle model, not a direct upgrade path available from 5.0.

## 3. Storage operations improve, with an important migration warning

Bulk storage-class migration now accommodates stopped VMs. A single
console migration plan can include both running and stopped guests,
which is useful when an estate contains active services, powered-off
utility machines, and seasonal workloads.

Declarative volume hot plug is also enabled by default. Operators can
insert and eject CD-ROM media on a running VM without first enabling
`DeclarativeHotplugVolumes`. This changes the default configuration for
a capability that previously required an explicit opt-in.

One less visible improvement affects image imports: Containerized Data
Importer (CDI) scratch space now inherits the target volume's storage
class unless explicitly overridden. Teams with several storage tiers
should review scratch-space capacity alongside destination capacity.
These changes are described in the
[storage-related release notes](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/release-notes#virt-5-0-new_virt-5-0-release-notes).

The November 11 product blog also describes QEMU Changed Block
Tracking for incremental backup. That feature is not in these release
notes. The two bitmaps and the support boundary are in
[Changed Block Tracking for OpenShift VMs](/posts/changed-block-tracking-openshift-vms/).

The known issues change how I would operate storage migration today:

> **Explicitly retain source volumes during storage migration.** The
> release notes document an issue where a
> `MultiNamespaceVirtualMachineStorageMigration` can report completion
> before copying data. If the plan decommissions its sources, that can
> cause data loss. Select **Keep original volumes at source after
> successful migration**, verify the destination data, and then remove
> the source volumes manually. See the
> [known issue CNV-98287](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/release-notes#virt-5-0-known-issues_virt-5-0-release-notes).
{: .prompt-warning }

The new-feature and known-issue sections describe different retention
defaults for storage migration. Set the retention choice explicitly in
each plan rather than relying on the default.

There is a valuable data-lifecycle fix too: detaching a disk now removes
the stale ownership relationship that could cause its DataVolume and PVC
to be deleted when the original VM was deleted. The
[fixed-issue notes](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/release-notes#virt-5-0-bug-fixes_virt-5-0-release-notes)
describe why that matters even when the disk has moved to another VM.

## 4. Network defaults reduce repetitive VM setup

Cluster administrators can set a project's default network for new VMs.
That can be the pod network or a Network Attachment Definition (NAD)
available in the project. Existing VMs are unaffected.

For a project dedicated to an application environment, this can remove
one repeated network-selection step from VM creation. It also makes the
project's intended attachment a configuration decision administrators
can review. It does not replace network policy or access controls.

The console also supports changing the network used by an existing
interface on a running VM through **Configuration > Network**. These
features improve the workflow around network selection; use the
[release notes](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/release-notes#virt-5-0-new_virt-5-0-release-notes)
and [project-default procedure](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/creating-virtual-machines#virt-vm-configuring-default-network-per-project_virt-creating-vms-web)
for the supported configuration.

I would test a network change with an application connection open.
Changing the attachment can change the guest's reachable networks and
addressing requirements. The network design still needs to account for
those consequences; the
[pod-to-localnet networking guide](/posts/openshift-virtualization-networking/)
provides that background.

## 5. Observability gets a stronger VM operations view

New Perses dashboards cover VM inventory, resource consumption, service
levels, time in status, top consumers, and node memory. OpenShift
Virtualization deploys them as `PersesDashboard` resources in
`openshift-cnv`. Viewing them requires Cluster Observability Operator
with its monitoring stack enabled.

GPU reporting also improves. Metrics identify the GPUs attached to a
virtual machine instance so operators can correlate allocation with
usage metrics from the NVIDIA Data Center GPU Manager exporter. The
release adds runbook coverage for `ClusterVMPanicDetected` and
`VMNonRecoverableOSPanic` alerts. These additions and prerequisites are
listed in the
[observability release notes](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/release-notes#virt-5-0-new_virt-5-0-release-notes).

For operations teams, the useful acceptance test is whether someone can
identify the busy guest, connect it to the affected node or accelerator,
and find the next troubleshooting action. Build that exercise into the
upgrade validation. A dashboard becomes operationally valuable when the
on-call team knows which decision it supports. How these views relate
to the metrics that replace vRealize Operations is covered in
[What Replaces vRealize Operations for VMs](/posts/what-replaces-vrealize-operations/).

## 6. VM templates and hardware support expand, with distinct support levels

The `VirtualMachineTemplate` and `VirtualMachineTemplateRequest` custom
resource definitions are generally available under
`template.kubevirt.io/v1beta1`. They provide native objects for VM
blueprints and for requesting a template from an existing VM. A VM must
have been started at least once before it can be used to create a
template.

Be precise about the surrounding workflows. The same release notes
still list converting an existing VM to a template in the UI and
creating VMs from in-cluster native templates under
[Technology Preview](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/release-notes#virt-5-0-technology-preview_virt-5-0-release-notes).
The GA status of the CRDs does not make every template workflow GA.
The virtualization MCP tools and manual role-aggregation option are
also Technology Preview.

For heterogeneous clusters, architecture-specific boot sources are now
GA after enabling `enableMultiArchBootImageImport`. IBM Z and LinuxONE
teams should also review the GA additions for Fusion Access for SAN
and RoCE/ISM PCI passthrough. KubeVirt Redfish reaches GA for VM power,
boot, and virtual-media management. These are targeted additions with
substantial value when they match the hardware and automation already
in use; the
[new-feature notes](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/release-notes#virt-5-0-new_virt-5-0-release-notes)
link to the individual configuration guides.

## The solutions architect takeaway

OpenShift Virtualization 5.0 gives the platform more responsibility for
maintaining its configuration and makes several routine VM operations
easier. I would evaluate it by exercising those responsibilities with a
representative set of guests.

Start with three questions: who owns the settings autopilot manages,
what happens to application performance when balancing moves guests,
and how will the team verify storage before deleting the source?
Those answers establish an operating model for the new capabilities.

Before an upgrade, also check the
[deprecations](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/release-notes#virt-5-0-deprecated_virt-5-0-release-notes):
legacy `pc-q35-rhel7.x.0` and `pc-q35-rhel8.x.0` machine types need a
planned move to `pc-q35-rhel9.8.0`, which requires a VM restart.
Ephemeral hot-plugged volumes are incompatible with declarative hot
plug and detach when switching to that feature gate. Include those
guests in the maintenance plan before relying on the new defaults.

> Want help planning an OpenShift Virtualization 5.0 evaluation? Work
> with your Red Hat account team to choose representative VMs and agree
> on balancing, migration, and recovery acceptance criteria before the
> production upgrade.
{: .prompt-tip }

## Related posts

- [Virtualization Autopilot vs GitOps on OpenShift](/posts/virt-platform-autopilot-vs-gitops/)
- [RHCOS 10 on OpenShift 4.22: What Changes](/posts/rhcos-10-openshift/)
- [KubeVirt Graduated. What Buyers Should Check](/posts/kubevirt-cncf-graduation/)
- [Changed Block Tracking for OpenShift VMs](/posts/changed-block-tracking-openshift-vms/)

## Further reading

- [OpenShift Virtualization 5.0 release notes](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/release-notes)
- [Automated postinstallation configuration](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/postinstallation-configuration#virt-platform-autopilot)
- [Configuring higher VM workload density](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/postinstallation-configuration#virt-configuring-higher-vm-workload-density)
- [Control Plane Only updates](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/updating#virt-about-control-plane-only-updates_upgrading-virt)
