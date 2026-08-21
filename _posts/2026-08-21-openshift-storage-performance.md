---
title: "OpenShift Storage Performance: Disks, IOPS, Architectures"
description: >-
  Disk types, IOPS, and throughput OpenShift needs for etcd, ODF, and CSI
  on bare metal, vSphere, AWS, Azure, and IBM Cloud—and which setups fail
  in production.
date: 2026-08-21 13:30:00 -0500
categories: [OpenShift]
tags: [openshift, storage, csi, bare-metal, rosa]
og_image: /assets/img/og/openshift-storage-performance.png
permalink: /posts/openshift-storage-performance/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization.
{: .prompt-info }

OpenShift storage reviews fail when someone quotes one IOPS number and applies
it to every disk in the rack. etcd, container image layers, OpenShift Data
Foundation (ODF) OSDs, and VM disks are four different I/O problems. A 7200 RPM
HDD that is fine for a file archive will elect a new etcd leader. An AWS `gp3`
volume that is fine for a worker root disk is undersized for a busy control
plane on Azure, where IOPS still tracks disk size.

This post is a solution-architect map of **disk types, architectures, IOPS, and
throughput** for OpenShift Container Platform 4.22. It is not a support matrix
and it is not an `fio` runbook. Confirm the
[recommended etcd practices](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/etcd/etcd-practices),
[optimizing storage](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/scalability_and_performance/scalability-and-performance-optimization),
and
[ODF infrastructure requirements](https://docs.redhat.com/en/documentation/red_hat_openshift_data_foundation/4.21/html/planning_your_deployment/infrastructure-requirements_rhodf)
for the version you will actually install.

## Three planes, three answers

Treat storage as three planes. Mixing them is how compact clusters and nested
labs look healthy until the first etcd WAL stall.

| Plane                         | What lives there                                      | What it cares about                         | Typical media                                      |
| ----------------------------- | ----------------------------------------------------- | ------------------------------------------- | -------------------------------------------------- |
| Control plane / etcd          | `/var/lib/etcd` on the OS disk (or a dedicated disk)  | fsync latency, not raw sequential GB/s      | Local NVMe or enterprise SSD                       |
| Node ephemeral                | `/var/lib/containers`, `/var/lib/kubelet`, `/var/log` | Capacity + decent write throughput          | Same SSD/NVMe as the OS; size it, do not NFS it    |
| Persistent CSI                | PVCs for apps, VMs, Prometheus, Loki, registry        | Access mode, consistency, IOPS at the array | Certified CSI: local SDS, SAN, or cloud block/file |

Installer minimums for a high-availability cluster are **100 GB** and **300
IOPS** per machine (120 GB on Single Node OpenShift). That is a capacity floor
and a coarse IOPS floor. etcd is stricter: it is a latency SLA. On many clouds
you over-allocate **size** to buy **IOPS**, because the two still scale
together.

Node directories from the
[optimizing storage](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/scalability_and_performance/scalability-and-performance-optimization)
guide:

| Path                   | Role                                      | Sizing cue                                              |
| ---------------------- | ----------------------------------------- | ------------------------------------------------------- |
| `/var/lib/etcd`        | etcd WAL and backend                      | Usually under 20 GB; DB can grow toward 8 GB            |
| `/var/lib/containers`  | CRI-O images and running containers       | ~50 GB at 16 GB RAM; add 20–25 GB per extra 8 GB RAM    |
| `/var/lib/kubelet`     | Ephemeral volumes, secrets, emptyDir      | Small if apps use PVs; unbounded if they do not         |
| `/var/log`             | Platform and kubelet logs                 | 10–30 GB; grow the disk or rotate                       |

Keep etcd on local flash. CSI is day-2. That split is the same advice as
[getting started with an OpenShift PoC](/posts/getting-started-openshift-poc/):
install does not need a StorageClass; persistent workloads do.

## What etcd actually requires

etcd is not I/O hungry. It is I/O **intolerant**. Raft persists every proposal
to the WAL with `fdatasync`. Slow disks, noisy neighbors, RAID write penalties,
and network-attached LUNs show up as leader elections and API timeouts, not as
a neat “disk full” event.

Official OpenShift 4.22 bar:

| Cluster load        | Sequential 8 KB writes including `fdatasync` | Latency target |
| ------------------- | -------------------------------------------- | -------------- |
| Standard            | At least **50 IOPS**                         | Under **10 ms** |
| Heavily loaded      | **500 IOPS**                                 | Under **2 ms**  |
| Validation          | 99th percentile fsync                        | Under **10 ms** |
| Network (Raft RTT)  | Peer round trip                              | Under **50 ms** |

Media rules from the same document, in one line: **SSD is the minimum, NVMe is
the production preference, dedicated local block, no NAS, no spinning rust, no
iSCSI, no Ceph RBD under etcd.** SLC enterprise SSD is called out for
write-intensive durability. Consumer QLC “NVMe” with ugly p99 write latency
fails this test even when the spec sheet looks fast.

Red Hat does **not** recommend RAID in front of etcd. RAID-5/6 is the usual
failure: every 8 KB WAL write pays a read-modify-write tax. If the hardware
story is “we always RAID,” RAID-1 of two NVMe devices is the least-bad variant,
and you still run `fio` / `etcd-perf` against `/var/lib/etcd`. Do not share that
disk with OSDs, container image caches, or application logs.

Validate before you argue with the storage team:

```shell
sudo podman run --volume /var/lib/etcd:/var/lib/etcd:Z quay.io/cloud-bulldozer/etcd-perf
```

Watch `etcd_disk_wal_fsync_duration_seconds` (p99) and
`etcd_server_leader_changes_seen_total` after install. If WAL fsync sits above
10 ms, the control plane is already in trouble.

## Disk types: order-of-magnitude, not a vendor quote

Numbers below are **typical ranges** so you can throw out the wrong media in a
design review. Array cache, queue depth, and the hypervisor will move them.
They will not turn a 7200 RPM HDD into an etcd disk.

| Media                         | Random IOPS (4K, ballpark) | Sequential throughput      | Typical latency     | etcd                         | ODF internal OSDs              | VM / DB CSI                    |
| ----------------------------- | -------------------------- | -------------------------- | ------------------- | ---------------------------- | ------------------------------ | ------------------------------ |
| HDD 7200 RPM                  | 100–200                    | 150–200 MB/s               | 5–10 ms             | **Does not work**            | **Not** the internal-mode disk | Archive only, not virt HA      |
| SATA SSD (enterprise)         | tens of thousands          | ~500 MB/s                  | ~100 µs             | Lab / small cluster          | Supported (SSD class)          | OK if the CSI is virt-capable  |
| SAS SSD                       | tens of thousands          | ~500–1200 MB/s             | ~100 µs             | Production minimum           | Supported                      | Yes                            |
| NVMe (enterprise TLC)         | hundreds of thousands+     | 2–7 GB/s                   | tens of µs          | **Preferred**                | **Preferred**                  | **Preferred**                  |
| Consumer QLC / DRAM-less NVMe | high peak, ugly p99        | high sequential            | unstable tail       | **Does not work**            | Avoid                          | Avoid                          |
| RAID-5/6 over HDD or SSD      | write penalty              | OK sequential              | spikes on fsync     | **Does not work**            | Avoid for WAL-like writes      | Avoid for databases            |
| USB / SD / “boot from SAN”    | whatever the dongle is     | whatever the dongle is     | high and noisy      | **Does not work**            | **Does not work**              | Lab toy                        |

Throughput matters for image pulls, live migration, ODF recovery, and
compaction. **IOPS and fsync latency** decide whether the API server stays up.
Do not size etcd from a sequential GB/s slide.

ODF internal mode on bare metal, IBM Power, IBM Z, and “any platform” wants
**local SSD** (NVMe, SATA, SAS, or a SAN LUN presented as a local SSD) via the
Local Storage Operator. Production devices start at **0.5 TiB**. Local devices
can be up to **16 TiB**, same **size and type** in a device set. Partitioning
is not supported except DASD on IBM Z. HDD capacity belongs in **external**
Red Hat Ceph Storage if you truly need cheap bulk—not as the default internal
ODF install.

## Architecture matrix: what works, what does not

### Bare metal

| Disk / path                         | Control plane / etcd        | Workers / CSI / ODF                                      |
| ----------------------------------- | --------------------------- | -------------------------------------------------------- |
| Local NVMe, dedicated from OS       | **Works.** Preferred.       | Preferred for ODF OSDs and VM SDS                        |
| Local enterprise SAS/SATA SSD       | Works if `etcd-perf` passes | Works for ODF and general CSI                            |
| Local HDD                           | **Does not work**           | Not for internal ODF; maybe cold app data on a SAN later |
| FC/iSCSI LUN for etcd               | **Does not work** (latency) | Fine for *workload* CSI                                  |
| NFS / NAS for etcd or Prometheus    | **Does not work**           | NFS for some RWX apps; not for Elasticsearch or Loki PV  |
| ODF on the etcd disk                | **Does not work**           | Separate OSD disks; OS disk stays OS                     |
| Compact 3-node (masters=workers)    | Works on NVMe               | ODF on **additional** SSDs, not `/var`                   |

Storage nodes should have at least two disks: one OS, the rest for ODF. Plan
**10 GbE** as the floor for Ceph replication; **25 GbE+** once OSDs are NVMe or
the fabric becomes the bottleneck. Jumbo frames must be end-to-end or they
fail after the cluster looks healthy.

### VMware vSphere

| Disk / path                         | Control plane / etcd                         | Persistent CSI                                      |
| ----------------------------------- | -------------------------------------------- | --------------------------------------------------- |
| All-flash vSAN or SSD VMFS          | Works if p99 fsync stays under 10 ms         | vSphere CSI for RWO; ODF or array CSI for RWX       |
| Hybrid vSAN (flash cache, HDD cap.) | etcd VMDKs need a **flash** SPBM policy      | HDD capacity is for cold data, not etcd             |
| NFS datastore for etcd              | **Does not work**                            | Possible for some app RWX; not core services        |
| Thin + contended datastore          | Often fails under load                       | Snapshot storms and noisy neighbors hurt VMs        |
| Nested ESXi / nested OpenShift      | Usually **fails** etcd-perf                  | Lab only; extra hypervisor latency is real          |
| PCI passthrough NVMe into the VM    | Works at scale (docs call this out)          | Use when the VMDK path cannot make fsync            |

Mark flash devices as flash in ESXi before ODF, or Ceph will treat SSD as HDD.
Do not put a second replication layer (ODF) on a SAN that already has a working
RWX CSI—that argument is in
[vSAN-like storage for OVE](/posts/ove-vsan-storage-alternatives/).

### AWS and Red Hat OpenShift Service on AWS (ROSA)

| Volume                              | IOPS / throughput (typical)                         | etcd / control plane                         | Workloads                                      |
| ----------------------------------- | --------------------------------------------------- | -------------------------------------------- | ---------------------------------------------- |
| `gp3`                               | Baseline **3,000 IOPS / 125 MiB/s**; raise both     | Default that scale tests use; raise for load | Default StorageClass (`gp3-csi`)               |
| `gp2`                               | Burst credits; IOPS tied to size                    | Risky once burst is gone                     | Avoid as the default                           |
| `io1` / `io2`                       | Provisioned IOPS (io2 up to 64k; Block Express more)| Heavy clusters, predictable latency          | Databases that need a latency SLA              |
| `st1` / `sc1`                       | Throughput HDD                                      | **Does not work**                            | Sequential bulk only                           |
| Instance-store NVMe                 | Fast and local                                      | Lost on stop/terminate                       | ODF only with a design that accepts that       |

OpenShift scalability testing documents control-plane `gp3` at the **3,000 IOPS
/ 125 MiB/s** baseline because etcd is latency-sensitive and `gp3` does not
rely on burst. ROSA with hosted control planes puts etcd in the AWS-managed
control plane; workers default to **300 GiB `gp3`**. ODF on AWS wants
`gp3-csi`; high IOPS instance families in the ODF planning guide are **D2 or
D3**.

### Microsoft Azure and Azure Red Hat OpenShift (ARO)

Azure is the architecture where **disk size buys IOPS**. That is why a 128 GiB
Premium SSD that looks “plenty for etcd” is slow.

| Disk                                | Performance cue                                          | Control plane                                      | Notes                                          |
| ----------------------------------- | -------------------------------------------------------- | -------------------------------------------------- | ---------------------------------------------- |
| Standard HDD                        | ~500 IOPS class                                          | **Does not work**                                  | Do not use                                     |
| Standard SSD                        | Modest IOPS, size-linked                                 | Lab at best                                        | Workers maybe; not production etcd             |
| Premium SSD **P30** (1 TiB)         | **5,000 IOPS / 200 MBps**                                | **Production minimum** in the optimizing-storage doc | Host cache **ReadOnly**                    |
| Premium SSD v2 / Ultra Disk         | IOPS and throughput provisioned separately               | Works when the VM series can consume it            | Prefer this over huge P30 just to buy IOPS     |
| Azure Files Standard                | Share-level caps                                         | **Does not work** for etcd                         | Not for Prometheus                             |

Red Hat’s production Azure guidance is explicit: control-plane OS disks should
sustain **5,000 IOPS / 200 MBps**, which a **P30** can do, and a
`Standard_D8s_v3`-class VM needs at least that P30 to hit the IOPS the VM
itself can drive. ODF on Azure can use **performance plus** on Premium or
Standard SSDs **513 GiB and larger** (`enablePerformancePlus=True`).

### Google Cloud

| Disk                     | Control plane / etcd     | Workloads                          |
| ------------------------ | ------------------------ | ---------------------------------- |
| `pd-standard`            | **Does not work** (HDD)  | Cold data                          |
| `pd-balanced`            | Small / non-prod         | General apps                       |
| `pd-ssd`                 | Works                    | Databases, ODF backing             |
| `hyperdisk-balanced`     | Works on supported series| Independent IOPS/throughput        |

Keep the whole cluster on one family (`pd-*` or hyperdisk). Mixing them is how
you get surprise attach limits.

### IBM Cloud, IBM Power, IBM Z

| Platform                         | What to use                                              | What not to use                                      |
| -------------------------------- | -------------------------------------------------------- | ---------------------------------------------------- |
| IBM Cloud VPC block              | `ibmc-vpc-block-10iops-tier` or custom/SDP for etcd-like | `3iops-tier` / general-purpose for control plane     |
| IBM Power                        | Local SSD (NVMe/SAS/SAN) via Local Storage Operator      | HDD OSDs for internal ODF                            |
| IBM Z / LinuxONE                 | Local SSD; DASD partitioning is the exception            | NFS under etcd                                       |

VPC **10 IOPS/GB** is the usual production tier. Custom / SDP profiles start
around **3,000 IOPS** and can go to **64,000**, with throughput up to about
**1,024 MBps**. ODF on Power asks for more CPU/RAM than x86 (48 logical CPU and
192 GiB aggregate for a three-node internal base).

### Edge, SNO, hosted control planes

| Form factor                      | etcd disk                                                | Persistent data                                      |
| -------------------------------- | -------------------------------------------------------- | ---------------------------------------------------- |
| Single Node OpenShift            | Local NVMe/SSD, 120 GB minimum                           | LVMS on extra disks or an array; see [edge architectures](/posts/openshift-edge-architectures/) |
| Compact three-node               | Local NVMe; do not share with OSDs                       | ODF additional device set on SSD                     |
| Hosted control planes            | etcd lives on the **management** cluster                 | Workers still need CSI that matches the workload     |
| Nested virt “lab on a laptop”    | Often fails 10 ms fsync                                  | Fine for demos that do not care about API latency    |

SNO plus LVMS is a coherent local-disk story. It is not HA. The
[Pure FlashArray + NVMe/TCP + LVMS](/posts/pure-flasharray-sno-nvme-tcp/)
pattern is an array-backed SNO, not a vSAN replacement.

## Persistent CSI: match the access mode, then the IOPS

Once etcd is local flash, workload storage is a CSI conversation.

| Workload                         | Recommended technology           | Avoid                                              |
| -------------------------------- | -------------------------------- | -------------------------------------------------- |
| Prometheus / metrics             | Block                            | File RWX; RHEL NFS                                 |
| Loki                             | Object (S3-compatible)           | NFS as the Loki PV                                 |
| Elasticsearch log store          | Block                            | NFS (corruption risk; not supported)               |
| Image registry (HA)              | Object, then file RWX            | Block (not RWX); RHEL NFS as the default           |
| Databases                        | Dedicated block                  | Shared NFS                                         |
| OpenShift Virtualization VMs     | **RWX Block**                    | LVMS/LSO (RWO); filesystem-mode extra hop          |
| General RWX apps                 | File or RWX block CSI            | HostPath                                           |

RHEL NFS as a PV for registry, Prometheus, Elasticsearch, and Quay is **not
recommended**. Other NFS stacks vary; the
[NFS for OpenShift internal components](https://access.redhat.com/solutions/3428661)
KCS is the support line, not a hallway opinion.

ODF performance profiles (CPU/RAM for the storage cluster, not a disk magic
knob): **Lean** 24 CPU / 72 GiB, **Balanced** 30 / 72, **Performance** 45 / 96
GiB aggregate. Replica **3** means usable capacity is about one third of raw.
Alerts at 75% and 85% full are operational, not optional.

For Virtualization, live migration needs RWX. Block volume mode. Snapshots and
clones. That shortlist is
[vSAN-like storage for OpenShift Virtualization Engine](/posts/ove-vsan-storage-alternatives/),
not “any StorageClass that bound a PVC.”

## What I reject in a design review

These fail in production often enough to treat as defaults-to-no:

1. **HDD or hybrid spinning capacity under etcd** — including “the SAN is fast”
   when the LUN is still a RAID-6 HDD pool.
2. **NFS, iSCSI, or Ceph RBD as the etcd disk** — network plus fsync is the
   wrong latency distribution.
3. **Azure Premium disk that is too small** — you bought capacity, not the
   5,000 IOPS / 200 MBps the control plane needs.
4. **AWS `gp2` or `st1` for control plane** — burst and HDD throughput are not
   an etcd SLA.
5. **ODF OSDs on the OS/etcd disk, mixed SSD+HDD in one device set, or
   partitions on x86** — unsupported or a noisy-neighbor trap.
6. **Nested hypervisors for anything you will measure** — extra fsync delay
   shows up as random API slowness.
7. **LVMS or hostPath for HA VMs** — RWO. Drain powers off the VM.
8. **RHEL NFS for Prometheus, Elasticsearch, Loki, or a scaled registry** —
   documented as not recommended or not supported.
9. **Consumer NVMe and RAID-5 “because it is flash”** — p99 writes still miss
   the 10 ms WAL bar.
10. **One StorageClass for etcd, VMs, and object** — three planes, three
    answers.

## How I would choose

**Bare metal production:** local NVMe (or enterprise SAS SSD) for control
plane; extra NVMe/SSD for ODF or a certified array CSI for workloads. `fio`
before the first ISO.

**vSphere:** all-flash datastore or a flash SPBM policy for control-plane VMDKs.
Passthrough NVMe if the datastore cannot make fsync. Array CSI or ODF for RWX;
do not stack both.

**AWS / ROSA:** `gp3` with the 3,000 / 125 baseline as the floor; raise IOPS and
throughput for busy clusters or use `io2`. Never `st1` for etcd.

**Azure:** P30 or Premium v2/Ultra for control plane, cache ReadOnly. Do not
ship a 256 GiB Premium disk and call it production.

**Edge / SNO:** one good local SSD for the node; LVMS or an array for PVCs.
Do not import datacenter HA storage expectations into a single disk.

## The SA takeaway

1. **etcd is a latency SLA** — 50 sequential 8 KB IOPS under 10 ms, 500 under
   2 ms when the cluster is busy, NVMe preferred, local block only.
2. **Installer 300 IOPS / 100 GB is the floor, not the design** — clouds often
   need a larger disk to buy IOPS (Azure P30 is the canonical example).
3. **SSD/NVMe for ODF internal; HDD is not that story** — same size and type
   per device set, extra disks besides the OS, 10 GbE floor.
4. **CSI follows the access mode** — block for etcd-adjacent platform
   components and VM disks; object for Loki and HA registry; NFS is not a
   universal RWX hammer.
5. **Prove it with `etcd-perf`** — a spec sheet that says “NVMe” is not a p99
   fsync measurement.

## Related posts

- [How to Get Started with an OpenShift PoC](/posts/getting-started-openshift-poc/)
- [vSAN-like Storage for OpenShift Virtualization Engine](/posts/ove-vsan-storage-alternatives/)
- [OpenShift Edge Architectures: Form Factor, Then Fleet](/posts/openshift-edge-architectures/)
- [Pure FlashArray on Single Node OpenShift with NVMe/TCP](/posts/pure-flasharray-sno-nvme-tcp/)

> Want help mapping disks and IOPS onto a landing zone? Reach out to your Red
> Hat account team—or run `etcd-perf` on the actual control-plane disk before
> you freeze the bill of materials.
{: .prompt-tip }

## Further reading

- [Recommended etcd practices (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/etcd/etcd-practices)
- [Optimizing storage (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/scalability_and_performance/scalability-and-performance-optimization)
- [Installing on bare metal — minimum resources (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/installing_on_bare_metal/user-provisioned-infrastructure)
- [ODF 4.21 infrastructure requirements](https://docs.redhat.com/en/documentation/red_hat_openshift_data_foundation/4.21/html/planning_your_deployment/infrastructure-requirements_rhodf)
- [Is NFS supported for OpenShift cluster internal components?](https://access.redhat.com/solutions/3428661)
- [Storage considerations for OpenShift Virtualization](https://developers.redhat.com/articles/2025/07/10/storage-considerations-openshift-virtualization)
- [OpenShift PoC overview](https://openshift-ssa.github.io/openshift-poc/home/)
- [Storage (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/post-installation/storage/)
- [OpenShift Data Foundation (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/post-installation/storage/odf/)
- [Prerequisites — storage (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/prerequisites/storage/)
