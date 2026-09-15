---
title: "OADP for OpenShift VMs: Backup Is Not DR"
description: >-
  OADP CSI snapshots and DataMover protect OpenShift Virtualization VMs.
  That is backup and restore, not Metro-DR, Regional-DR, live migration,
  or fencing.
date: 2026-09-14 16:00:00 -0500
categories: [OpenShift, Virtualization]
tags: [openshift, openshift-virtualization, storage, csi, gitops, acm]
permalink: /posts/oadp-vms-backup-is-not-dr/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization.
{: .prompt-info }

A VMware design review has a backup product and a disaster recovery (DR)
product, and they are not the same slide. On
[Red Hat OpenShift](https://www.redhat.com/en/technologies/cloud-computing/openshift)
the first answer for virtual machines (VMs) is often
[OpenShift API for Data Protection (OADP)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/backup_and_restore/oadp-application-backup-and-restore).
That is the right product for a point-in-time copy of an
[OpenShift Virtualization](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/index)
VM that you can restore later. It is the wrong product to satisfy a
recovery time objective (RTO) that was written for Site Recovery Manager.

OADP product docs will say DataMover gives you disaster recovery for
cluster loss, because the snapshot has left the array. Restore from object
storage after the cluster is gone is still a restore. It is not a declared
peer relationship, not a failover orchestrator, and not a tested RTO. This
post is that split for OpenShift Container Platform 4.22. It is a
solutions-architect map, not an install runbook. Confirm the
[OADP with OpenShift Virtualization](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/backup_and_restore/oadp-application-backup-and-restore)
procedure and the
[virtualization backup and restore](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/backup-and-restore)
chapter for the operator version you will actually run.

If you are still sequencing the landing zone, start with
[How to Get Started with an OpenShift PoC](/posts/getting-started-openshift-poc/).
Storage class and RWX Block still come before the first `Backup` custom
resource (CR)—see
[vSAN-like storage for OpenShift Virtualization Engine](/posts/ove-vsan-storage-alternatives/).
Fleet backup policy belongs on
[Red Hat Advanced Cluster Management for Kubernetes (RHACM)](/posts/acm-openshift-virtualization/),
not on a Velero click in each cluster console.

## Four phrases that get mixed in the room

| Phrase              | What it actually is                                      | What it is not                                      |
| ------------------- | -------------------------------------------------------- | --------------------------------------------------- |
| Backup              | Point-in-time copy you restore later                     | Failover                                            |
| Restore             | Rehydrate CRs and disks from that copy                   | A recovery time you have proven                     |
| Live migration      | Move a running VM between nodes or clusters              | A copy that survives storage-domain loss            |
| Disaster recovery   | Declared peer, replication, failover and failback        | `kind: Backup`                                      |

Host fencing is a fifth conversation. Node Health Check plus a remediator
restarts VMs after a hung node. That is
[gray-failure HA](/posts/openshift-virt-gray-failure-ha/),
not last night's disk. Live migration is a move with the VM still running;
the
[RHACM fleet post](/posts/acm-openshift-virtualization/)
already drew that line. Do not let a slide titled "data protection" cover
all four rows.

## What OADP is allowed to do for VMs

OADP is Velero, installed as an operator. The object you reconcile is a
`DataProtectionApplication` (DPA) in `openshift-adp`. For
OpenShift Virtualization the mandatory plugins are `kubevirt`, `csi`, and
`openshift`, plus the plugin for the object store that holds backup
metadata. On OpenShift 4.22, plan
[OADP 1.6](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/backup_and_restore/oadp-application-backup-and-restore).
OADP 1.5 is not the 4.22 pairing. Virt backups need OADP 1.3 or later;
do not treat that floor as the version you install today.

Red Hat supports two storage paths for OpenShift Virtualization backups:

- Container Storage Interface (CSI) backups
- CSI backups with DataMover

File system backup (Restic or Kopia walking the guest filesystem) and
Velero's native volume-snapshot path are excluded. CSI snapshots are still
snapshots. The excluded line is the older Velero snapshot API, not
`VolumeSnapshot`. Say that before someone "proves" OADP with
`defaultVolumesToFsBackup: true` on a VM disk.

The support matrix matches that story. For virt workloads, both Filesystem
and Block volume modes back up with CSI and with CSI DataMover. DataMover
is incremental on those paths and uses Kopia regardless of `uploaderType`.
File system backup is not supported for virt, even though the same matrix
allows it for ordinary container persistent volumes.

A CSI snapshot without DataMover lives next to the volume, on the array
that already holds production. That is rollback: clone back, recover from
operator error, feed a forensics namespace. Delete the cluster or lose the
storage domain and the snapshot goes with it.

DataMover is the off-cluster copy. The CSI plugin takes a snapshot, a
`DataUpload` reads it with Kopia, and the bytes land in the backup store.
That is how you restore after the cluster is gone. The RTO is snapshot
time plus upload plus download plus CSI provision plus VM start. Measure
it on a disk the size of production, not on a 20 GiB lab guest.

```yaml
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: vm-daily
  namespace: openshift-adp
spec:
  snapshotMoveData: true
  includedNamespaces:
    - vm-prod
  labelSelector:
    matchLabels:
      app: payments
  ttl: 720h
```

`snapshotMoveData: true` is the DataMover bit. Selection is a label, not
"every VM in the namespace" unless you meant that. GitOps the DPA, the
`BackupStorageLocation`, and the `Schedule`. Put object-store credentials
in
[External Secrets Operator](/posts/external-secrets-vs-secrets-store-csi/),
not in git.

## Consistency is a guest problem

An online VM snapshot is only as consistent as the QEMU guest agent.
`GuestAgent` means the agent quiesced the filesystem; treat that as
application-consistent for the guest OS, not as proof that Oracle or SQL
Server flushed in the way the DBA expects. `NoGuestAgent` is
crash-consistent: abrupt power-off. `QuiesceFailed` is a snapshot you
should not bless. Windows guests have an extra boot-time window: Volume
Shadow Copy Service (VSS) and the guest agent are not ready immediately
after reboot, and OADP can mark the backup `PartiallyFailed` until you
retry.

Multi-disk VMs are the other consistency conversation. Independent CSI
snapshots of boot and data volumes are not one point in time. Kubernetes
`VolumeGroupSnapshot` exists so related persistent volume claims (PVCs)
can snap together. In OADP 1.6 that path is Technology Preview. Evaluate
it; do not put it in the landing-zone default. Application-level backup
inside the guest (database dump, clustered application) still belongs on
the same design review as it did on vSphere.

OADP 1.6 also adds virtual machine file restore (VMFR): pull one file out
of a kubevirt-plugin backup without restoring the whole VM. Useful. Still
backup. `qcow2` and `raw` disks, plus `ext4`, `xfs`, `ntfs`, and `fat`. It
does not change RTO for site loss.

## Restore to another cluster is still restore

OADP can restore onto a different cluster. That does not mint a DR
program. The documented constraints are the ones that bite in a tabletop:

- Backup storage location names and paths must match.
- The clusters share object-storage credentials.
- You do not restore onto an older Kubernetes version than the source.
- Storage classes, snapshot classes, and RWX Block capability have to
  exist on the destination the way they existed on the source.
- The VM still needs networks, IPAM, DNS, and RBAC after the PVC comes
  back.

Namespace mapping is a restore feature. It is not a runbook for "the east
site is dark." If the RTO assumes a human will `oc apply` a `Restore` CR
and wait for DataMover download, write that number down and time it. Most
estates that said "DR" meant something closer to Metro-DR or
Regional-DR.

## When the answer is not OADP

Replication and failover are storage and DR products. CSI does not
standardize them.
[OpenShift Data Foundation (ODF)](https://docs.redhat.com/en/documentation/red_hat_openshift_data_foundation/4.22/)
Metro-DR and Regional-DR are the Red Hat-shaped version of that
conversation: RHACM hub, peer clusters, `DRPlacementControl`, failover
and failback. Metro has a latency budget. Regional is asynchronous and
accepts a replication gap. External-mode Metro-DR is deprecated in ODF
4.22; do not draw a new design on a path that is leaving. Confirm the
current
[ODF disaster recovery](https://docs.redhat.com/en/documentation/red_hat_openshift_data_foundation/4.22/html/configuring_openshift_data_foundation_disaster_recovery_for_openshift_workloads/index)
guide for the mode you will actually buy.

If the array already replicates—Dell PowerStore, Pure FlashArray, IBM
Fusion, and the rest of the certified CSI list—use that replication and
the vendor's failover story. Do not add ODF because a
backup slide felt empty. The
[OVE storage shortlist](/posts/ove-vsan-storage-alternatives/)
is the place to pick the backend; this post is only the protection layer
on top of it.

Partner backup products still have a job when the requirement is a
catalog, tenant self-service, or application-aware workflows that OADP
does not pretend to own. IBM Fusion is the one that already sits in the
storage conversation. Name the product in the design; do not let "we
installed OADP" stand in for a bake-off you skipped.

## Fleet backup is still OADP

RHACM 2.16 does not replace OADP for VMs. It installs and schedules it.
Labels on the `VirtualMachine` select a cron from a hub ConfigMap.
Policies create Velero schedules. Compliance is whether the last backup
completed. Supported paths are still CSI or CSI with DataMover. That
model belongs in git the same way everything else on the hub does:
[GitOps should manage ACM, not the cluster](/posts/gitops-should-manage-acm/).

Restore from the hub is a separate policy, including optional namespace
mapping. Same objects, wider blast radius. A hub that can restore every
VM in the estate is a privilege concentrator; keep it on the same RBAC
conversation as fleet live migration.

## The solutions architect takeaway

1. **OADP is backup and restore for virt** — `kubevirt` plus CSI, or CSI
   with DataMover. File system backup is not a virt path.
2. **CSI snapshot without DataMover is rollback** — it dies with the
   array. DataMover is the off-cluster copy; time the restore.
3. **Guest agent is consistency** — crash-consistent is not a database
   recovery point objective (RPO). VolumeGroupSnapshot is Technology
   Preview.
4. **Restore to another cluster is not Metro-DR** — matching buckets and
   a `Restore` CR are not failover.
5. **HA, live migration, and DR stay on their own slides** — fence a
   gray host, move a running VM, or fail over a replica. None of those
   is `kind: Backup`.
6. **RHACM policy is OADP at fleet scale** — labels and schedules, still
   not a recovery objective.

If a non-prod cluster already has Virtualization and a certified storage
class with snapshots, the next proof is small: one labeled VM, one
`Backup` with `snapshotMoveData: true`, one restore into a scratch
namespace, and a stopwatch. Pair that with the
[OpenShift Virtualization (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/post-installation/virtualization/)
install and the
[operations](https://openshift-ssa.github.io/openshift-poc/operations/)
failover demos. Then write the RTO you actually measured, not the RTO
the backup product logo implied.

## Related posts

- [ACM as the Fleet Control Plane for OpenShift VMs](/posts/acm-openshift-virtualization/)
- [vSAN-like Storage for OpenShift Virtualization Engine](/posts/ove-vsan-storage-alternatives/)
- [Fence Gray Host Failures on OpenShift Virtualization](/posts/openshift-virt-gray-failure-ha/)
- [GitOps Should Manage ACM, Not the Cluster](/posts/gitops-should-manage-acm/)

> Want help splitting OADP restore from a Metro-DR or Regional-DR design?
> Reach out to your Red Hat account team—or time a DataMover restore of
> a production-sized disk on a non-prod cluster before you call it DR.
{: .prompt-tip }

## Further reading

- [OADP application backup and restore (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/backup_and_restore/oadp-application-backup-and-restore)
- [Backup and restore (OpenShift Virtualization 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/backup-and-restore)
- [ODF disaster recovery for OpenShift workloads](https://docs.redhat.com/en/documentation/red_hat_openshift_data_foundation/4.22/html/configuring_openshift_data_foundation_disaster_recovery_for_openshift_workloads/index)
- [OpenShift Virtualization (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/post-installation/virtualization/)
- [VM failover (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/operations/vm-failover/)
- [Storage (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/post-installation/storage/)
- [OpenShift Data Foundation (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/post-installation/storage/odf/)
