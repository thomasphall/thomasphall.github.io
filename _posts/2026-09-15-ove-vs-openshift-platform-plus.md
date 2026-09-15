---
title: "OVE vs OpenShift Platform Plus: The SKU Choice"
description: >-
  When OpenShift Virtualization Engine is the right buy versus Platform
  Plus. GitOps, RHACS, or containers can imply Plus. Year-one free does
  not change topology.
date: 2026-09-15 07:30:00 -0500
categories: [OpenShift, Virtualization]
tags: [openshift, openshift-virtualization, gitops, acs, acm, migration]
permalink: /posts/ove-vs-openshift-platform-plus/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization. Subscription promotions
> change. Confirm current qualification with your Red Hat account team
> before you treat any year-one pricing as a design input.
{: .prompt-info }

A qualifying three-year agreement can make the first year of
[OpenShift Virtualization](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/index)
subscriptions free. That is a budget fact. It is not an architecture.
Simon Seagrave’s
[September note](https://www.redhat.com/en/blog/why-virtualization-decision-keeps-getting-deferred)
already said the quiet part: a free first year is not a reason to choose a
platform. It removes overlap cost so the decision can go back to the
technology. This post is that decision for two SKUs:
[Red Hat OpenShift Virtualization Engine (OVE)](https://www.redhat.com/en/technologies/cloud-computing/openshift/virtualization-engine)
versus
[Red Hat OpenShift Platform Plus](https://www.redhat.com/en/technologies/cloud-computing/openshift/platform-plus).

The hypervisor, the storage class, and the failure domain do not change
because year one is paid or unpaid. You still cannot mix those two product
types in one cluster. You still pick a form factor, a Container Storage
Interface (CSI) backend, and a fleet hub. Confirm the current
[self-managed OpenShift subscription guide](https://www.redhat.com/en/resources/self-managed-openshift-subscription-guide)
for the edition you will actually buy. This is a solutions-architect map,
not a quote.

## What each SKU is allowed to be

OVE is OpenShift for virtual machines (VMs). Unlimited VMs. No unlimited
guest application containers. Infrastructure containers—CSI drivers,
backup agents,
[Red Hat Advanced Cluster Management for Kubernetes (RHACM)](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/2.16/),
Ansible Automation Platform, software-defined storage that exists to serve
VM disks—are in the entitlement. Confirm borderline workloads with Red Hat.
Nodes are Red Hat Enterprise Linux CoreOS (RHCOS). Red Hat Enterprise Linux
(RHEL) guests need RHEL for Virtual Datacenters or per-VM subscriptions.
[OpenShift GitOps](https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.20/)
is included for VM use cases: `VirtualMachine` CRs, NMState, the platform
objects a virt cluster actually needs.
[Migration Toolkit for Virtualization (MTV)](https://docs.redhat.com/en/documentation/migration_toolkit_for_virtualization/)
is in the product. OpenShift Data Foundation (ODF),
[Red Hat Advanced Cluster Security for Kubernetes (RHACS)](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_security_for_kubernetes/),
and Quay as an estate registry are not. Fleet operations for VM-only
clusters are
[ACM for Virtualization](/posts/acm-openshift-virtualization/),
not the full RHACM SKU.

Platform Plus is OpenShift Container Platform plus the management layer:
RHACM, RHACS, ODF Essentials, and Quay. Unlimited containers. RHEL for
nodes and guests is in that bundle. GitOps is an application-platform
operator, not only a virt YAML pipe. Virtualization is still included. You
did not buy a different hypervisor. You bought the right to run containers
and VMs on the same control plane, with the security, registry, and storage
products that go with that story.

[OpenShift Container Platform (OCP)](https://www.redhat.com/en/technologies/cloud-computing/openshift/container-platform)
sits between them. Containers plus Virtualization, without the Plus
catalog. If the only “coming soon” item is a handful of application
namespaces, OCP can be the honest middle. Do not skip it because a slide
was titled OVE versus Plus.

You cannot mix editions in one cluster. An OVE node and a Platform Plus
node do not share an API server. If guest containers will land on the
*same* virt cluster, the SKU for that cluster has to move. A second cluster
is the other legal answer. Year-one pricing does not create a third.

## When OVE is the right buy

OVE is right when the program is a hypervisor replacement and the landing
zone will stay VM-only for a planning horizon you are willing to write
down.

- The workloads are VMs. Tenant applications are not becoming pods on
  this cluster in year one.
- Storage is already a SAN, or a certified partner SDS that runs as
  infrastructure. You are not buying Platform Plus to obtain ODF. See
  [vSAN-like storage for OpenShift Virtualization Engine](/posts/ove-vsan-storage-alternatives/).
- GitOps means the cluster repo: `VirtualMachine`, `NetworkAttachmentDefinition`,
  `StorageClass`. It does not mean Developer Hub, Pipelines, and tenant
  ApplicationSets as the operating model.
- The hub is ACM for Virtualization. Mixed ROSA and OCP spokes are not in
  scope for this fleet.
- RHACS is a later conversation, or it lives on a different cluster that
  already has it.

That pattern is common. Plenty of VMware exits look like this. MTV, live
migration, Node Health Check, and
[OADP](/posts/oadp-vms-backup-is-not-dr/)
do not require Platform Plus. The path off OVE later is an entitlement
change, not a reinstall. The subscription guide is explicit: change the
SKU, keep the cluster.

## When Platform Plus is already implied

Platform Plus is implied when the next slide after “migrate the VMs”
already names a product OVE does not include, or names a workload OVE
does not permit.

**Containers on the virt cluster.** Guest application containers need a
container SKU. On OVE you either entitle those VMs with core-pair
OpenShift subscriptions—an OpenShift-on-OVE sandwich—or you change the
bare-metal cluster to OCP or Platform Plus. “We will containerize later
on the same hosts” is a Platform Plus (or OCP) decision *now*, because
you cannot add Plus nodes to an OVE cluster later.

**RHACS as the cluster security plane.** Virt-launcher is still a pod.
If the security architecture is
[RHACS for OpenShift Virtualization workloads](/posts/acs-openshift-virtualization/),
you are buying the product. Platform Plus is how that product is bundled
with the cluster. A standalone RHACS add-on exists; treat “we need RHACS”
as a Plus-shaped requirement until procurement proves otherwise.

**GitOps as the application platform.** GitOps on OVE is allowed for VM
use cases. GitOps that implies Plus is the rest of the catalog: tenant
apps in ApplicationSets, Pipelines baking images, Quay as the source of
truth, RHACM policy across mixed clusters. That is
[GitOps should manage ACM, not the cluster](/posts/gitops-should-manage-acm/)
as an estate, not as a virt YAML habit. If the hub must manage non-Plus
clusters, the RHACM that ships with Plus does not automatically cover
them. Budget the add-on.

**ODF as first-party storage.** ODF Essentials is in Platform Plus. It is
not in OVE. Buying Plus only to get Ceph is a valid SKU move. It is not
the only storage move. An array you already own can keep you on OVE.

If two of those four are true in the same design review, stop pretending
the cluster is VM-only. Price Platform Plus (or OCP plus the add-ons) as
the landing zone. Migrating SKUs later is supported. Designing the first
cluster around a SKU you intend to abandon in nine months is still wasted
staff time.

## What year-one free does not change

Overlap cost is why migrations stall. Removing it is useful. It does not
rewrite the rest of the landing zone.

| Decision                         | Still yours after the promo                         |
| -------------------------------- | --------------------------------------------------- |
| Form factor                      | SNO, two-node + arbiter, compact, standard          |
| Storage                          | RWX Block CSI; ODF vs array vs partner SDS          |
| SKU mix in one cluster           | Not allowed; OVE or Plus, not both                  |
| Guest containers on this cluster | Not an OVE workload                                 |
| Fleet hub                        | ACM for Virtualization vs full RHACM                |
| Security plane                   | Guest hardening vs RHACS on virt-launcher           |
| Restore vs DR                    | OADP is still not Metro-DR                          |

Hardware, migration labor, training, and the platform you are leaving are
still on your books. The promo does not pick NMState, a `StorageClass`, or
a hub. Those are the same conversations as
[How to Get Started with an OpenShift PoC](/posts/getting-started-openshift-poc/).

## The solutions architect takeaway

1. **OVE is the VM-only OpenShift SKU** — unlimited VMs, infrastructure
   containers, GitOps for virt. Not guest application containers, not
   ODF, not RHACS, not Quay as an estate registry.
2. **Platform Plus is the application platform SKU** — containers and
   VMs, plus RHACM, RHACS, ODF, and Quay. Same hypervisor, different
   entitlement.
3. **GitOps on OVE is not GitOps as Plus** — VM YAML in git is in the
   OVE box. Tenant apps, Pipelines, and a mixed-fleet hub are not.
4. **You cannot mix editions in one cluster** — containers on these hosts
   means the whole cluster’s SKU moves, or you build a second cluster.
5. **Entitlement can change without a reinstall** — do not use that as
   permission to under-buy a cluster you already know will run pods.
6. **Year-one free is not topology** — it pays overlap. It does not pick
   SNO, CSI, or the hub.

If a non-prod cluster is already the proof, write the year-two workload
list on one slide before you pick the SKU. VMs only: OVE. Pods, RHACS, or
ODF on that same API server: Platform Plus, or OCP plus the named
add-ons. Then time an MTV wave. Pair that with
[OpenShift Virtualization (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/post-installation/virtualization/)
and
[OpenShift GitOps (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/post-installation/openshift-gitops/).

## Related posts

- [vSAN-like Storage for OpenShift Virtualization Engine](/posts/ove-vsan-storage-alternatives/)
- [ACM as the Fleet Control Plane for OpenShift VMs](/posts/acm-openshift-virtualization/)
- [GitOps Should Manage ACM, Not the Cluster](/posts/gitops-should-manage-acm/)
- [RHACS for OpenShift Virtualization Workloads](/posts/acs-openshift-virtualization/)

> Want help choosing OVE versus Platform Plus for a virt landing zone?
> Reach out to your Red Hat account team—or write the year-two workload
> list for one non-prod cluster before you freeze the SKU.
{: .prompt-tip }

## Further reading

- [Red Hat OpenShift Virtualization Engine](https://www.redhat.com/en/technologies/cloud-computing/openshift/virtualization-engine)
- [Red Hat OpenShift Platform Plus](https://www.redhat.com/en/technologies/cloud-computing/openshift/platform-plus)
- [Self-managed OpenShift subscription guide](https://www.redhat.com/en/resources/self-managed-openshift-subscription-guide)
- [Why the virtualization decision keeps getting deferred](https://www.redhat.com/en/blog/why-virtualization-decision-keeps-getting-deferred)
- [OpenShift Virtualization (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/post-installation/virtualization/)
- [OpenShift GitOps (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/post-installation/openshift-gitops/)
- [Advanced Cluster Management (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/fleet-management/acm-install/)
- [OpenShift Data Foundation (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/post-installation/storage/odf/)
