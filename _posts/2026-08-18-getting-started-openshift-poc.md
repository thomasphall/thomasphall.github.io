---
title: "How to Get Started with an OpenShift PoC"
description: >-
  How to start an on-prem OpenShift PoC: pick a single cluster or a
  fleet hub, finish DNS and firewall first, then use Assisted
  Installer and day-2 operators.
date: 2026-08-18 13:00:00 -0500
categories: [OpenShift]
tags: [openshift, bare-metal, sno, acm, gitops]
og_image: /assets/img/og/getting-started-openshift-poc.png
permalink: /posts/getting-started-openshift-poc/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization.
{: .prompt-info }

OpenShift PoCs rarely stall on the installer. They stall on tickets: DNS,
firewall, BMC access, and a pull secret that is not actually entitled. The
[OpenShift PoC guide](https://openshift-ssa.github.io/openshift-poc/home/)
is the on-prem runbook for that work. This post is the sequencing layer: pick
a path, finish prerequisites with the right teams, then install.

It is not a substitute for product procedure. Confirm the
[OpenShift Container Platform](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/)
version, CSI driver, and operators you will actually run. The PoC site currently
documents a 4.21 line; this blog’s latest stable line is 4.22.

## Pick the path before you rack

The [OpenShift PoC guide](https://openshift-ssa.github.io/openshift-poc/home/)
recommends two starting architectures. Do not mix them on day one. Fleet work
uses
[Red Hat Advanced Cluster Management for Kubernetes (RHACM) 2.16](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/2.16/).

| Path             | Use it when                                                         | First cluster                   |
| ---------------- | ------------------------------------------------------------------- | ------------------------------- |
| Installation     | OpenShift as an application platform, Virtualization, or both       | Connected multi-node (3 + 3)    |
| Fleet management | You also need RHACM to provision and govern more than one cluster   | SNO hub, then spokes from RHACM |

[Installation](https://openshift-ssa.github.io/openshift-poc/installation/)
is the platform path.
[Fleet management](https://openshift-ssa.github.io/openshift-poc/fleet-management/)
is the RHACM path.

The hub is a management plane. Do not park the customer’s first production-like
workload on it. Form factor still comes first if the story is edge—see
[OpenShift edge architectures](/posts/openshift-edge-architectures/).
If the story is nested control planes, that is a later fork, not the first
cluster: [hosted vs virtualized control planes](/posts/hosted-vs-virtualized-control-planes/).

Bring infrastructure, networking, security, and application owners in before
the first ISO boots. A PoC that surprises the DNS or firewall team is already
late.

## Prerequisites are the install

Do not start until evaluation subscriptions exist on an **organizational**
Red Hat account, allocated to the person who will install. Personal accounts
and “we will entitle it later” are how image pulls fail at hour six.

Work from a shared
[installation host](https://openshift-ssa.github.io/openshift-poc/prerequisites/installation-host/)
(RHEL 9 is the PoC default) on the same network as the nodes. Laptops go on
PTO; a jump host does not. Put `oc`, `openshift-install`, `nmstatectl`, git,
and Podman there. Download the
[pull secret](https://console.redhat.com/openshift/install/pull-secret)
and generate an SSH key before you open the installer UI.

Then close the five gates the guide treats as blocking:

1. **Hardware inventory** — hostname, install disk, every NIC name and MAC,
   BMC IP and credentials. If you do not know the disk or NIC names, boot a
   RHEL ISO and look. Do not guess. Verify Redfish or vendor BMC access from
   the installation host, including virtual media. Minimums live on
   [infrastructure](https://openshift-ssa.github.io/openshift-poc/prerequisites/infrastructure/).
   Same CPU vendor and generation across the rack avoids surprise.
2. **DNS before ISO** — `api`, `api-int`, and `*.apps` under
   `<cluster>.<base_domain>`. On SNO those records point at the node
   IP. On a multi-node cluster they point at the API and Ingress VIPs. Validate
   with `dig` from the install network, not from a laptop on another DNS view.
   See [DNS](https://openshift-ssa.github.io/openshift-poc/prerequisites/dns/).
3. **Static IPs, NTP, and a simple network** — this PoC assumes no DHCP. Keep
   one NIC or one bond for all traffic unless the customer already has a
   production-like split. Default pod (`10.128.0.0/14`) and service
   (`172.30.0.0/16`) CIDRs unless you have a collision. Isolate the machine
   network from VM workload VLANs if OpenShift Virtualization is in scope.
   Details:
   [networking](https://openshift-ssa.github.io/openshift-poc/prerequisites/networking/).
4. **Firewall and egress** — cluster ports between nodes, plus outbound HTTPS
   to Red Hat registries, `console.redhat.com`, and update endpoints unless you
   are doing a
   [disconnected install](https://openshift-ssa.github.io/openshift-poc/installation/disconnected/).
   If a TLS-inspecting proxy is in the path, the proxy CA belongs in the
   additional trust bundle **before** discovery. Missing that bundle looks like
   a random `x509` failure two hours in.
5. **Storage is day-2, etcd is local** — CSI is not required to install
   OpenShift. It is required before persistent workloads. Bring the storage
   vendor for the driver. Keep etcd on local NVMe or SSD that can fdatasync
   an 8 KB write under 10 ms. Disk types, IOPS, and per-architecture traps
   are in
   [OpenShift storage performance](/posts/openshift-storage-performance/).
   Jumbo frames for the storage path must be end-to-end or they will bite
   after the cluster looks healthy. See
   [storage](https://openshift-ssa.github.io/openshift-poc/prerequisites/storage/).

UEFI boot, UTC clock, and a boot order that prefers local disk once virtual
media is attached. On dense-memory loaner gear,
[temporarily disabling firmware memory tests](/posts/poc-faster-bare-metal-boot-disable-memory-check/)
reclaims POST time; restore before handback.

## Install with Assisted, unless you cannot

For a connected on-prem PoC, use the
[Assisted Installer](https://openshift-ssa.github.io/openshift-poc/installation/assisted-installer/)
in the
[Red Hat Hybrid Cloud Console](https://console.redhat.com/openshift/assisted-installer/clusters).
Static IP, bridges, and bonds. No platform integration on bare metal. Do not
preinstall operators. Pick the install disk explicitly and do not format
network-attached disks.

Serve the discovery ISO from the installation host over HTTP (port 8080) or
give each BMC its **own copy**. Sharing one ISO file across several BMC
consoles is a classic virtual-media failure.

Expect roughly 30–45 minutes for a six-node cluster, 20–30 for SNO. Login as
`kubeadmin`, then wait until `clusterversion` and `clusteroperators` are
stable before you call it installed.

Use a different installer only when the constraint is real:

- **[Agent-based](https://openshift-ssa.github.io/openshift-poc/installation/agent-based/)**
  when you need a locally generated ISO, limited connectivity to
  `console.redhat.com`, or Git-tracked `install-config.yaml` /
  `agent-config.yaml`.
- **Disconnected** when nodes cannot reach Red Hat registries. Mirror or
  pull-through first; then agent-based. Do not discover this after hosts are
  in the Ready state.
- **[vSphere IPI](https://openshift-ssa.github.io/openshift-poc/installation/vmware-install/)**
  when the hypervisor is vSphere and you want the in-tree integration.
- **[OpenShift on OpenShift](https://openshift-ssa.github.io/openshift-poc/installation/openshift-on-openshift/)**
  when the PoC is hosted control planes on an existing management cluster.

The fleet path is the same installer with SNO settings: one control plane, no
workers, no VIPs. Then
[hub storage](https://openshift-ssa.github.io/openshift-poc/fleet-management/hub-storage/),
[RHACM](https://openshift-ssa.github.io/openshift-poc/fleet-management/acm-install/),
and
[spoke provisioning](https://openshift-ssa.github.io/openshift-poc/fleet-management/acm-provision-bare-metal-cluster/).
How RHACM itself should be fed from Git is a separate split—
[GitOps should manage ACM, not the cluster](/posts/gitops-should-manage-acm/).

## Day-2 in order, then prove one workload

After install, the guide’s **required** sequence is short on purpose:

1. [NMState Operator](https://openshift-ssa.github.io/openshift-poc/post-installation/nmstate/)
   before bonds, VLANs, or OVS bridges.
2. [CSI and StorageClasses](https://openshift-ssa.github.io/openshift-poc/post-installation/storage/)
   before anything that needs a PVC.
3. [Internal registry](https://openshift-ssa.github.io/openshift-poc/post-installation/registry/)
   on persistent storage.

Everything else is optional and should match the customer story: identity,
GitOps, virtualization (after
[workload availability](https://openshift-ssa.github.io/openshift-poc/post-installation/workload-availability/)),
[MTV](https://openshift-ssa.github.io/openshift-poc/post-installation/mtv/),
logging, Service Mesh, and
[Network Observability](/posts/network-observability-openshift/)
after CSI and the underlay. Mark the console with the
[PoC banner](https://openshift-ssa.github.io/openshift-poc/post-installation/poc-banner/)
so nobody treats kubeadmin as production.

Then run one container and, if virt is in scope, one VM from the
[workloads](https://openshift-ssa.github.io/openshift-poc/workloads/)
section. Failover and backup demos live under
[operations](https://openshift-ssa.github.io/openshift-poc/operations/).
A green `clusterversion` with no PVC and no idp is not a finished PoC.

## The SA takeaway

1. **Pick installation or fleet, not both** — six-node platform cluster, or
   SNO hub plus RHACM spokes.
2. **Prerequisites are the critical path** — account, DNS, static IPs,
   firewall, BMC, and NTP before any ISO.
3. **Assisted Installer is the default** — agent-based, disconnected, vSphere,
   and hosted control planes are constraint-driven forks.
4. **Keep the first network simple** — one NIC or bond; add trunks after
   NMState.
5. **Required day-2 is NMState, CSI, registry** — then one workload that
   matches the story you sold.

Start at the
[OpenShift PoC overview](https://openshift-ssa.github.io/openshift-poc/home/)
and treat the rest of that site as the procedure. This post is only the order
of operations.

## Related posts

- [Faster Bare-Metal Boots in OpenShift PoCs](/posts/poc-faster-bare-metal-boot-disable-memory-check/)
- [OpenShift Storage Performance: Disks, IOPS, Architectures](/posts/openshift-storage-performance/)
- [OpenShift Edge Architectures: Form Factor, Then Fleet](/posts/openshift-edge-architectures/)
- [Hosted vs Virtualized Control Planes on OpenShift 4.22](/posts/hosted-vs-virtualized-control-planes/)

> Want help applying this in your environment? Reach out to your Red Hat
> account team—or run the prerequisites checklist on paper with networking and
> storage before you generate a discovery ISO.
{: .prompt-tip }

## Further reading

- [OpenShift PoC overview](https://openshift-ssa.github.io/openshift-poc/home/)
- [Prerequisites (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/prerequisites/)
- [Assisted Installer (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/installation/assisted-installer/)
- [Fleet management (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/fleet-management/)
- [Assisted Installer product docs](https://docs.redhat.com/en/documentation/assisted_installer_for_openshift_container_platform/latest/html/installing_openshift_container_platform_with_the_assisted_installer/index)
