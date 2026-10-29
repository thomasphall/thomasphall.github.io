---
title: "Migrate Oracle Databases to OpenShift Virtualization"
description: >-
  How to move Oracle databases from vSphere to OpenShift Virtualization:
  Data Guard or MTV, RAC shared disks, block storage, and a node pool for
  a license review.
date: 2026-10-29 08:00:00 -0500
categories: [OpenShift, Virtualization]
tags: [openshift, openshift-virtualization, vmware, migration, storage, gitops]
permalink: /posts/oracle-database-vsphere-to-openshift-virt/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization. Oracle licensing follows your
> contract. The partitioning policy cited below is Oracle's published
> guideline. Oracle says that document is not a contract and that it can
> change.
{: .prompt-info }

A VMware exit can move a web server with the
[Migration Toolkit for Virtualization](https://docs.redhat.com/en/documentation/migration_toolkit_for_virtualization/2.12)
(MTV) and a weekend window. An Oracle database asks three questions before
anyone picks a migration plan: which physical servers the software will be
allowed to run on, whether the cutover ships redo or a disk, and who owns
the device names inside the guest after VMware PVSCSI is gone.

This is that design review for
[Red Hat OpenShift](https://www.redhat.com/en/technologies/cloud-computing/openshift)
Container Platform 4.22 and
[OpenShift Virtualization](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/index).
The guest in scope is Oracle Database on Linux, Red Hat Enterprise Linux
(RHEL) or Oracle Linux, same architecture you run on vSphere today, x86 to
x86. Oracle Real Application Clusters (RAC) and Exadata are later waves.
If the cluster is still a diagram, start with
[How to Get Started with an OpenShift PoC](/posts/getting-started-openshift-poc/)
and the
[OpenShift Virtualization (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/configure-the-cluster/virtualization/)
install. Namespaces, quotas, and labels are
[vSphere to OpenShift Virtualization: Translation Guide](/posts/vsphere-to-openshift-translation-guide/).
Put the `VirtualMachine`, the kubelet config, and the network attachments
in git on the same split as
[GitOps Should Manage ACM, Not the Cluster](/posts/gitops-should-manage-acm/).

Red Hat published a performance validation of Oracle Database 19c (19.26)
on RHEL 8.10 on OpenShift Virtualization 4.18.9: single instance and RAC,
OpenShift Data Foundation and Fibre Channel, plus live migration under
load. Use it as evidence the platform can run the database. Re-measure on
4.22 with your storage and your System Global Area (SGA) before you quote
that lab in a design review.

## Sort the estate before you pick a tool

The DBA, the virtualization admin, and the person who owns the Oracle
agreement sit in this review together. The inventory is short. Each row
changes the plan.

| What you record                         | What it decides                                              |
| --------------------------------------- | ------------------------------------------------------------ |
| Single instance or RAC                  | Shared disks and a private interconnect, or a normal VM     |
| Data Guard role, and which site is home | Whether the first OpenShift VM is a standby                  |
| ASM, filesystem, or raw device          | How the guest finds disks after the controller changes      |
| RDM, multi-writer, or shared VMDK       | A new disk layout on the target                              |
| Size of data files, redo, and FRA       | A copy window, or redo apply while production stays open    |
| RPO and RTO                             | Switchover budget, or a closed-database copy                 |
| TDE, and where the wallet lives         | A file that has to arrive with the database                  |
| Processor or NUP, and the vSphere cluster you license today | How small a worker pool you can draw |
| Exadata or Oracle Database Appliance    | A sizing project, because the storage tier stays behind     |
| Guest OS and Oracle release update      | The OS and the RU stay put in this window                   |

Keep the Oracle release update, the character set, the Oracle home path,
and the SID stable. Patch in another change. An x86 to x86 move is the
same endianness, so this window is a platform move.

Dev and test single-instance databases with a real outage window are the
first proof. Production single instance goes next, by redo. RAC, shared
raw disks, and engineered systems wait, the same way
[32-bit VMs Stay Out of OpenShift Wave 1](/posts/32-bit-vms-not-wave-1/)
keeps an unsupported guest out of the first MTV plan.

## Move redo, or copy a closed database

MTV copies a virtual machine (VM). Oracle Data Guard ships redo to a
database you built on the target. Recovery Manager (RMAN) restores a
backup into that new VM. Those are three different outages.

| Estate                                              | How it moves                                      | What the users feel                          |
| --------------------------------------------------- | ------------------------------------------------- | -------------------------------------------- |
| Dev or test, single instance, window fits the copy | Cold MTV of a database closed with `shutdown immediate` | The copy                            |
| Single instance, large disks, short outage is acceptable | Warm MTV, database closed before cutover   | The delta, after a clean shutdown            |
| Production single instance                          | New VM on OpenShift, Data Guard, then switchover | A role change once apply lag is at zero      |
| Production, and Data Guard is off the table        | RMAN restore and recover into a new VM           | The restore window                           |
| RAC                                                 | New Grid Infrastructure on shared block, then Data Guard or a rebuild | Its own project        |
| Exadata or Oracle Database Appliance               | Data Guard onto a VM sized for ordinary storage  | Its own project                              |

Oracle GoldenGate is the cutover when the source and target are different
enough that a physical standby cannot do the job, or when the outage
budget is shorter than a switchover and you already run GoldenGate.
Same version, same OS family, vSphere to OpenShift Virtualization: Data
Guard or a closed-database copy covers the estate. Data Pump refreshes a
small schema or a dev database. It is a long outage for multi-terabyte
OLTP.

A mounted standby that applies redo is Data Guard, which Enterprise
Edition includes. Opening that standby for reads while apply continues is
Active Data Guard, a separate option. Confirm which contract you have
before an application team asks to query the standby during the rehearsal.

### Build the standby on OpenShift first

This is the production path.

1. Build the target VM on the Oracle worker pool, with virtio disks from
   the start. You never inherit PVSCSI names.
2. Keep the same version and release update. Duplicate with RMAN, or
   restore a backup, then enable Data Guard with real-time apply. Wait
   until apply lag sits at zero.
3. Rehearse switchover and switchback. Time both. Clients should use a
   DNS name, a SCAN name you control, or a load balancer. An IP that
   moves because someone rebuilt `listener.ora` under pressure is a
   longer outage than the role change.
4. Cut over with a switchover. The vSphere VM becomes the standby. Leave
   it in place through the next successful RMAN backup on the new primary
   and one business cycle.
5. Rollback is a switchback.

The copy of the data files happens while production is open. The weekend
is a role change you have already timed. A second site is a second
OpenShift cluster with its own worker pool, and Data Guard between them.

If the IP address has to stay, attach the VM to the existing VLAN with a
bridged network. That map is
[OpenShift Virtualization Networking: Pod to Localnet](/posts/openshift-virtualization-networking/).
A pod-network address is a new firewall ticket and a new connection
string.

### Cold or warm MTV when the VM is the artifact

Cold MTV fits a database you can close for the whole copy. Warm MTV
precopies while the VM runs, then copies the delta after shutdown. For
Oracle, that shutdown is `shutdown immediate`, then stop the listener.
A hard power-off still boots, and Oracle performs instance recovery, the
same as a crashed host. Prefer the clean close so the alert log on the
target starts quiet.

Consolidate VMware snapshots before the plan runs. A snapshot chain
lengthens the copy. Multi-terabyte data files that do take this path
should use the storage copy, when the array supports it:
[VMware to OpenShift Virtualization: Copy Offload](/posts/mtv-storage-copy-offload-vmware/).
For operator install and VDDK in a PoC, use the
[Migration Toolkit for Virtualization (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/configure-the-cluster/mtv/)
guide.

After cutover, one copy stays powered off until you accept the target.
Two open databases with the same name are a split brain.

RDMs and multi-writer VMDKs, the usual RAC layout on vSphere, become new
persistent volume claims. Create the database, or the standby, against
those claims.

## The landing zone

### Workers

Oracle workers are their own MachineConfigPool, labeled and tainted
`workload=oracle:NoSchedule`. The database VM tolerates that taint and
selects the label. Everything else stays off those nodes. The pool is
also the diagram you take to the license review: these servers, these
cores, and no live migration onto the general worker pool.

Size it to N+1 for the largest VM if you intend to live-migrate or to
restart after a node dies. Dedicated CPUs have to be free on the target.
A node whose RAM equals the guest stays Pending once virt-launcher
overhead lands. Leave that headroom.

Application-Aware Quota is how you cap the namespace. A native
`ResourceQuota` counts virt-launcher overhead and can reject the second
pod a live migration starts. The translation guide has that distinction.
Quota still does not create a free node. The target needs physical cores.

### CPU and memory

`dedicatedCpuPlacement` requires the static CPU Manager policy. Set it
with a `KubeletConfig` on the Oracle pool (`cpuManagerPolicy: static`),
then reboot those nodes before the first database VM. Guaranteed quality
of service means CPU and memory requests equal limits, and CPU requests
are whole cores. The guest topology (`sockets`, `cores`, `threads`) is
the topology you will show in the license review. Record it.

`isolateEmulatorThread: true` gives QEMU's emulator thread its own
physical CPU, outside the guest. A 16-vCPU guest needs a 17th isolated
CPU on the node, or the VM stays Pending. `autoattachMemBalloon: false`
keeps the SGA at the size you set. A balloon under memory pressure
shrinks the guest to save the node. Oracle would rather the node show
the pressure.

`model: host-passthrough` gives the guest the host CPU flags. Live
migration then requires a compatible CPU generation inside the pool.
Keep the pool on one generation.

Hugepages match on both sides. If the guest allocates huge pages for the
SGA (`USE_LARGE_PAGES` in the published test was `AUTO`), the node has
to have those pages reserved. Topology Manager policy `single-numa-node`
fits a VM that lives on one socket. A VM larger than a socket needs a
guest NUMA layout you have tested.

Red Hat's low-latency performance profiles also turn on static CPU
Manager, and the examples in that guide often enable a realtime kernel.
Leave the realtime kernel off for Oracle. A telco profile copied onto a
database node is a different product decision.

`runStrategy: Always` crash-restarts the VM when a fenced node is gone.
That is vSphere HA, followed by Oracle instance recovery.

`evictionStrategy` is the maintenance question.
[Upgrading OpenShift While VMs Stay Running](/posts/upgrading-openshift-while-vms-stay-running/)
is how a drain uses that field.

| Strategy                 | Use it when                                                                 |
| ------------------------ | --------------------------------------------------------------------------- |
| `LiveMigrate`            | Single instance, storage that can move, and you have timed a migration of this SGA |
| `LiveMigrateIfPossible`  | SR-IOV or another device that often cannot move. The drain must not sit forever |
| `None`                   | You want node maintenance to wait until a DBA closes or relocates the database |

In Red Hat's 4.18 test, a single-instance VM with 16 vCPU and 48 GB
migrated in one to two minutes, idle or under Swingbench, with a short
dip in transactions and no failed transactions. They had not tuned live
migration. Your 512 GB SGA is a different measurement. Time it on a
non-prod copy before you promise an upgrade window.

Overcommit is off this pool. The published guidance is the same: give
the VM the cores and RAM it needs, and stop.

### Disks

Redo commit latency is the storage design. Block for data and redo.
[OpenShift Storage Performance: Disks, IOPS, Architectures](/posts/openshift-storage-performance/)
is the broader rule: pick the access mode from the workload. NFS as a
universal share is how redo commits get slow.

| Disk                    | Claim                                      | Practice                                                                 |
| ----------------------- | ------------------------------------------ | ------------------------------------------------------------------------ |
| OS and Oracle binaries  | RWO filesystem                             | `fstab` by UUID                                                          |
| Data files              | RWO block, or a filesystem with direct I/O | `cache: none`, its own IO thread, preallocated                          |
| Redo                    | The lowest-latency block you have          | Its own PVC                                                              |
| Fast recovery area      | Capacity-oriented block or filesystem      | The RMAN destination                                                     |
| RAC ASM disks           | RWX block, `shareable: true`               | One claim per disk. External redundancy when the array already mirrors  |

`cache: none` keeps the commit on the array. A writeback cache can
acknowledge a write while it still sits in the host. For a filesystem
database, `FILESYSTEMIO_OPTIONS=SETALL` turns on direct and asynchronous
I/O in the guest, which is what the published single-instance test used.

Red Hat's lab compared storage on that 19c workload. Fibre Channel on a
Pure FlashArray, provisioned through Portworx, delivered about 26 percent
higher transactions per minute than OpenShift Data Foundation for single
instance, and about 83 percent higher for RAC. Local NVMe tracked the
Fibre Channel result for single instance. RAC on OpenShift Data
Foundation spent a large share of CPU in I/O wait. Treat those deltas as
that lab, on those Dell R660 nodes. The ordering is what you design
around: single instance can be proven on OpenShift Data Foundation, and
RAC wants an array path you have already measured.

Thick or preallocated volumes (`preallocation: true` on the
DataVolume) so the first load pays for space up front. The test did
that.

### Networks

Split the traffic the way the database already splits it.

| Traffic            | Where it goes                                                                 |
| ------------------ | ----------------------------------------------------------------------------- |
| Clients, listeners | Bridged VLAN when the IP and the firewall ticket stay. SR-IOV when you have measured a latency need |
| Storage            | The array network on the node, CSI in front, virtio in the guest             |
| RAC interconnect   | Its own NIC and subnet. SR-IOV in the published RAC test                     |
| Live migration     | The cluster migration network                                                |

The interconnect and the migration network are different links. Sharing
them is how a maintenance move looks like a cluster partition.

## What the guest sees after MTV

A Data Guard target was built with virtio, so this section is the MTV
path. The controller change is the outage that happens after the progress
bar says the copy finished.

VMware PVSCSI presents `/dev/sd*`. virtio-blk presents `/dev/vd*`.
virtio-scsi stays on `/dev/sd*` and can still enumerate in a new order.
`fstab` entries that use UUIDs come along. Automatic Storage Management
(ASM) disk strings and udev rules often name a path or a VMware vendor
ID. Those do not match a QEMU disk. Update the discovery string, or
rescan ASMLib or the ASM Filter Driver, before `startup`. The published
RAC test used the ASM Filter Driver. The scan is part of cutover, whoever
builds the VM.

Then:

- The Transparent Data Encryption (TDE) wallet has to be on a filesystem
  that mounted, or the client config has to reach Oracle Key Vault from
  the new network. A missing wallet looks like a failed migration.
- Remove `open-vm-tools`. Install `qemu-guest-agent`.
- One time source. `chronyd` in the guest, and the VMware Tools time
  sync gone. Data Guard apply and the alert log both assume the clocks
  agree.
- SELinux stays enforcing. A device-permission problem gets a policy fix,
  or a context on the new device path.

Grid Infrastructure is more sensitive to NIC names and disk paths than a
single-instance home. That is another reason a RAC cluster is rebuilt on
the target disks.

## RAC and Exadata wait

RAC on OpenShift Virtualization is a supported shape in Red Hat's
validation: two VMs, shared volumes, ASM disk groups for OCR, data, and
the fast recovery area, external redundancy, Grid Infrastructure 19c.
Shared disks are RWX block claims marked shareable. Instances are
anti-affine so two RAC nodes do not land on one worker. Fencing is still
a Clusterware design. A virt-launcher restart is crash recovery of a
node, and Clusterware has to agree.

In that same test, live migration of one RAC node took about three
minutes. The SR-IOV move paused the interconnect long enough for
Clusterware to drop heartbeats and fail services onto the other node.
Transactions did not fail. Throughput dropped, then Oracle restored the
second instance after the move. The operational rule: relocate services,
then move or stop the VM. A drain that live-migrates a RAC node will
demonstrate this for you during an upgrade.

Their closing recommendation matches the result. Separate physical
devices for client traffic, storage, and the interconnect. SR-IOV where
the hardware has it. Fibre Channel, or storage in that class, for RAC
data and redo.

Exadata and the Oracle Database Appliance stay a different project. Smart
Scan, storage indexes, and Hybrid Columnar Compression offload live in
the storage servers. MTV can copy a VM disk. It cannot copy that tier.
The move is Data Guard onto a VM whose storage you sized for the loss of
those offloads, with a performance test before cutover.

## Backup, crash restart, and failover

Three copies, three jobs.

| Job                         | Product                                                                 |
| --------------------------- | ----------------------------------------------------------------------- |
| Recover a block or a table | RMAN, on the schedule you already trust                                 |
| Fail over a site           | Data Guard                                                              |
| Restore a VM spec and disks | [OADP for OpenShift VMs: Backup Is Not DR](/posts/oadp-vms-backup-is-not-dr/) |

An OpenShift VM snapshot, or an OADP backup, is a point in time of disks
and the `VirtualMachine` spec. RMAN is the contract for a consistent
Oracle backup. Take a backup on the target before you call the migration
done. The source stays powered off, and intact, until that backup
succeeds.

Node loss is
[Fence Gray Host Failures on OpenShift Virtualization](/posts/openshift-virt-gray-failure-ha/).
The guest still crashes. `runStrategy: Always` starts it on a healthy
node that has the cores and the volume. Oracle performs instance
recovery. That is the vSphere HA behavior your runbooks already describe.
It is slower than RAC service failover, and it is slower than Data Guard
fast-start failover. If the recovery time objective was written for one
of those, the database feature has to be in the design, licensed, and
rehearsed.

Automatic Workload Repository reports need the Diagnostics Pack. If that
option is on the contract, AWR still explains the database. Platform
metrics for the VM live in the OpenShift monitoring stack. Red Hat's
validation scraped database metrics with Oracle's database exporter into
Prometheus. Use that if you want one dashboard. Skip AWR if the pack is
absent.

## The license boundary is the node pool

Do this review before you enlarge a cluster or shrink one.

Oracle's partitioning policy, the guideline dated 14 February 2022 at
publication, separates hard and soft partitioning. Soft partitioning,
and the policy names VMware and affinity management among the examples,
does not set the number of licenses for a server or a cluster of
servers. The hard-partition list is specific. Oracle Linux KVM is on it
only in the configuration described in Oracle's Oracle Linux KVM paper
(July 2024): vCPUs bound to physical CPUs, and live migration of those
pinned VMs left disabled. That paper is Oracle Linux KVM with Oracle
Linux Virtualization Manager. Trusted partitions are a further program,
on approved Oracle engineered systems, using Oracle VM or Oracle Linux
KVM.

> OpenShift Virtualization does not appear on that hard-partition list.
> `dedicatedCpuPlacement` pins vCPUs so the database does not take steal
> time. Bring the worker pool, the taint, and the live-migration
> boundary to the people who own the Oracle agreement, and get a written
> answer before you treat a smaller pool as a smaller license.
{: .prompt-warning }

The Oracle Linux paper is still useful as a signal. On the KVM Oracle
does document, live migration of a pinned VM drops hard-partition
accounting, and the servers themselves have to be licensed. Read that as
a warning about migration scope. The formula in that paper is for Oracle
Linux KVM. Apply it to OpenShift only if Oracle has told you to.

What you can draw today:

- The tainted pool is the set of servers the VM can be scheduled onto.
- Live migration targets are part of that set. A general-purpose cluster
  with migration onto every worker is a large set.
- Options you use now come with the database. RAC, Partitioning, Active
  Data Guard, Advanced Security, Diagnostics. The hypervisor change does
  not retire them.
- Processor versus Named User Plus, and the core factor, stay in your
  contract and in Oracle's core factor table. Write down the socket and
  core topology the guest will see.

A move from a fully licensed vSphere cluster onto a smaller OpenShift
pool can be the commercial reason for the project. It can also be an
accident in the other direction if the new cluster is larger than the
old one and every worker can run the VM. Finish that conversation before
wave one of databases. Dev and test on Named User Plus belong in their
own pool if mixing them would muddy the diagram.

Support splits the same way. Oracle supports Oracle Database on a
certified guest operating system. Red Hat supports OpenShift
Virtualization. In
[The Oracle estate you can control](https://www.redhat.com/en/blog/oracle-estate-you-can-control),
Red Hat describes Oracle's certification as attaching to the OS in the
guest, and points to the 19c validation for the performance evidence.
RHEL 8.10 is the guest that validation published numbers for. Keep the
Oracle support agreement and the OS subscription aligned with the guest
you run. A defect that shows up only on the hypervisor needs a path both
vendors have already accepted. Agree that path while the database is
still on vSphere.

## The solutions architect takeaway

1. **Sort the estate.** Dev single instance with a window can move by
   cold MTV. Production single instance moves as a standby you built on
   OpenShift, then a switchover. RAC, shared raw disks, and Exadata are
   later projects.
2. **The node pool is the license diagram.** Static CPU Manager and
   `dedicatedCpuPlacement` take steal off the guest. Ask the license
   owner, in writing, whether that pool is also the license boundary.
3. **Block disks, separate redo, no balloon, no overcommit.**
   `cache: none` on data and redo. Filesystem guests use direct I/O.
   RAC uses RWX block, one claim per ASM disk.
4. **After MTV, fix discovery before `startup`.** ASM strings, udev,
   the TDE wallet, and time sync. The source stays powered off.
5. **RMAN, Data Guard, and OADP are three copies.** Crash restart is
   instance recovery. A recovery time objective written for RAC or
   fast-start failover has to name that product.
6. **Re-measure.** The published validation is 19c on RHEL 8.10 on
   OpenShift Virtualization 4.18. Carry the design to 4.22. Time live
   migration on your SGA before an upgrade plan depends on it.

The next proof is small. One non-prod single-instance database. A
standby on the tainted pool. A timed switchover and switchback. One
RMAN restore onto that VM. Then one cold MTV of a small closed database,
so the disk-name change is a lesson you have already had.

## Related posts

- [vSphere to OpenShift Virtualization: Translation Guide](/posts/vsphere-to-openshift-translation-guide/)
- [VMware to OpenShift Virtualization: Copy Offload](/posts/mtv-storage-copy-offload-vmware/)
- [OADP for OpenShift VMs: Backup Is Not DR](/posts/oadp-vms-backup-is-not-dr/)
- [OpenShift Storage Performance: Disks, IOPS, Architectures](/posts/openshift-storage-performance/)

> Want help sorting an Oracle estate into a node pool, a Data Guard
> cutover, and an MTV wave? Reach out to your Red Hat account team—or
> build one non-prod standby on a tainted pool and time a switchover
> before you schedule production.
{: .prompt-tip }

## Further reading

- [Oracle Database 19c on OpenShift Virtualization: performance validation](https://www.redhat.com/en/blog/Oracle-Database-Workloads-On-OpenShift-Virtualization-Reference-Architecture)
- [The Oracle estate you can control](https://www.redhat.com/en/blog/oracle-estate-you-can-control)
- [Oracle Partitioning Policy (guideline, 14 February 2022)](https://www.oracle.com/a/ocom/docs/it-infrastructure/partitioning-070609.pdf)
- [Hard Partitioning with Oracle Linux KVM (July 2024)](https://www.oracle.com/a/ocom/docs/linux/ol-kvm-hard-partitioning.pdf)
- [Introduction to Oracle Data Guard (19c)](https://docs.oracle.com/en/database/oracle/oracle-database/19/sbydb/introduction-to-oracle-data-guard-concepts.html)
- [About OpenShift Virtualization (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/about)
- [Managing VMs (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/managing-vms)
- [Live migration (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/live-migration)
- [Using CPU Manager (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/scalability_and_performance/using-cpu-manager)
- [Provisioning low-latency workloads (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/scalability_and_performance/cnf-provisioning-low-latency-workloads)
- [Migration Toolkit for Virtualization 2.12](https://docs.redhat.com/en/documentation/migration_toolkit_for_virtualization/2.12)
- [OpenShift Virtualization (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/configure-the-cluster/virtualization/)
- [Migration Toolkit for Virtualization (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/configure-the-cluster/mtv/)
