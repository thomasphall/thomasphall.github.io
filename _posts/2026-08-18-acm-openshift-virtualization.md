---
title: "ACM as the Fleet Control Plane for OpenShift VMs"
description: >-
  Why RHACM 2.16 is the fleet hub for OpenShift Virtualization across
  clusters: inventory, Observability, policy-driven backup, live
  migration, and VM RBAC.
date: 2026-08-18 06:00:00 -0500
categories: [OpenShift, Virtualization]
tags: [acm, openshift, openshift-virtualization]
permalink: /posts/acm-openshift-virtualization/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization.
{: .prompt-info }

Give a platform team a second
[OpenShift Virtualization](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/index)
cluster and the OpenShift console stops being a control plane. It is still the
right place to build a VM, attach a localnet NIC, or debug a single
virt-launcher pod. It is the wrong place to answer *what is running across
the estate, who can stop it, and how we move it for maintenance.* Cluster-local
UI does not scale. The objects do.

Each VM is still a Kubernetes `VirtualMachine`. That is why
[Red Hat Advanced Cluster Management for Kubernetes (RHACM) 2.16](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/2.16/)
has a job here. The hub already inventories and governs managed clusters. ACM
Virtualization extends that same hub to the VM workload class: search and
actions, Observability, policy-driven backup, cross-cluster live migration, and
fine-grained RBAC so those actions are not cluster-admin for everyone.

This post is a solution-architect field guide for that conversation. It is not
an install lab. For product procedure, start with
[ACM 2.16 Virtualization](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/2.16/html/virtualization/acm-virt).
Cluster-local day-2 improvements in
[OpenShift Virtualization 4.22](/posts/openshift-virtualization-4-22-features/)
still matter; they do not replace a fleet hub.

## Inventory and actions from the hub

Day-2 virtualization is mostly inventory plus control. ACM Search can list and
filter `VirtualMachine` resources across every managed cluster that runs
OpenShift Virtualization. The Fleet Virtualization console is the operational
view of that inventory: one place to see what is running instead of a bookmark
folder of cluster consoles.

From that console you can start, stop, restart, pause, unpause, and snapshot
VMs. Those are the documented hub actions. They are enough to change the
conversation from “SSH to the right cluster and find the YAML” to “the hub
operates the VM fleet.” Live migration between clusters is a separate, GA
capability—not another Search button to invent in a pitch.

That split matches how customers already think about containers. Nobody wants
a unique operational model for “the VM clusters.” If the platform is OpenShift,
the VM is a Kubernetes workload, and the hub that already knows the clusters
should know the VMs.

OpenShift Virtualization 4.20.1 or later is the floor for ACM Virtualization
features. This site’s latest stable OpenShift line is 4.22, which satisfies
that requirement. Confirm pairing against the
[ACM 2.16 support matrix](https://access.redhat.com/articles/7136928)
for the hub and managed clusters you actually run.

## Observability and right-sizing

Inventory without signals is a CMDB with a nicer theme. If the Observability
service is installed on the hub, the Virtual Machine page can launch Grafana
dashboards for VM metrics. That is the fleet capacity conversation: utilization,
pressure, and whether a cluster is the right place to land the next workload.

[RHACM 2.16](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/2.16/html/release_notes/acm-release-notes)
makes `RightSizingRecommendation` generally available. After Observability is
enabled, namespace right-sizing and virtualization right-sizing are on by
default. Use that as a talking point, not a Grafana workshop: the hub can
recommend whether VMs are over- or under-provisioned instead of leaving every
site to build its own spreadsheet.

Keep the boundary honest. Right-sizing is an Observability feature, not a
substitute for storage performance testing or for the
[hardening](/posts/openshift-virtualization-hardening-priorities/)
work that decides who may attach devices and which networks a VM may join.

## Policy-driven backup is not DR

Backup for OpenShift Virtualization VMs in ACM is policy plus
[OpenShift APIs for Data Protection (OADP)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/backup_and_restore/oadp-application-backup-and-restore).
Enable the backup component, place the virtualization policies, and ACM will
install and configure OADP on managed clusters according to a hub ConfigMap.
The operator model is GitOps-shaped even when you never open OpenShift
GitOps: labels select clusters and VMs; policies create Velero schedules;
compliance tells you whether the last backup completed.

Supported storage for those VM backups is CSI or CSI with DataMover. File
system backup and volume-snapshot backup are not supported for this path. Say
that in the design review before someone assumes “we have OADP, so every
Velero feature applies to VMs.”

Selection is a label on the VM, not a hidden controller default:

```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: vm-name
  labels:
    cluster.open-cluster-management.io/backup-vm: daily_8am
```

The schedule name must exist in the hub cron ConfigMap. The managed cluster
gets the policies when you set `acm-virt-config` on the `ManagedCluster`
resource. Restore is a separate policy driven by a restore ConfigMap, including
optional namespace mapping. That is backup and restore. It is not Metro or
Regional DR, and it is not a replacement for application-level recovery
objectives you already negotiated.

## Cross-cluster live migration

[Cross-cluster live migration is generally available in ACM 2.16](https://www.redhat.com/en/blog/stop-searching-start-operating-scale-hybrid-clusters-red-hat-advanced-cluster-management-kubernetes-216).
The point is operational: drain a cluster for upgrade, rebalance load, or move
a VM to a namespace that matches a new tenancy boundary—without treating the
VM as glued to the cluster where it was born.

The enablement model is hub-centric. Turn on the `cnv-mtv-integrations`
component on `MultiClusterHub`. Label source and target clusters with
`acm/cnv-operator-install: "true"`. Migration Toolkit for Virtualization lands
on the hub; OpenShift Virtualization is installed on those labeled managed
clusters. That last sentence is an operational implication, not a footnote:
do not apply the label to a cluster you did not intend to turn into a
virtualization target.

Live migration is not backup. Backup is a point-in-time copy you can restore
later, including onto another cluster. Live migration is a move with the VM
still running. Mixing those words in a customer slide is how DR requirements
get “satisfied” by a feature that does not survive a storage-domain loss.

Hosted control planes change where the API server runs; they do not remove the
need for a fleet hub. See
[hosted vs virtualized control planes](/posts/hosted-vs-virtualized-control-planes/).
ACM still manages the hosted clusters and the VMs on the compute clusters
underneath them.

## Fine-grained RBAC for VM admins

A hub that can stop or migrate every VM in the estate is a privilege
concentrator. ACM 2.16 makes fine-grained RBAC for virtualization generally
available so VM operators are not cluster-admins.

Permissions are declared on the hub with `MulticlusterRoleAssignment` and
propagated to managed clusters. The Fleet Virtualization roles to name in the
room:

| Role | What it is for |
| ---- | -------------- |
| `acm-vm-fleet:view` | Minimum access to the Fleet Virtualization console |
| `acm-vm-fleet:admin` | Fleet console plus cluster-to-cluster live migration |
| `acm-vm-extended:view` / `acm-vm-extended:admin` | Read or administer extended Kubernetes resources on source and target clusters |
| `acm-vm-cluster-migration:view` | Migration readiness checks on the target cluster |

Details and assignment flows live in
[ACM secure clusters](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/2.16/html-single/secure_clusters/index)
documentation. The SA point is simpler than the CRD: write VM administration as
a fleet role, not as `cluster-admin` copied to every virt namespace. That is the
same least-privilege instinct as
[RHACS for virt-launcher workloads](/posts/acs-openshift-virtualization/)—
a complementary control plane, not a substitute.

## ACM for Virtualization

[ACM for Virtualization](https://www.redhat.com/en/resources/advanced-cluster-management-for-virtualization-datasheet)
is the same ACM operational surface, entitled only for
OpenShift Virtualization Engine clusters and the VMs on them. If the estate is
VMs on OVE and nothing else, that SKU matches the buy. Mixed container and VM
fleets stay on ACM for Kubernetes. Do not let the SKU conversation replace the
architecture conversation: either way, the hub is how you stop managing each
virt cluster as a pet.

## The SA takeaway

Lead with outcomes:

1. **The OpenShift console does not scale to a VM fleet** — ACM 2.16 is the
   hub for inventory, actions, Observability, backup policy, and live
   migration.
2. **Right-sizing is GA with Observability** — use it for capacity talk; do
   not treat it as a storage or hardening substitute.
3. **Backup is CSI/OADP policy, not DR** — label clusters and VMs; do not
   claim filesystem or volume-snapshot backup on this path.
4. **Live migration is GA and is a move** — maintenance and load, not a
   recovery objective; the install label has blast radius.
5. **RBAC is part of the feature** — `acm-vm-fleet:admin` is not
   `cluster-admin`.

If you already run RHACM for cluster lifecycle or GitOps ZTP, the next proof
point is small: show one `VirtualMachine` from a spoke in Search, agree who
may stop and migrate it, and decide whether Observability and the backup
policies belong on the same hub. Edge form factor still comes first—see
[OpenShift edge architectures](/posts/openshift-edge-architectures/)—
then make the fleet boring on purpose, including the VMs.

For a PoC hub, start with
[Advanced Cluster Management (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/fleet-management/acm-install/)
and
[OpenShift Virtualization (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/post-installation/virtualization/).

## Related posts

- [AI Agents for MTV: vSphere to OpenShift Virtualization](/posts/ai-agents-mtv-vsphere/)
- [What's New in OpenShift Virtualization 4.22](/posts/openshift-virtualization-4-22-features/)
- [Hosted vs Virtualized Control Planes on OpenShift 4.22](/posts/hosted-vs-virtualized-control-planes/)
- [RHACS for OpenShift Virtualization Workloads](/posts/acs-openshift-virtualization/)

> Want a deeper walkthrough for your environment? Reach out to your Red Hat
> account team—or evaluate the pattern on a non-prod hub and two spoke
> clusters first.
{: .prompt-tip }

## Further reading

- [ACM 2.16 Virtualization](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/2.16/html/virtualization/acm-virt)
- [ACM 2.16 release notes](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/2.16/html/release_notes/acm-release-notes)
- [ACM 2.16 Observability](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/2.16/html/observability/index)
- [ACM 2.16 secure clusters](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/2.16/html-single/secure_clusters/index)
- [Stop searching, start operating: ACM 2.16](https://www.redhat.com/en/blog/stop-searching-start-operating-scale-hybrid-clusters-red-hat-advanced-cluster-management-kubernetes-216)
