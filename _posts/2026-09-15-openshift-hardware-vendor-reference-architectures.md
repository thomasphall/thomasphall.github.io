---
title: "OpenShift Hardware Vendor Reference Architectures"
description: >-
  How Dell, HPE, Lenovo, Cisco, IBM, and other hardware vendors publish
  OpenShift reference architectures—and how to use them as a starting
  BOM, not a design.
date: 2026-09-15 11:00:00 -0500
categories: [OpenShift]
tags: [openshift, bare-metal, storage, csi]
permalink: /posts/openshift-hardware-vendor-reference-architectures/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization. Vendor documents move and
> pin OpenShift versions that lag current GA. Confirm the PDF, CSI matrix,
> and certified hardware list for the release you will actually install.
{: .prompt-info }

Architecture reviews stall when someone drops a 90-page vendor PDF on the
table and treats the bill of materials (BOM) as the design. The PDF is useful.
It is not a form factor, a failure domain, or a SKU decision. Name those
first—see
[OpenShift edge architectures](/posts/openshift-edge-architectures/)
and
[OVE vs OpenShift Platform Plus](/posts/ove-vs-openshift-platform-plus/)—
then use a hardware vendor reference architecture (RA) to freeze servers,
NICs, disks, and the storage pairing that has already been labbed together.

This post is a solutions-architect map of **published OpenShift RAs from
hardware vendors** as of September 2026. It is a catalog and a reading guide,
not a support matrix and not an install runbook. The
[Red Hat Ecosystem Catalog](https://catalog.redhat.com/en/platform/red-hat-openshift)
is still the support floor: certified hardware and operators. An RA is an
*opinionated stack* on top of that floor.

## What “reference architecture” means in this conversation

Vendors use the same phrase for four different artifacts. Mix them up and you
buy an appliance when you needed a BOM, or a 4.12 design guide when the
account expected current
[Red Hat OpenShift Container Platform (OCP)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/).

```text
 Certified hardware          Validated / reference design         Appliance / private cloud
 (can I support this box?)   (how should we rack a cluster?)     (who owns day-2 firmware?)
┌─────────────────────────┐  ┌───────────────────────────────┐  ┌─────────────────────────┐
│ Ecosystem Catalog       │  │ Vendor RA / CVD / design      │  │ Dell Private Cloud,     │
│ Server + NIC + GPU IDs  │─▶│ guide, pinned OCP + CSI + BOM │─▶│ IBM Fusion HCI,         │
│ CSI operator certified  │  │ Often lag current GA by 1–3   │  │ HPE GreenLake wrap      │
└─────────────────────────┘  │ z-streams                     │  └─────────────────────────┘
                             └───────────────────────────────┘
```

| Artifact | What it proves | What it does not prove |
| -------- | -------------- | ---------------------- |
| **Certified hardware** | This server, NIC, GPU, or CSI driver is supported on a listed OpenShift version | That the BOM matches *your* etcd, VM, or GPU I/O |
| **Reference architecture / validated design** | Someone racked a full stack (compute + network + storage + OpenShift) and wrote the wiring | That the pinned OpenShift version is the one you will buy |
| **Cisco Validated Design (CVD)** | Cisco + partner (usually NetApp) tested a FlexPod tenant end to end | That UCS X-Series Direct is the only legal UCS shape |
| **Appliance / private cloud** | Vendor installer + lifecycle tooling keep firmware and OpenShift in a validated state | That you can casually swap the storage layer next quarter |
| **As-a-service wrap** | Metering, factory integration, single throat to choke | That the underlying RA disappeared—you still inherit its topology |

Read every RA for five things before you copy the SKU list:

1. **OpenShift version pin** — as of this writing the newest *published*
   vendor RAs are still behind current GA (4.22 on this site). HPE’s living
   set is 4.21; Dell’s OpenShift AI RA pins 4.21.9 while the general PowerEdge
   DVDs are 4.14; Cisco’s current FlexPod CVD is 4.20; Lenovo Press LP0968 is
   4.18; FlashStack’s OpenShift CVD is 4.18. Keep the *ratios* (control plane
   vs workers vs storage nodes, NIC speeds, boot vs data disks). Re-validate
   the z-stream and operators.
2. **Workload assumption** — general containers,
   [Red Hat OpenShift Virtualization](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/index),
   or [Red Hat OpenShift AI](https://www.redhat.com/en/technologies/cloud-computing/openshift/openshift-ai).
   An AI factory RA that assumes Spectrum-X and eight GPUs per node is the
   wrong PDF for a VM landing zone.
3. **Storage pairing** — Container Storage Interface (CSI) array,
   [Red Hat OpenShift Data Foundation (ODF)](https://docs.redhat.com/en/documentation/red_hat_openshift_data_foundation/),
   Portworx, or nested disks on HCI. Live migration needs ReadWriteMany
   (RWX) or a vendor equivalent you have actually tested.
4. **Install method** — Assisted Installer, user-provisioned, vendor wizard,
   or Ansible for the fabric only. The OpenShift piece should still match
   [how to get started with an OpenShift PoC](/posts/getting-started-openshift-poc/).
5. **Nested vs bare metal** — OpenShift as VMs on Nutanix AHV or KVM is a
   different failure domain from Red Hat Enterprise Linux CoreOS (RHCOS) on
   the iron. Say that out loud.

## Server OEMs: start here for a rack BOM

### Dell Technologies

Dell publishes the densest OpenShift paper trail. Treat it as three layers.

**Do-it-yourself on PowerEdge.** The current general Dell Validated Designs
are the OpenShift **4.14**
[Intel-powered](https://infohub.delltechnologies.com/en-us/l/design-guide-red-hat-openshift-container-platform-4-14-on-intel-powered-dell-infrastructure/physical-network-design-37/)
and
[AMD-powered](https://infohub.delltechnologies.com/en-us/l/design-guide-red-hat-openshift-container-platform-4-14-on-amd-powered-dell-infrastructure/physical-network-design-39/)
design guides (R660/R760 and R6625/R7625 class, CSAH/load-balancer nodes,
leaf-spine, Single Node OpenShift (SNO)). Older 4.12 siblings are still on
InfoHub; do not copy them as the current DVD. Use 4.14 for node roles and
NIC redundancy, not as a version pin.

**Validated platform / PowerFlex.** The
[Dell Validated Platform for Red Hat OpenShift](https://infohub.delltechnologies.com/en-ca/p/accelerate-devops-and-cloud-native-apps-with-the-dell-validated-platform-for-red-hat-openshift/)
pairs OpenShift with PowerFlex in a two-tier (compute vs storage) layout so
you scale those axes independently. PowerFlex Manager can sit in OpenShift
Virtualization to shrink the management footprint. This is the RA to open
when the account already standardized on PowerFlex SDS.

**Private cloud / APEX lineage.**
[Dell Private Cloud](https://www.dell.com/en-us/shop/private-cloud/sf/private-cloud)
deploying OpenShift (Automation Platform blueprints) is the current packaging
for an appliance-like lifecycle on disaggregated PowerEdge plus Dell storage.
Older InfoHub papers still say
[APEX Cloud Platform for Red Hat OpenShift](https://infohub.delltechnologies.com/en-us/l/dell-apex-cloud-platform-for-red-hat-openshift-deployment-and-performance/overview-6935/):
bare-metal compute, separate PowerFlex storage nodes, wizard install, CSI
from the compute layer. Storage options on that lineage expanded from
PowerFlex-only to PowerStore and ODF for a smaller footprint. Confirm which
name and storage SKU the quote actually is.

**AI.** Dell has a current
[OpenShift AI RA on PowerEdge R770/R570 with Xeon 6](https://infohub.delltechnologies.com/en-us/p/red-hat-openshift-ai-on-dell-poweredge-r770-and-r570-with-xeon-6/)
(documented against OpenShift 4.21.9 plus ODF, with optional NVIDIA GPU
Operator) and a
[Dell AI Factory with NVIDIA and OpenShift AI](https://infohub.delltechnologies.com/en-sg/l/dell-ai-factory-with-nvidia-and-red-hat-openshift-ai/reference-architecture-159/)
design for GPU-heavy RAG and inference. CPU-first Xeon 6 is a different
conversation from eight-GPU Blackwell nodes—do not let the word “AI”
collapse them.

Existing array CSI on this site:
[Dell Unity over iSCSI](/posts/openshift-virt-dell-unity-iscsi/).

### HPE

HPE’s current RA is
[OpenShift 4.21 on ProLiant Intel Gen12](https://hewlettpackard.github.io/hpe-solutions-openshift/4.21-INTEL-LTI/)
(and the matching AMD Gen11 set) on
[hewlettpackard.github.io/hpe-solutions-openshift](https://hewlettpackard.github.io/hpe-solutions-openshift/).
That is the document to hand an HPE-standardized account: DL320/DL360/DL380
Gen12, KVM-hosted control plane VMs on RHEL 9.6 head nodes, bare-metal
RHCOS workers, iSCSI to
[HPE Alletra Storage MP](https://scod.hpedev.io/csi_driver/partners/redhat_openshift/index.html)
via the HPE CSI Driver (Alletra 6000/9000, Alletra Storage MP, Nimble,
Primera), optional ODF. Older 4.18/4.20 trees and the Gen11 4.12 reference
configuration are still published; they are not the current validation.

HPE GreenLake for OpenShift was the as-a-service wrap around those validated
integrated systems. Treat current quotes as GreenLake service descriptions
plus the 4.21 GitHub solution set—not a third architecture.

### Lenovo

Lenovo Press
[LP0968](https://lenovopress.lenovo.com/lp0968-red-hat-openshift-container-platform-reference-architecture)
(updated 3 Oct 2025) is still the full RA: OpenShift **4.18** on ThinkSystem,
ThinkEdge, and ThinkAgile HX, including edge topologies from single-node
through three-node. For a virt landing zone, the newer
[Modern Virtualization with OpenShift on ThinkSystem](https://lenovopress.lenovo.com/lp2432-modern-virtualization-with-red-hat-openshift-on-lenovo-thinksystem)
brief (20 May 2026) is the current BOM: SR630/SR650 V4 and SR635/SR655/SR665
V3, ThinkSystem DM5200F, Lenovo Trident CSI. Companion
[deployment-ready solutions](https://lenovopress.lenovo.com/lp1671-red-hat-openshift-deployment-ready-solutions-on-lenovo-servers)
document a 3-node compact cluster and an HCI path.

Two Lenovo shapes, two designs:

- **ThinkSystem / ThinkEdge, preferably bare metal**, with ThinkSystem DM
  series (NetApp ONTAP OEM) via Trident CSI when you want an array. LP2432
  pins DM5200F.
- **ThinkAgile HX** — Nutanix HCI + AHV, OpenShift as virtual machines,
  Nutanix CSI. Nested control planes, Nutanix failure domains. Lenovo Open
  Cloud Automation (LOCA) shows up as the factory/deploy tool.

Do not copy an HX BOM into a bare-metal RHCOS design or the reverse.

### Supermicro

Supermicro’s current OpenShift page is the
[AI-ready infrastructure](https://www.supermicro.com/en/solutions/red-hat-openshift)
story: NVIDIA GPU servers with OpenShift AI, plus a
[NVIDIA AI Enterprise on OpenShift](https://www.supermicro.com/solutions/Solution-Brief_SMCI-AMD-NVIDIA-RedHat-AIEnterprise.pdf)
reference architecture (small/medium/large GPU worker kits). The older
OpenShift Ready 3-node-through-42U ODF rack SKUs are still listed as starting
kits on that family of pages.

For two-node HA without a SAN, the current brief is
[Supermicro + OpenShift 4.20 TNA + Portworx](https://www.supermicro.com/solutions/Solution_Brief_Portworx_by_Everpure_Red_Hat_OpenShift.pdf)
(two data nodes plus a lightweight arbiter, Portworx synchronous replication).
Pair that with
[OpenShift Edge Architectures: Form Factor, Then Fleet](/posts/openshift-edge-architectures/)
so the arbiter’s job is etcd quorum, not “a third hypervisor we pretended
was cheap.”

### Fujitsu / Fsas Technologies

Fsas documents
[trusted configurations for OpenShift Virtualization on PRIMERGY](https://docs.ts.fujitsu.com/dl.aspx?id=e052a415-a74f-4449-a96c-c89f80715197):
a 3-node HCI with ODF Essentials, and a 6-node split (three control plane,
three workers) with a NetApp array and CSI. This is a services-backed BOM
more than a 100-page design guide. Use it when the account is already a
PRIMERGY shop and wants a compact virt landing zone.

## Converged stacks: compute, fabric, and array as one RA

### Cisco and NetApp (FlexPod)

FlexPod is the longest-running *joint* hardware RA: UCS + Nexus + NetApp
ONTAP. The document Cisco lists first on the
[FlexPod design guides](https://www.cisco.com/c/en/us/solutions/design-zone/data-center-design-guides/flexpod-design-guides.html)
index (as of this writing) is the current CVD:

- [FlexPod Datacenter with OpenShift 4.20, Intel CPUs, FC boot](https://www.cisco.com/c/en/us/td/docs/unified_computing/ucs/UCS_CVDs/flexpod_rh_ocp_bm_fc_boot_intel.html)
  — UCS X210c M8 / C240 M8, Fabric Interconnect 6664, NetApp AFF A90
  (ONTAP 9.18.1), Trident 26.02.1, optional NVIDIA H200 NVL / L40S / RTX PRO
  GPUs on the X580p PCIe node

Still published for the X-Series Direct (M7, M.2 boot, OpenShift 4.17) path:

- [IaC configuration](https://www.cisco.com/c/en/us/td/docs/unified_computing/ucs/UCS_CVDs/flexpod_rh_openshift_bm_iac_deploy.html)
- [Manual configuration](https://www.cisco.com/c/en/us/td/docs/unified_computing/ucs/UCS_CVDs/flexpod_rh_ocp_bm_xseries_manual.html)
- [FlexPod with OpenShift Virtualization](https://www.cisco.com/c/en/us/td/docs/unified_computing/ucs/UCS_CVDs/flexpod_openshift_virtual.html)
  layered on that tenant

Do not treat the 4.17 X-Direct CVD as the current M8 / 4.20 validation.

### Cisco and Pure (FlashStack)

When the array is Pure rather than NetApp, the current Cisco CVD is
[FlashStack with OpenShift containerization and virtualization](https://www.cisco.com/c/en/us/td/docs/unified_computing/ucs/UCS_CVDs/flashstack_ocp_baremetal_ucs_amd_imm.html)
(OpenShift 4.18.26 on UCS AMD M8, FlashArray + FlashBlade, Portworx
Enterprise, FC and Ethernet). That is a different stack from FlexPod—do not
mix ONTAP Trident BOMs into a FlashArray quote.

### IBM Power, Fusion, and FlashSystem

IBM is both a server vendor and a storage vendor in this list.

- **IBM Power** is a first-class
  [OpenShift install target](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/installing_on_ibm_power/index)
  (and IBM Z / LinuxONE is another). ODF on Power is a documented
  [internal and external path](https://docs.redhat.com/en/documentation/red_hat_openshift_data_foundation/).
  Use Power when the workload already lives in PowerVM LPARs or when the
  account wants that ISA—not as a surprise swap for x86 RAs.
- **IBM Fusion** software is currently **2.12**
  ([readme](https://www.ibm.com/support/pages/readme-ibm-fusion-2120),
  [docs](https://www.ibm.com/docs/en/fusion-software/2.12.0)). That operator
  (backup/restore, Fusion Data Foundation, Scale, cataloging) is the RA to
  open on an existing OpenShift cluster. The older Redpaper REDP-5688 covers
  Fusion 2.5.x—do not quote it as current.
- **Fusion HCI System** is the appliance. Current architecture reading is
  [IBM Fusion HCI as a Catalyst (SG24-8600, Oct 2025)](https://www.redbooks.ibm.com/abstracts/sg248600.html)
  plus the
  [Fusion HCI product docs](https://www.ibm.com/docs/en/fusion-hci-systems).
- **Fusion Access for SAN** (in the 2.12 line) is the OpenShift
  Virtualization + Fibre Channel or iSCSI shared-disk story for shops that
  already own a SAN and do not want Ceph as the VM disk plane.

FlashSystem CSI remains the array path when Fusion HCI is too much appliance.

## Storage specialists (when the array is the RA)

These vendors do not always publish a full server BOM. They publish the
storage half that every server OEM above eventually plugs into.

| Vendor | What to open | OpenShift role |
| ------ | ------------ | -------------- |
| **Pure Storage** | [Portworx on OpenShift Bare Metal RA](https://portworx.com/wp-content/uploads/2024/09/ra-portworx-red-hat-openshift-bare-metal.pdf) plus the [Virtualization addendum](https://portworx.com/wp-content/uploads/2024/12/ra-openshift-virtualization-addendum.pdf) (Portworx 3.6 / OpenShift 4.20); FlashArray CSI; complete rack via [FlashStack CVD](https://www.cisco.com/c/en/us/td/docs/unified_computing/ucs/UCS_CVDs/flashstack_ocp_baremetal_ucs_amd_imm.html) | Array-backed PVCs, Portworx SDS, or FlashStack. Lab pattern: [Pure FlashArray on SNO with NVMe/TCP](/posts/pure-flasharray-sno-nvme-tcp/) |
| **NetApp** | Trident + ONTAP; complete rack via the FlexPod 4.20 CVD above | NFS/iSCSI/NVMe-TCP/FC, snapshots, SVM tenancy |
| **HPE Alletra** | [HPE CSI on OpenShift](https://scod.hpedev.io/csi_driver/partners/redhat_openshift/index.html) (4.21 field-tested) | Block (and some file) from Alletra / Nimble / Primera |
| **Dell PowerStore / Unity / PowerFlex** | Dell CSM / CSI; [OpenShift 4.16 + PowerStore](https://infohub.delltechnologies.com/en-sg/l/red-hat-openshift-4-16-and-mongodb-deployment-on-dell-powerstore-3/appendix-a-hardware-and-software-configuration-4/) workload paper | Unity iSCSI on this site; PowerFlex in the validated platform |
| **Hitachi Vantara** | Newest: [iQ + Hammerspace + OpenShift AI 3](https://docs.hitachivantara.com/api/khub/documents/8cx3yyHp90LIPbpJz5ozTw/content). Also [UCP/VSP One + NVIDIA](https://www.hitachivantara.com/content/dam/hvac/pdfs/architecture-guide/accelerate-your-ai-journey-with-red-hat-ai-and-nvidia.pdf) | HSPC CSI, Hammerspace NAS, VSP One |
| **IBM FlashSystem / Scale** | Fusion 2.12 CSI / Fusion Access for SAN | Existing IBM storage estates |

Array CSI is the right RA *fragment* when the servers are already chosen and
the fight is RWX, snapshots, and what fails when a path drops—not when nobody
has named the form factor yet. Disk types and IOPS still follow
[OpenShift storage performance](/posts/openshift-storage-performance/).

## GPU and AI factory RAs

NVIDIA does not sell the complete rack as an OpenShift SKU. It publishes
**Enterprise / RTX PRO AI Factory** reference architectures
([components](https://docs.nvidia.com/enterprise-reference-architectures/rtx-pro-ai-factory/latest/components.html))
and a co-engineered
[Red Hat AI Factory with NVIDIA deployment guide](https://docs.nvidia.com/ai-enterprise/deployment/red-hat-ai-factory/latest/prerequisites.html)
(OpenShift + OpenShift AI, GPU / Network / NIM Operators, NVIDIA-Certified
Systems, Spectrum-X or Quantum InfiniBand). Partners ship the iron: Dell AI
Factory, Hitachi iQ, Supermicro GPU kits, FlexPod M8 with an X580p PCIe node,
and OEM RTX PRO servers in 2/4/8 GPU configurations.

Use an AI factory RA when the constraint is GPU interconnect, NIM serving, and
operator lifecycle. Use a Xeon-first OpenShift AI RA (Dell R770/R570) when the
constraint is “inference without a Blackwell PO.” Do not size VM landing-zone
control planes from either PDF.

## Catalog (hardware-complete RAs)

| Vendor | Newest published RA | Typical shape | Storage in the RA | Open when |
| ------ | ------------------- | ------------- | ----------------- | --------- |
| Dell | PowerEdge DVD **4.14** (Intel/AMD); Private Cloud; OpenShift AI on R770/R570 (**4.21.9**); AI Factory + NVIDIA | 3-node compact through two-tier compute/storage; SNO in the DVD | PowerFlex, PowerStore, ODF, Unity CSI | PowerEdge or PowerFlex is already the standard |
| HPE | GitHub **4.21** ProLiant Intel Gen12 / AMD Gen11 | DL320/DL360/DL380, KVM control plane + BM workers | Alletra Storage MP CSI; optional ODF | ProLiant + Alletra estate |
| Lenovo | LP0968 (**4.18**, Oct 2025); LP2432 virt brief (May 2026) | ThinkSystem/ThinkEdge BM or ThinkAgile HX nested | DM5200F + Trident, or Nutanix CSI | Lenovo-standardized DC or edge |
| Cisco + NetApp | FlexPod OpenShift **4.20** FC-boot Intel M8; X-Direct **4.17** still listed | UCS X210c/C240 M8 tenant | ONTAP AFF A90, Trident, FC/NFS/iSCSI | Converged UCS + NetApp |
| Cisco + Pure | FlashStack OpenShift **4.18.26** AMD M8 | UCS AMD M8 + FlashArray/FlashBlade | Portworx + Pure | Converged UCS + Pure |
| IBM | Fusion **2.12**; Fusion HCI SG24-8600 (Oct 2025); installing on Power | Power LPARs, Fusion HCI appliance, or x86 + SAN | Fusion DF / Scale / SAN | Power, Fusion, or IBM storage |
| Supermicro | AI Factory + NVIDIA AI Enterprise RA; TNA + Portworx **4.20** | GPU kits, or 2+arbiter | ODF in older kits; Portworx on TNA | GPU rack or two-node HA |
| Fujitsu / Fsas | PRIMERGY virt trusted configs | 3-node ODF HCI or 6-node + NetApp | ODF or NetApp CSI | PRIMERGY virt landing zone |
| NVIDIA + OEMs | AI Factory / RTX PRO RA; Red Hat AI Factory guide | GPU servers 2/4/8, Spectrum-X | NVIDIA-certified storage / S3 | Agentic/inference factory |
| Hitachi | iQ + Hammerspace + OpenShift AI 3; UCP/VSP One + NVIDIA | GPU compute + VSP One | HSPC CSI, Hammerspace NAS | Hitachi compute/storage + AI |

## Decision guide

| Constraint | Lean toward |
| ---------- | ----------- |
| Servers already chosen; only storage is open | That vendor’s CSI matrix + an array RA fragment—not a new server OEM RA |
| Want one PO and vendor lifecycle for firmware + OpenShift | Dell Private Cloud / APEX lineage, IBM Fusion HCI, HPE integrated system |
| UCS + NetApp already in the DC | FlexPod OpenShift **4.20** CVD (M8); X-Direct 4.17 only if that is the iron you own |
| UCS + Pure already in the DC | FlashStack OpenShift CVD—not FlexPod |
| Nested OpenShift on Nutanix is acceptable | Lenovo ThinkAgile HX RA—do not pretend it is bare metal |
| Two hypervisor-class boxes, site HA, no SAN | Supermicro TNA + Portworx, or two-node + shared CSI you actually have |
| Edge SNO / compact, Lenovo or Dell already on the floor | LP0968 edge chapter or Dell design-guide SNO—not an AI factory PDF |
| GPU interconnect and NIM are the product | NVIDIA AI Factory + OEM certified servers |
| CPU-only or hybrid inference, Dell account | OpenShift AI on R770/R570 Xeon 6 |
| IBM Power estate | Installing on Power + Fusion/ODF, not an x86 ProLiant BOM |
| Live migration of VMs | RA whose storage row is RWX CSI or SDS—not host-local LVMS alone |

A useful facilitation line: *“Is this PDF certifying a server, recommending a
rack, or selling an appliance?”* If the room cannot answer, you are not ready
to order.

## The solutions architect takeaway

1. **Certified ≠ designed** — the Ecosystem Catalog says the box is
   supportable. The RA says someone wired a cluster. Your design still names
   form factor, failure domain, and SKU.
2. **Version pins lag** — steal NIC counts, disk roles, and two-tier vs
   hyperconverged ratios. Re-validate OpenShift 4.22 (or whatever you buy)
   and the CSI operator.
3. **Workload selects the PDF** — virt CVDs, AI factories, and general
   container design guides are not interchangeable cover sheets.
4. **Storage is the usual trap** — nested HCI, ODF, Portworx, and array CSI
   are different products with different blast radii. Match them to
   [storage performance](/posts/openshift-storage-performance/)
   and the edge storage chooser, not to the logo on the RA cover.
5. **Appliances trade flexibility for lifecycle** — that is a valid buy when
   firmware drift is the risk. It is a bad surprise when the next project
   needs a different array.

Start the next hardware conversation with constraints, then pick the vendor
document that already labbed that shape. Do not start with the thickest PDF.

## Related posts

- [How to Get Started with an OpenShift PoC](/posts/getting-started-openshift-poc/)
- [What's New in Red Hat OpenShift AI 3.5](/posts/openshift-ai-3-5-features/)
- [OpenShift Edge Architectures: Form Factor, Then Fleet](/posts/openshift-edge-architectures/)
- [OpenShift Storage Performance: Disks, IOPS, Architectures](/posts/openshift-storage-performance/)
- [OVE vs OpenShift Platform Plus: The SKU Choice](/posts/ove-vs-openshift-platform-plus/)

> Want help mapping a vendor RA onto an actual landing zone? Reach out to
> your Red Hat account team—and the hardware vendor’s OpenShift practice—
> before you freeze a BOM from a PDF that pins last year’s z-stream.
{: .prompt-tip }

## Further reading

- [Red Hat OpenShift ecosystem (certified hardware)](https://catalog.redhat.com/en/platform/red-hat-openshift)
- [Installing on bare metal (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/installing_on_bare_metal/index)
- [Installing on IBM Power (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/installing_on_ibm_power/index)
- [Dell OpenShift AI on PowerEdge R770/R570 (Xeon 6)](https://infohub.delltechnologies.com/en-us/p/red-hat-openshift-ai-on-dell-poweredge-r770-and-r570-with-xeon-6/)
- [Dell OpenShift 4.14 DVD (Intel)](https://infohub.delltechnologies.com/en-us/l/design-guide-red-hat-openshift-container-platform-4-14-on-intel-powered-dell-infrastructure/physical-network-design-37/)
- [Dell OpenShift 4.14 DVD (AMD)](https://infohub.delltechnologies.com/en-us/l/design-guide-red-hat-openshift-container-platform-4-14-on-amd-powered-dell-infrastructure/physical-network-design-39/)
- [Dell Private Cloud](https://www.dell.com/en-us/shop/private-cloud/sf/private-cloud)
- [HPE OpenShift 4.21 on ProLiant Intel Gen12](https://hewlettpackard.github.io/hpe-solutions-openshift/4.21-INTEL-LTI/)
- [HPE CSI Driver for OpenShift](https://scod.hpedev.io/csi_driver/partners/redhat_openshift/index.html)
- [Lenovo LP0968 OpenShift RA (4.18)](https://lenovopress.lenovo.com/lp0968-red-hat-openshift-container-platform-reference-architecture)
- [Lenovo LP2432 OpenShift Virtualization on ThinkSystem](https://lenovopress.lenovo.com/lp2432-modern-virtualization-with-red-hat-openshift-on-lenovo-thinksystem)
- [FlexPod OpenShift 4.20 FC-boot Intel M8](https://www.cisco.com/c/en/us/td/docs/unified_computing/ucs/UCS_CVDs/flexpod_rh_ocp_bm_fc_boot_intel.html)
- [FlashStack OpenShift CVD (UCS AMD M8 + Pure)](https://www.cisco.com/c/en/us/td/docs/unified_computing/ucs/UCS_CVDs/flashstack_ocp_baremetal_ucs_amd_imm.html)
- [IBM Fusion 2.12.0 readme](https://www.ibm.com/support/pages/readme-ibm-fusion-2120)
- [IBM Fusion HCI as a Catalyst (SG24-8600)](https://www.redbooks.ibm.com/abstracts/sg248600.html)
- [Supermicro OpenShift / AI-ready solutions](https://www.supermicro.com/en/solutions/red-hat-openshift)
- [Portworx on OpenShift Bare Metal RA](https://portworx.com/wp-content/uploads/2024/09/ra-portworx-red-hat-openshift-bare-metal.pdf)
- [NVIDIA Red Hat AI Factory deployment guide](https://docs.nvidia.com/ai-enterprise/deployment/red-hat-ai-factory/latest/prerequisites.html)
- [NVIDIA RTX PRO AI Factory components](https://docs.nvidia.com/enterprise-reference-architectures/rtx-pro-ai-factory/latest/components.html)
- [Hitachi iQ + Hammerspace + OpenShift AI 3](https://docs.hitachivantara.com/api/khub/documents/8cx3yyHp90LIPbpJz5ozTw/content)
- [Hitachi OpenShift AI + NVIDIA RA](https://www.hitachivantara.com/content/dam/hvac/pdfs/architecture-guide/accelerate-your-ai-journey-with-red-hat-ai-and-nvidia.pdf)
- [OpenShift PoC overview](https://openshift-ssa.github.io/openshift-poc/home/)
- [Storage (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/post-installation/storage/)
