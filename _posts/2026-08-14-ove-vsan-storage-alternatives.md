---
title: "vSAN-like Storage for OpenShift Virtualization Engine"
description: >-
  Replace vSAN-style local disks on OpenShift Virtualization Engine without
  ODF using Portworx, PowerFlex, LINSTOR, IBM Fusion, or certified CSI arrays.
date: 2026-08-14 12:00:00 -0500
categories: [OpenShift, Virtualization]
tags: [openshift-virtualization, storage, csi, vsan]
image: /assets/img/og/ove-vsan.png
permalink: /posts/ove-vsan-storage-alternatives/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization.
{: .prompt-info }

Most VMware exit programs that land on
[OpenShift Virtualization](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/index)
do not stall on KVM. They stall on storage. vSAN customers are used to a
simple story: disks in the hosts, software replication, vMotion on a shared
datastore. The first Red Hat answer they hear is often OpenShift Data
Foundation (ODF). That is a good answer. It is not the only one, and it is
**not included** with OpenShift Virtualization Engine (OVE).

This post is a solution-architect shortlist for platform and virtualization
teams who want vSAN-like *local-disk* storage on OVE, or who already have a
SAN and should not invent an HCI layer on top of it. It is not an install
runbook, and it is not a support matrix. Partner listings move. Confirm the
current
[OpenShift Virtualization storage compatibility article](https://access.redhat.com/articles/7128992)
(KCS 7128992) and the [Red Hat Ecosystem Catalog](https://catalog.redhat.com/)
for your OpenShift version before you freeze a design.

## OVE is not a storage subscription

OVE is the VM-only OpenShift SKU. Virtualization is included. ODF Essentials
is not. ODF Essentials ships with OpenShift Platform Plus. You can buy ODF
separately, and many teams should. You can also run partner software-defined
storage as infrastructure containers that back VM disks. That pattern is
explicit in the
[self-managed OpenShift subscription guide](https://www.redhat.com/en/resources/self-managed-openshift-subscription-guide):
storage drivers and SDS that exist to serve VMs are infrastructure, not
guest applications. Confirm any borderline workload with Red Hat if it is
not clearly a CSI driver or a storage control plane.

If the conversation is “we picked OVE so we would not buy ODF,” the next
question is which certified CSI still gives you live migration. That is the
whole problem.

## What “vSAN-like” actually means here

vSAN aggregates local disks, replicates across hosts, and stays available
during vMotion. OpenShift Virtualization maps that to Kubernetes CSI, not to
a datastore object.

Live migration needs
[ReadWriteMany (RWX)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/live-migration)
so the source and destination nodes can attach the same VM disk. Prefer
**Block** volume mode. Filesystem mode adds a guest image file on top of a
filesystem on top of a volume, and it is slower for VM disks. Snapshots and
clones are what make golden images, MTV imports, and crash-consistent
backups cheap. Volume expansion is table stakes. Replication and DR are
vendor features, not a CSI standard.

| Capability              | Why it matters for OVE                         | vSAN analog                         |
| ----------------------- | ---------------------------------------------- | ----------------------------------- |
| RWX + Block             | Live migration, node drain, cluster upgrades   | vMotion on a shared datastore       |
| CSI snapshots / clones  | Fast provision, MTV, crash-consistent backup   | vSAN snapshots / linked clones      |
| Volume expansion        | Grow VM disks online                           | Datastore / VMDK expand             |
| Replication / DR        | Host failure and site recovery (vendor-specific) | Failures to tolerate, stretched cluster, Site Recovery Manager |

LVM Storage (LVMS / TopoLVM) and the Local Storage Operator do not clear any
row in that table, by design. They bind a volume to **one node** (RWO) and do
not replicate across hosts. Fine for a lab disk, including the
[Pure FlashArray + NVMe/TCP + LVMS SNO pattern](/posts/pure-flasharray-sno-nvme-tcp/).
Not a vSAN replacement on a multi-node OVE cluster. If the PVC is RWO, live
migration is blocked and the VM powers off on drain.

## Three architectures, not thirty products

Red Hat’s
[storage considerations for OpenShift Virtualization](https://developers.redhat.com/articles/2025/07/10/storage-considerations-openshift-virtualization)
cuts the problem into three models. Pick the model first. Then pick a
vendor.

| Model                         | Where the disks live                                      | When to use it                                                              |
| ----------------------------- | --------------------------------------------------------- | --------------------------------------------------------------------------- |
| Internal SDS (HCI or partial) | Local NVMe/SSD on OVE nodes                               | True vSAN analog; no array; platform team owns storage                      |
| External CSI (SAN / NAS)      | PowerFlex, FlashSystem, ONTAP, Alletra, FlashArray, VSP   | You already have an array; storage team keeps the data plane                |
| Shared-disk file system       | One large LUN + IBM Fusion Access or Arctera Infoscale    | Older SAN without a mature RWX CSI; typically up to roughly 40 nodes        |

HCI SDS is the vSAN operating model: disks in the hypervisor hosts, software
pool, CSI on top. External CSI is the FC/iSCSI/NVMe-oF datastore model you
already run next to vSAN. Shared-disk file systems exist for arrays whose
CSI is not VM-grade yet.

Do **not** drop ODF or Portworx on top of a SAN that already has a working
RWX CSI. That is an extra license, extra latency, and write amplification
from a second replication layer. Use it only when the array CSI cannot do
RWX, snapshots, clones, or small-LUN-per-VM-disk provisioning.

## HCI / local-disk SDS: the vSAN shortlist

These products consume disks in the OVE nodes (or a storage-node subset)
and present RWX block through CSI. No external array required.

| Product                 | Partner                    | Topology                                              | OVE virt fit                                      | Notes                                                                                          |
| ----------------------- | -------------------------- | ----------------------------------------------------- | ------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| Portworx Enterprise     | Everpure (Pure lineage)    | HCI on local SCSI/NVMe; also FlashArray or other arrays | Certified, including local disk                 | Most common vSAN stand-in. Same product can later front a FlashArray if you leave HCI.         |
| Dell PowerFlex          | Dell                       | HCI rack/appliance or two-layer SDS                   | Certified via Dell CSM                            | NVMe/TCP or PowerFlex protocol. Natural if the account already runs Dell SDS.                  |
| LINSTOR + DRBD          | LINBIT                     | Replicated local block on OVE nodes                   | Certified for OpenShift Virtualization            | Lightest analog to vSAN FTT. Live migration, snapshots, clones, RWX verified.                  |
| IBM Storage Fusion      | IBM                        | Fusion HCI appliance or SDS software                  | IBM + Red Hat joint path                          | Fusion Data Foundation is Ceph-family (ODF-like). Fusion Access for SAN is the shared-FS path. |
| Hitachi VSP One SDS     | Hitachi Vantara            | Software-defined block                                | Certified (SPC)                                   | SDS sibling of VSP One Block. Closer to an array SDS than “disks in the hypervisor.”           |
| ODF (purchased)         | Red Hat                    | Ceph HCI or external Ceph                             | First-party, designed with Virtualization         | Not in the OVE bundle. Use `ocs-storagecluster-ceph-rbd` with `volumeMode: Block`, not CephFS. |

**Portworx on local disks** is the default I put on the whiteboard when the
requirement is “vSAN, but OpenShift.” The
[compatibility article](https://access.redhat.com/articles/7128992)
lists local disk, FlashArray, and third-party arrays under Portworx
Enterprise, with OpenShift Virtualization and VDI. You are not locked into
HCI forever.

**PowerFlex** is the Dell HCI/SDS answer. PowerMax and PowerStore are the
Dell *array* answers. Unity XT is a different conversation: the lab path in
[Dell Unity over iSCSI](/posts/openshift-virt-dell-unity-iscsi/) can attach
block, but Unity is often missing from the OpenShift Virtualization column
of Dell’s CSM matrix even when PowerFlex is listed. Do not assume every
Dell CSI driver is virt-capable.

**LINSTOR** is the interesting lightweight option. LINBIT ran Red Hat’s CSI
e2e suite *and* the kubevirt-storage-checkup (live migration, RWX,
snapshots, clones, hot-plug, expansion). Support is LINBIT, not Red Hat
storage support. That is acceptable for many OVE designs if the account
wants DRBD-style local NVMe without a Ceph control plane.

**IBM Storage Fusion** is the IBM HCI path. Internal disks go through Fusion
Data Foundation. Existing IBM SAN can stay on IBM block CSI (FlashSystem,
SVC, Storage Virtualize) or move to Fusion Access for SAN. Prefer raw block
for VM disks.

simplyblock and Lightbits market NVMe/TCP SDS as an ODF/vSAN alternative
and show up in catalog or vendor virt pages. They were **not** on KCS
7128992 when I last checked. Treat them as evaluation candidates, not the
default shortlist, until the vendor shows a current OpenShift Virtualization
badge for your OpenShift version.

## Certified arrays: keep the SAN, skip the HCI story

If the disks already live in an array, you are replacing a VMFS/NFS
datastore, not vSAN. Use the vendor CSI. Confirm RWX (block or NFS),
snapshots, and clones.

| Vendor              | Product                                              | Typical protocol                         | OpenShift Virtualization                          |
| ------------------- | ---------------------------------------------------- | ---------------------------------------- | ------------------------------------------------- |
| Everpure / Portworx | FlashArray via Portworx CSI or PX Enterprise         | iSCSI, FC, NVMe/TCP, NVMe/RDMA           | Yes, including VDI                                |
| Dell                | PowerMax, PowerStore, PowerFlex                      | FC, iSCSI, NVMe/TCP, NFS (varies)        | Yes via Container Storage Modules                 |
| NetApp              | AFF / FAS via Trident (certified operator)           | iSCSI, NVMe/TCP, NFS, SMB; FC tech preview | Yes, including VDI. Use SAN raw block or NAS for RWX live migration. |
| IBM                 | FlashSystem, SVC, Storage Virtualize, DS8000         | FC, iSCSI                                | Yes via IBM block storage CSI                     |
| HPE                 | Alletra / Primera / Nimble; XP8; GreenLake File      | FC, iSCSI, NFS, NVMe (XP8)               | Yes via HPE CSI operators                         |
| Hitachi Vantara     | VSP One Block; VSP One SDS                           | FC, iSCSI, NVMe-oF                       | Yes via Hitachi Storage Plug-in for Containers    |
| Infinidat           | InfiniBox                                            | FC, iSCSI, NFS                           | Yes                                               |
| Arctera             | Infoscale for Kubernetes                             | FC/SCSI on Hitachi, Pure, or VMware VMDK | Yes — shared-disk file system model               |

NetApp Trident’s SAN drivers do RWX in **raw block** mode. Filesystem mode
on those drivers is RWO. Live migration cares about that distinction more
than the brand on the array.

If you are migrating *from* VMware and the disks already sit on a SAN,
storage copy offload can matter more than which HCI you pick. See
[storage copy offload for VMware migrations](/posts/mtv-storage-copy-offload-vmware/).

## Looks local. Does not replace vSAN.

| Option                              | Why it is not the analog                                                                                          |
| ----------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| LVM Storage (LVMS / TopoLVM)        | Local RWO only. No cross-node replication. Live migration blocked.                                                |
| Local Storage Operator / hostPath   | Static local PVs. Same node affinity. Fine for a lab, not HA VMs.                                                 |
| StorMagic SvSAN                     | Two-node HCI aimed at vSphere/Hyper-V. CSI docs target Tanzu on VMware, not OVE.                                  |
| StarWind VSAN, Longhorn, OpenEBS    | May replicate local disks. Not on the Red Hat Virtualization compatibility article. You own live-migration proof. |
| Nutanix AHV as the hypervisor       | Different hypervisor. Nutanix CSI can attach storage to OpenShift in some designs. That is not OVE + Nutanix vSAN. |

## How I would choose on an OVE cluster

If the requirement is **local disks like vSAN**, shortlist Portworx
on local disks, Dell PowerFlex, LINBIT LINSTOR, or IBM Fusion HCI. Portworx
is the most common OpenShift Virtualization HCI path. PowerFlex fits Dell
SDS accounts. LINSTOR is the lightest certified replica of local NVMe.
Fusion is the IBM appliance/software path.

If a **SAN already exists**, use the vendor CSI. Do not add ODF “because
that is what the slide said.” ODF is still the right buy when you want
first-party Ceph, one stack for block/file/object, and Red Hat storage
support on the same ticket as the cluster. A PoC ODF install is in
[OpenShift Data Foundation (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/post-installation/storage/odf/);
array CSI examples start from
[Storage](https://openshift-ssa.github.io/openshift-poc/post-installation/storage/).

Starting with OpenShift 4.17, CSI certification includes the
kubevirt-storage-checkup suite. A driver can pass generic CSI tests and
still be a poor VM backend. Ask the vendor for RWX Block, snapshots,
clones, live migration, and the catalog badge for *your* OpenShift version—not
just an older release.

> Listings in this post are a snapshot, not a support statement. Re-check
> [KCS 7128992](https://access.redhat.com/articles/7128992) and the
> [Ecosystem Catalog](https://catalog.redhat.com/) before procurement.
{: .prompt-warning }

## Related posts

- [OpenShift Virtualization with Dell Unity over iSCSI](/posts/openshift-virt-dell-unity-iscsi/)
- [Pure FlashArray on Single-Node OpenShift with NVMe/TCP](/posts/pure-flasharray-sno-nvme-tcp/)
- [Storage Copy Offload for VMware to OpenShift Virtualization](/posts/mtv-storage-copy-offload-vmware/)
- [What's New in OpenShift Virtualization 4.22](/posts/openshift-virtualization-4-22-features/)

## Further reading

- [OpenShift Virtualization storage compatibility (KCS 7128992)](https://access.redhat.com/articles/7128992)
- [Storage considerations for OpenShift Virtualization (Red Hat Developer)](https://developers.redhat.com/articles/2025/07/10/storage-considerations-openshift-virtualization)
- [Self-managed OpenShift subscription guide](https://www.redhat.com/en/resources/self-managed-openshift-subscription-guide)
- [Red Hat Ecosystem Catalog](https://catalog.redhat.com/)
- [OpenShift PoC overview](https://openshift-ssa.github.io/openshift-poc/home/)
- [Storage (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/post-installation/storage/)
- [OpenShift Data Foundation (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/post-installation/storage/odf/)
- [Dell Unity XT (iSCSI) (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/post-installation/storage/dell/dell-unity/)
- [VMware vSphere CSI (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/post-installation/storage/vsphere-csi/)
- [OpenShift Virtualization (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/post-installation/virtualization/)

> Mapping this into a landing zone or a VMware-exit storage design? That is
> a conversation for your Red Hat account team—or prove RWX Block live
> migration on a non-prod OVE cluster before you standardize on a StorageClass.
{: .prompt-tip }
