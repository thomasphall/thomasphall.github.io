---
title: "vSphere to OpenShift Virtualization: Translation Guide"
description: >-
  How vSphere folders, resource pools, tags, DRS rules, roles, and snapshots
  map to OpenShift Virtualization namespaces, quotas, labels, affinity, and
  RBAC.
date: 2026-10-27 07:00:00 -0500
categories: [OpenShift, Virtualization]
tags: [openshift, openshift-virtualization, vmware, migration, gitops]
permalink: /posts/vsphere-to-openshift-translation-guide/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization.
{: .prompt-info }

A VMware exit stalls in the first design review when someone asks where the
resource pools went. vCenter inventory is a tree: datacenters, clusters,
hosts, folders, pools, tags, and roles that inherit down that tree.
[Red Hat OpenShift](https://www.redhat.com/en/technologies/cloud-computing/openshift)
inventory is flat: a cluster, nodes, namespaces, labels, and role bindings.
The virtual machine (VM) still runs. The objects around it do not survive a
rename.

This is the translation guide for that review on OpenShift Container
Platform 4.22 and
[OpenShift Virtualization](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/index).
It is a solutions-architect map, not a manifest catalog. The
[Migration Toolkit for Virtualization](https://docs.redhat.com/en/documentation/migration_toolkit_for_virtualization/2.12)
(MTV) copies disks. It does not rebuild a folder tree. Design the landing
zone before wave 1. If the cluster is still a diagram, start with
[How to Get Started with an OpenShift PoC](/posts/getting-started-openshift-poc/)
and the
[OpenShift Virtualization (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/configure-the-cluster/virtualization/)
install. Put namespaces, quotas, bindings, and affinity in git on the same
split as
[GitOps should manage ACM, not the cluster](/posts/gitops-should-manage-acm/).

## The inventory map

Create the object in the OpenShift column. The vSphere name is the question
people still ask.

| vSphere object              | OpenShift object                                      | What changes in the room                                      |
| --------------------------- | ----------------------------------------------------- | ------------------------------------------------------------- |
| vCenter                     | OpenShift API and console                             | A fleet of vCenters is the hub                                |
| Datacenter                  | OpenShift cluster                                     | Blast radius, shared storage, and the networks you can attach |
| Cluster (HA and DRS)        | Workers that can live-migrate among themselves        | Often the whole cluster. A hardware tier is a labeled pool   |
| ESXi host                   | Worker node running virt-handler                      | VM configuration lives in the API                             |
| Resource pool               | Namespace plus Application-Aware Quota                | A cap. Shares and borrowing stay behind                       |
| VM and template folder      | A label, or a namespace if it held a permission       | Namespaces are flat. The console calls one a project         |
| Tag and category            | Label key and value                                   | Selectors. A label is not a permission                       |
| Custom attribute, note      | Annotation                                            | Display it. Do not select on it                              |
| Template                    | `VirtualMachine` manifest in git, plus a `DataSource` | Size differences belong in an instance type                  |
| Customization spec          | cloud-init or sysprep                                 | First boot, from the VM spec                                  |
| Content library             | `DataSource` and `DataImportCron`, or a boot source   | The golden disk has a namespace and an owner                 |
| Port group                  | Pod network, or a `NetworkAttachmentDefinition`       | The networking post is that map                               |
| Datastore                   | `StorageClass` and a PVC                              | The VM consumes a claim                                       |
| Storage policy              | `StorageClass`                                        | Platform admins publish a short menu                          |
| vMotion                     | Live migration                                        | Its own role, `kubevirt.io:migrate`                           |
| Storage vMotion             | Storage migration across storage classes              | 4.22 keeps the source PVC unless you opt into cleanup        |
| Snapshot                    | `VirtualMachineSnapshot`                              | Disks and the VM spec                                         |
| Alarm                       | Prometheus alerts                                     | Five signals, in the vROps post                               |
| HA restart                  | `spec.runStrategy`                                    | `Always`, `RerunOnFailure`, `Halted`, or `Manual`             |

A fleet of vCenters is a
[Red Hat Advanced Cluster Management for Kubernetes (RHACM)](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/2.16/html/virtualization/acm-virt)
hub.
[ACM as the Fleet Control Plane for OpenShift VMs](/posts/acm-openshift-virtualization/)
is that seat. Port groups are
[OpenShift Virtualization Networking: Pod to Localnet](/posts/openshift-virtualization-networking/).
Alarms are
[What Replaces vRealize Operations for VMs](/posts/what-replaces-vrealize-operations/).
The rows that cause bad designs get the rest of this post.

## Folders, tags, and the org chart

Three vSphere habits show up as one argument: folders as departments, tags
as departments, and folders as the permission tree.

A folder that only grouped VMs for a person becomes a label, such as
`owner=payments` or `env=prod`. A folder that held a permission becomes a
namespace. Nested folders do not become nested namespaces. The hierarchy
that remains is RHACM at the cluster boundary and a namespace inside the
cluster.

Permission inheritance stops at the namespace. A `RoleBinding` in
`payments` does not apply to `payments-dev`. Stamp the same binding from
git, or from an RHACM policy, on purpose.

Tags become labels because something selects them: anti-affinity, a backup
policy, an RHACM policy. A label is not an authorization boundary.
When the tag was standing in for "who may power this VM off," make a
namespace and a binding.

Annotations hold the rest: a ticket number, the CMDB id, the old folder
path during the exit so inventory still reconciles. Leave automation off
that annotation. Selectors belong on labels.

## Resource pools become quotas

A vSphere resource pool is a share of CPU and memory, often nested, often
allowed to borrow from its parent when the siblings are idle. OpenShift
has no such tree. Split the pool into the job it was actually doing.

| What the pool was doing              | OpenShift object                         |
| ------------------------------------ | ---------------------------------------- |
| Cap a team or an app                 | Namespace and Application-Aware Quota    |
| Cap several namespaces together      | `ApplicationAwareClusterResourceQuota`   |
| Pin a workload to a hardware tier    | Node labels and node affinity            |
| Guarantee CPU and memory for one VM  | `requests` on the `VirtualMachine`       |
| Hard ceiling for one VM              | `limits` on the `VirtualMachine`         |

Use Application-Aware Quota (AAQ) for the cap. A native `ResourceQuota`
measures the virt-launcher pod, including hypervisor overhead. That number
is the wrong answer to "how much guest did we sell." Live migration also
starts a second virt-launcher for the move, so a quota sized to the running
guests rejects the target pod, and the upgrade that needed the move fails
with it. AAQ measures virtual CPU and memory, so the move is not charged
as a second guest. In 4.22, enable it under
**Virtualization → Settings** and create the quota under
**Virtualization → Quotas**. The object is `ApplicationAwareResourceQuota`.

Three calculation methods exist. Virtual resources, the default, count
guest CPU and memory and leave pod overhead out. Virtual machine instance
pod usage counts the whole virt-launcher. Dedicated virtual resources track
VMs and pods on separate lines. A mixed cluster wants the dedicated method
so a `Deployment` and a VM do not spend the same quota. A cluster-scoped
AAQ quota, `ApplicationAwareClusterResourceQuota`, can cap several
namespaces once the operator is configured to allow it. Unused quota still
does not move from one namespace to another. Confirm the method in the
[4.22 managing VMs chapter](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/managing-vms)
before you standardize it.

CPU `requests` participate in scheduling. Under CPU contention they also
influence relative weight on that node. They still do not recreate a
parent pool. If the business rule is "payments may use what retail leaves
idle," put them in one namespace with one quota and separate them with
labels. If the rule is "payments must not starve retail," give them two
quotas and accept idle capacity.

Cluster overcommit is a platform policy. Read the Node Memory Overcommit
dashboard in the vROps post before you copy vSphere reservations
one-for-one into `requests`.

## DRS rules become affinity

The scheduler places a VM when it starts. There is no manual DRS mode, and
nothing rebalances a running VM until you add a descheduler.

| DRS rule                    | Field                                                         | Behavior                                      |
| --------------------------- | ------------------------------------------------------------- | --------------------------------------------- |
| Must run on a host group    | `nodeSelector`, or required node affinity                     | Stays pending if no node matches              |
| Should run on a host group  | Preferred node affinity                                       | Still starts                                  |
| Must keep VMs apart         | Required `podAntiAffinity`, `topologyKey: kubernetes.io/hostname` | Pending beats stacking                    |
| Should keep VMs apart       | Preferred `podAntiAffinity`                                   | Stacks if the cluster is tight                |
| Must keep VMs together      | Required `podAffinity`                                        | Licensing and chatty pairs. Use it rarely     |
| May run on a tainted node   | `tolerations`                                                 | A taint with no toleration excludes the VM    |

Those fields sit on `spec.template.spec`. Required rules use
`requiredDuringSchedulingIgnoredDuringExecution`. Preferred rules use
`preferredDuringSchedulingIgnoredDuringExecution`. The `Ignored` half is
the contract: OpenShift does not move a running VM when a later arrival
makes the rule false. A should-rule that was true on Monday can be false
on Thursday, and the VM stays where it is.

The Descheduler Operator, with the `KubeVirtRelieveAndMigrate` profile,
evicts and live-migrates so a rule gets another chance. Enable it for the
rules you are willing to enforce after boot. Leave it off for VMs that
must stay put. That set is smaller than a vSphere "should" rule, and the
profile belongs in git next to the affinity.

Live migration is the vMotion path, including the moves an upgrade
performs.
[Upgrading OpenShift While VMs Stay Running](/posts/upgrading-openshift-while-vms-stay-running/)
is that procedure. Since OpenShift Virtualization 4.19, live migration is
a separate role: `kubevirt.io:migrate`, bound on the namespace or the
cluster. Namespace `admin` does not include it. Cluster admins can
aggregate that role back into `admin`. Do that in git only when the VM
team should move running guests. The requests themselves are
`VirtualMachineInstanceMigration` objects.

`spec.runStrategy` sits beside `spec.template`, not inside it.

| `runStrategy`     | Guest outcome                                              |
| ----------------- | ---------------------------------------------------------- |
| `Always`          | Comes back, including after a clean guest shutdown         |
| `RerunOnFailure`  | Comes back after a failure, and stays down after a clean shutdown |
| `Manual`          | Starts and stops only when a person asks                   |
| `Halted`          | Stays down                                                 |

`Always` does not fence a dead node by itself. Without node remediation,
that VM waits until someone deletes the `Node`. Isolation response is
[Fence Gray Host Failures on OpenShift Virtualization](/posts/openshift-virt-gray-failure-ha/).

Enhanced vMotion Compatibility is a CPU model decision you make before
wave 1. `host-model` keeps the guest compatible only with nodes that
support that host CPU. A named model on
`spec.template.spec.domain.cpu.model` is the explicit baseline for every
node that must be able to receive the VM. Mixed CPU generations will
schedule a guest that can never leave its node.

## Roles become bindings

vSphere roles inherit down the inventory tree. OpenShift bindings do not.
Pick the namespace, then bind a role into it.

OpenShift Virtualization extends the default `view`, `edit`, and `admin`
roles with virt permissions. Binding those on a namespace is the usual
path. `kubevirt.io:migrate` is the exception above.

| vSphere habit                    | Bind this                                      | What they can do                         | What stays out                                      |
| -------------------------------- | ---------------------------------------------- | ---------------------------------------- | --------------------------------------------------- |
| Read-only operator               | `view`                                         | See the VM                               | Console, power, delete                              |
| Console and power, no redesign   | Custom `Role` on the subresources below        | Power and console                        | Delete, disk changes, live migration                |
| Team VM admin                    | `admin` on that namespace                      | Create, change, delete, console          | `HyperConverged`, storage classes, migrate          |
| Someone who may vMotion          | `kubevirt.io:migrate`                          | `VirtualMachineInstanceMigration`        | The rest of `cluster-admin`                         |
| Platform owner                   | `cluster-admin`                                | Operators, storage classes, `HyperConverged` | The VM team should not hold this                |
| Fleet operator                   | `acm-vm-fleet:admin` on the hub                | RHACM VM actions across spokes           | Spoke `cluster-admin`                               |

The custom role is the row design reviews skip. `edit` can delete the VM
and open the console. A vSphere virtual machine user who could power-cycle
and open a console could not delete the guest from disk. Give that person
the subresources, not `edit`: `virtualmachines/start`,
`virtualmachines/stop`, and `virtualmachines/restart`, plus the console
and VNC subresources. They live in `subresources.kubevirt.io`. Confirm the
verbs in the
[4.22 authentication and authorization](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/authentication_and_authorization/using-rbac)
chapter before you bind a role you intend to keep.
[About OpenShift Virtualization](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/about)
lists `kubevirt.io:view`, `kubevirt.io:edit`, `kubevirt.io:admin`, and
`kubevirt.io:migrate`.

`admin` on a namespace does not own the `HyperConverged` object in
`openshift-cnv`. Storage classes and node network configuration are
cluster-scoped the same way. The VM owner consumes a `StorageClass`, or
attaches a `NetworkAttachmentDefinition` the platform team published into
the namespace. Publish a short menu.

`acm-vm-fleet:admin` is the fleet action role.
[ACM as the Fleet Control Plane for OpenShift VMs](/posts/acm-openshift-virtualization/)
draws that boundary. It is not spoke `cluster-admin`.

## Templates, clones, and snapshots

A vSphere template plus a customization spec becomes three objects. A
`VirtualMachine` manifest in git. An instance type when the only
difference is CPU and memory, so you stop cloning templates to change RAM.
cloud-init or sysprep on the VM for guest identity. The disk comes from a
`DataSource`. The Containerized Data Importer (CDI) clones or imports that
disk into the VM's namespace. A `DataImportCron` is how the golden image
stays current.

Converting a VM into a template from the console is Technology Preview in
4.22. The template you will still have next year is the manifest in git.

A linked clone, and the delta disk it implies, becomes a CDI clone: a new
PVC, not a chain you consolidate later. An instant clone of a running
memory image has no equivalent. Build the next guest from the golden
image.

A vSphere snapshot, especially one that includes memory, is the undo
button teams leave in place for a week. A `VirtualMachineSnapshot` is the
VM spec plus Container Storage Interface (CSI) volume snapshots. An online
snapshot asks the QEMU guest agent to quiesce guest filesystems. Without
the agent, the snapshot is best-effort. Plan on a disk rollback. Do not
plan on returning to the guest's RAM. There is no redo log to consolidate.
Restore is a `VirtualMachineRestore`. In 4.22 the default
`volumeRestorePolicy` is `PrefixTargetName`, so new PVCs are prefixed with
the target VM name. In-place restore can keep the original names.

Backup is still OpenShift API for Data Protection (OADP).
[OADP for OpenShift VMs: Backup Is Not DR](/posts/oadp-vms-backup-is-not-dr/)
is that split. A snapshot on the same array dies with the array.
The QEMU guest agent is also what the vROps post needs for guest memory
and filesystem alerts. One agent, two jobs.

## Objects that stay behind

| vSphere idea                                      | What you design instead                                      |
| ------------------------------------------------- | ------------------------------------------------------------ |
| Fault Tolerance                                   | Anti-affinity, live migration, and fencing. No lockstep twin |
| Shares, and a pool that borrows from its parent   | One quota per namespace. Shared idle capacity is one namespace |
| Folder permission inheritance                     | Git or an RHACM policy stamps each `RoleBinding`             |
| Snapshot the memory and decide next week          | A change window, plus OADP. The snapshot rolls disks back    |
| Linked-clone chains                               | A CDI clone from a `DataSource`                              |
| Manual DRS                                        | The scheduler places the VM. A node selector pins exceptions |
| The old alarm pack, copied one-for-one            | The five signals in the vROps post                           |

## The solutions architect takeaway

1. **Namespaces are the permission boundary.** Folders that only grouped
   VMs become labels. Nested folders do not become nested namespaces.
2. **AAQ is the resource pool.** A native `ResourceQuota` counts
   virt-launcher overhead and can block live migration. Shares and
   borrowing stay on the vSphere slide.
3. **Affinity is a schedule-time rule.** Must and should map to required
   and preferred. `KubeVirtRelieveAndMigrate` is how a rule gets a second
   chance.
4. **`view`, `edit`, and `admin` already include virt.** Console and power
   without delete is a custom role. `kubevirt.io:migrate` is a separate
   binding, and that has been the default since 4.19.
5. **The template is git.** Instance types for size, cloud-init or
   sysprep for identity, a `DataSource` for the disk. Console "convert to
   template" is Technology Preview in 4.22.
6. **A VM snapshot is disks and the spec.** The guest agent makes it
   consistent. OADP is the backup. Plan the rollback as disks.
7. **Write the landing zone down before MTV.** Labels, quotas, bindings,
   and affinity. The copy will not invent them.

If a non-prod cluster already runs Virtualization, the next proof is
small. One namespace per team that used to be a permission folder, one
AAQ quota, one anti-affinity rule for a pair that must not share a node,
and a binding that can open a console and cannot delete the VM. Then run
a live migration with a user who has `kubevirt.io:migrate`, and with a
user who does not.

## Related posts

- [What Replaces vRealize Operations for VMs](/posts/what-replaces-vrealize-operations/)
- [ACM as the Fleet Control Plane for OpenShift VMs](/posts/acm-openshift-virtualization/)
- [OADP for OpenShift VMs: Backup Is Not DR](/posts/oadp-vms-backup-is-not-dr/)
- [Fence Gray Host Failures on OpenShift Virtualization](/posts/openshift-virt-gray-failure-ha/)

> Want help turning a vCenter inventory export into namespaces, quotas, and
> roles? Reach out to your Red Hat account team—or build one namespace, one
> AAQ quota, and one console-only binding on a non-prod cluster before you
> standardize the map.
{: .prompt-tip }

## Further reading

- [About OpenShift Virtualization (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/about)
- [Managing VMs (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/managing-vms)
- [Live migration (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/live-migration)
- [Backup and restore (OpenShift Virtualization 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/backup-and-restore)
- [Using RBAC (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/authentication_and_authorization/using-rbac)
- [OpenShift Virtualization (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/configure-the-cluster/virtualization/)
