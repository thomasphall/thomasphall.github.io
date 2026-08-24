---
title: "Why OVN-Kubernetes Is OpenShift's Default CNI"
description: >-
  OVN-Kubernetes is OpenShift 4.22's default CNI. Why keep it instead of
  Cilium or Calico, and when a certified vendor plugin is still the right
  call on 4.22.
date: 2026-08-24 09:00:00 -0500
categories: [OpenShift, Virtualization]
tags: [openshift, networking, openshift-virtualization]
og_image: /assets/img/og/ovn-kubernetes-openshift-cni.png
permalink: /posts/ovn-kubernetes-openshift-cni/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization.
{: .prompt-info }

Ask a platform team which Container Network Interface (CNI) they want on
[Red Hat OpenShift](https://www.redhat.com/en/technologies/cloud-computing/openshift)
and the answer is often a vendor name: Cilium, Calico, sometimes “whatever the
fabric team already bought.” That is the right question on generic Kubernetes.
On OpenShift Container Platform 4.22 it is usually the wrong first question.
The default plugin is **OVN-Kubernetes**, it is what Red Hat OpenShift
Networking is built around, and the capabilities that showed up after OpenShift
SDN went away—User-Defined Networks, admin network policy, localnet for
virtual machines—exist only there.

This post is a solution-architect decision guide: why the default is the
design, what you actually lose if you replace it, and when a certified
third-party CNI is still the honest call. It is not a packet-per-second
bake-off. Confirm the
[OVN-Kubernetes docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/ovn-kubernetes_network_plugin/about-ovn-kubernetes)
and the current
[certified OpenShift CNI plug-ins](https://access.redhat.com/articles/5436171)
row for the version you will install. CNI is an **install-time** choice.

For how that CNI lands VMs on VLANs, start with
[OpenShift Virtualization networking](/posts/openshift-virtualization-networking/).
For who owns isolation after the overlay is up, see
[Network Policies: Tenant, Admin, Secondary](/posts/openshift-network-policies/).
To prove a drop, install
[Network Observability](/posts/network-observability-openshift/).

## What OVN-Kubernetes is

OVN-Kubernetes is the default CNI for OpenShift Container Platform and
[Single Node OpenShift](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/installing_on_a_single_node/).
It is not a bolt-on Operator you subscribe to after day two. The installer
sets `networking.networkType: OVNKubernetes`. Each node runs Open vSwitch
(OVS). Open Virtual Network (OVN) turns Kubernetes objects into logical
switches, routers, and ACLs, then programs OpenFlow on those bridges. The
overlay between nodes is **Geneve**, not VXLAN.

That is the same family of primitives datacenter SDN used for a decade:
distributed virtual routing, logical switches, DHCP, and access control. On
OpenShift it also implements the features platform teams actually ask for in a
landing zone:

| Capability | What it is for |
| ---------- | -------------- |
| Kubernetes `NetworkPolicy` plus logs | Tenant east-west on the pod network |
| `AdminNetworkPolicy` / `BaselineAdminNetworkPolicy` | Cluster guardrails tenants cannot override |
| Egress IP, egress firewall, egress router | Stable north-south identity and CIDR allow/deny |
| User-Defined Networks (UDN) | Isolated Layer 2 / Layer 3 segments, overlapping subnets |
| Localnet via `ClusterUserDefinedNetwork` | VMs and pods on real provider VLANs |
| IPsec | Encrypted overlay between nodes |
| Hardware offload | Move established flows to a SmartNIC or DPU |
| Dual-stack and hybrid (Linux + Windows) | Same CNI across those install shapes |

Secondary NICs still go through
[Multus](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/multiple_networks/understanding-multiple-networks)
and a `NetworkAttachmentDefinition`. You do **not** replace the cluster CNI to
get an extra VLAN, SR-IOV VF, or macvlan attachment. That confusion is how
PoCs pick Cilium “for secondary networks” and then rediscover Multus anyway.

## What “latest CNI” actually means

OpenShift SDN is gone. It was deprecated in 4.14, closed to new installs in
4.15, and blocked upgrades to 4.17. There is no SDN toggle left on 4.22. If
someone is still arguing OpenShift SDN versus OVN-Kubernetes, they are arguing
a migration that had to finish years ago.

The current default is not just “the overlay that replaced SDN.” The
capability that changed the design conversation is
[User-Defined Networks](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/multiple_networks/primary-networks).
Before UDN, OVN-Kubernetes offered one Layer 3 pod network and you microsegmented
it with `NetworkPolicy`. UDN adds isolated Layer 2 and Layer 3 segments that
can be a **primary** network for a namespace or a **secondary** attachment.
Localnet on a `ClusterUserDefinedNetwork` has been generally available since
4.19; on 4.22 it is the preferred way to hang VMs on a datacenter VLAN.

UDNs are **OVN-Kubernetes only**. A certified Cilium or Calico cluster does not
get `UserDefinedNetwork` or `ClusterUserDefinedNetwork`. That is the feature
you are walking away from when you change `networkType`.

## Why keep the default instead of a vendor CNI

The usual vendor pitch is performance (eBPF) or routing (BGP). Those are real
products. They are not why OpenShift defaults to OVN-Kubernetes, and they are
not why most landing zones should keep it.

**1. One support path for the platform and the network.** Red Hat owns
OVN-Kubernetes as part of OpenShift. A Sev1 that is “pods cannot reach the
API” does not start with a vendor-of-record argument. Third-party CNI means
Red Hat plus Isovalent, Tigera, or Cisco, with custom manifests you supplied
at install. That split is survivable. It is not free.

**2. The rest of OpenShift Networking assumes it.** Admin Network Policy,
egress IP, egress firewall, UDN, and the useful
`OVS_DROP_*` reasons in Network Observability are OVN/OVS features. You can
still run Network Observability on another CNI for generic flows. You should
not expect the same OVN policy correlation, UDN mapping, or localnet story.
See
[Network Observability on OpenShift 4.22](/posts/network-observability-openshift/)
and
[the three policy planes](/posts/openshift-network-policies/).

**3. Virtualization is designed onto this CNI.** Guest attach, live-migration
identity, and VLAN/port-group mapping assume OVN-Kubernetes. Certified vendors
may pass Virt tests. They do not give you UDN. The next section is that
argument in full.

**4. It ships. You do not bring manifests.** Assisted Installer, IPI, and UPI
all know `OVNKubernetes`. Cilium, Calico, and Cisco ACI are `networkType`
values that **require vendor manifests** before bootstrap. The installer does
not generate them. That is extra day-0 load, extra GitOps, and an extra thing
that can fail a 4.y upgrade.

**5. Hardware offload is an OVS story.** OVN-Kubernetes can push established
flows to a compatible SmartNIC or DPU (NVIDIA BlueField and similar). Cilium’s
eBPF path is fast in software. If the requirement is “take packet processing
off the host CPU,” that is offload, not a CNI brand preference.

**6. No second network license for the default path.** Isovalent Networking
for Kubernetes and Tigera Calico Enterprise are excellent products with their
own commercial motion. OVN-Kubernetes is in the OpenShift subscription. Do not
buy a CNI to get NetworkPolicy. You already have it.

**7. You can still attach vendor hardware without replacing the CNI.** SR-IOV,
macvlan, ipvlan, and localnet sit beside OVN-Kubernetes via Multus. Replacing
the primary CNI because a NIC vendor’s slide mentioned their plugin is solving
the wrong layer.

## OpenShift Virtualization

[OpenShift Virtualization](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/index)
does not get a second CNI. Each guest runs in a `virt-launcher` pod. The
cluster plugin still owns east-west, live migration, and how a VNIC lands on
the host. If VMware exit is on the calendar, this is the CNI conversation—not
a later day-2 Operator.

The 4.22 field path has three attachments. Host underlay, NNCP, and CUDN YAML
live in
[OpenShift Virtualization networking](/posts/openshift-virtualization-networking/).
Here is the CNI decision those patterns depend on.

| Guest need | Attachment | Why it wants OVN-Kubernetes |
| ---------- | ---------- | --------------------------- |
| Services, Routes, LoadBalancer; IP may change on migrate | Default pod network (masquerade) | Same overlay as every other pod; Network Observability sees it with no extra flags |
| Tenant isolation, overlapping subnets, persistent guest IP across live migration | Primary Layer 2 UDN | UDN is OVN-Kubernetes only; the guest default NIC is on an isolated L2 that spans nodes |
| Datacenter VLAN / “give me that port group,” no SNAT to the node IP | Secondary localnet via `ClusterUserDefinedNetwork` | CUDN localnet maps a physnet to an OVS bridge; that is the OVN localnet topology |
| Highest NIC performance / VF in the guest | SR-IOV (Multus) | Secondary CNI. Keep OVN-Kubernetes as primary; do not replace the cluster plugin to get a VF |

Masquerade is enough when the VM looks like a Kubernetes workload. It is the
wrong answer when the guest IP **must not** be the pod IP. On migrate, the
pod IP follows the node `/23`. A primary Layer 2 UDN is the migration-friendly
identity virtualization teams are asking for. Localnet is the VLAN: CUDN
selects namespaces, the controller generates the NAD, the VM attaches with
Multus. You do not buy Cilium to get a port group.

The Virt badge on a certified third-party CNI means conformance tests passed.
It does not mean UDN, CUDN localnet, or OVN egress IP exist on that cluster.
If you install Isovalent or Calico because “it is certified for Virtualization,”
you still hand-build secondary NADs for VLANs, you still do not get isolated
primary Layer 2 tenant nets, and live-migration addressing is whatever that
vendor overlay does—not the UDN model the rest of the OpenShift Virtualization
docs assume. Prove the requirement that forces that, then accept the gap.

Policy still splits by NIC, on any CNI:

- `NetworkPolicy` and `AdminNetworkPolicy` cover the pod network and a
  **primary** UDN.
- `MultiNetworkPolicy` covers a **secondary** NIC (localnet, SR-IOV kernel,
  macvlan). Enable it; bind it to the NAD. The default-deny you wrote for the
  pod network does not see VLAN 1924.

That split is
[Network Policies: Tenant, Admin, Secondary](/posts/openshift-network-policies/).
Network Observability follows the same cut: masquerade flows are in the
default `FlowCollector`; primary UDN needs `UDNMapping`; localnet and SR-IOV
need privileged eBPF agents. See
[Network Observability on OpenShift 4.22](/posts/network-observability-openshift/).

Do not replace OVN-Kubernetes because the VM team said “we need VLANs.” Design
the host (native, tagged, or dual-bond), map localnet once per OVS bridge,
define VLANs as CUDN, attach the VM. Linux bridge is the exception for VLAN
guest tagging into the guest, not the default. SR-IOV is hardware, not a CNI
swap.

## Certified vendors when you actually need them

Red Hat certifies third-party CNI plugins that deploy as Operators and pass
conformance. Network Conformance is required. Virtualization, Service Mesh,
and Hosted Control Planes are extra badges. The live matrix is
[Certified OpenShift CNI Plug-ins](https://access.redhat.com/articles/5436171)—
re-read it when you freeze a version. Rows below are what that article showed
for OpenShift **4.22** in August 2026.

| Partner | Product (4.22 row) | Tests passed | Pick it when |
| ------- | ------------------ | ------------ | ------------ |
| Red Hat | OVN-Kubernetes (default) | Platform native | Default for almost every cluster |
| Cisco Isovalent | Isovalent Networking for Kubernetes 1.17–1.19 | Net, Virt, Mesh, HCP | Existing Cilium estate, Hubble, or L7 (HTTP/gRPC) policy as a hard requirement |
| Tigera | Calico Core 3.32 | Net, Virt, Mesh, HCP | BGP into the physical fabric, or Calico/Tigera policy you already operate fleet-wide |
| Cisco | ACI CNI | See matrix (listed through 4.21 on that snapshot) | The fabric is ACI and the CNI must map to EPGs; confirm the 4.22 row before you bet the install |
| Broadcom / VMware | Antrea, NSX NCP | Stale (Antrea 1.10 on 4.18; NCP on 4.4) | Do not design a 4.22 cluster on these rows |

Flannel is not a certified OpenShift primary CNI. Neither is “we will run
community Cilium and support it ourselves.” If you leave OVN-Kubernetes, leave
it for a **certified** build of a product you already know how to operate.

### Isovalent (Cilium)

Cilium is the honest alternative when the datapath requirement is eBPF, when
Hubble is already how the network team debugs, or when Layer 7 policy (HTTP
method, gRPC service, Kafka topic) is in the security design—not as a
nice-to-have on a slide. Isovalent Networking for Kubernetes 1.19 is certified
on OpenShift 4.21 and 4.22 including Virtualization, Service Mesh, and Hosted
Control Planes.

What you still owe the design: vendor manifests at install, Isovalent in the
support path, and no UDN. Do not pick Cilium because “eBPF is faster” and then
spend the PoC re-implementing egress IP and VLAN attach that OVN-Kubernetes
already had.

### Tigera (Calico)

Calico is the honest alternative when pods must be **routable on the physical
network** (BGP) instead of living behind a Geneve overlay, or when Calico
Enterprise / Tigera policy is already the standard across Kubernetes estates
that are not all OpenShift. Calico Core 3.32 is certified on 4.19–4.22 with
the same Net, Virt, Mesh, and HCP badges as current Isovalent.

BGP is a fabric conversation. If the network team does not want to carry pod
CIDRs, you are buying operational coupling, not a cleaner CNI. Overlay
isolation plus UDN is usually the OpenShift-shaped answer.

### Cisco ACI

ACI CNI is for estates where the leaf-spine **is** ACI and endpoints must
show up as EPGs. It is UPI, and the certified article listed 4.15–4.21 on
bare metal, vSphere, and OpenStack—not a 4.22 row in that snapshot. Treat ACI
as “required by the fabric,” then confirm the exact OpenShift and ACI
versions with Cisco and Red Hat before Assisted Installer sees the cluster.

### What you accept when you leave OVN-Kubernetes

- **Install-time only.** There is no supported live migrate from a third-party
  CNI onto OVN-Kubernetes the way OpenShift SDN had. Get it right on the first
  cluster.
- **Custom manifests.** You fetch them from the vendor. You keep them current
  across 4.y.
- **No UDN.** Primary Layer 2 tenant nets and CUDN localnet are off the table.
- **Split support.** File against Red Hat and the CNI vendor; know which
  queue owns overlay vs node vs policy.
- **Tooling gaps.** ANP/BANP, OVN egress APIs, and some Network Observability
  drop reasons are OVN-Kubernetes features. Budget replacements.

## When to choose what

| Need | Prefer |
| ---- | ------ |
| New OpenShift cluster, including SNO and Virtualization | OVN-Kubernetes (default) |
| Tenant isolation, overlapping subnets, persistent VM IPs | Primary Layer 2 UDN on OVN-Kubernetes |
| VM or pod on a datacenter VLAN | CUDN localnet on OVN-Kubernetes, not a different CNI |
| Extra NIC (SR-IOV, macvlan, ipvlan) | Multus secondary network; keep OVN-Kubernetes as primary |
| Cluster-wide isolation tenants cannot override | `AdminNetworkPolicy` on OVN-Kubernetes |
| Encrypted node-to-node overlay | OVN-Kubernetes IPsec |
| Packet processing off the host CPU | OVN-Kubernetes with hardware offload |
| L7 HTTP/gRPC policy or existing Hubble/Cilium operations | Certified Isovalent Networking for Kubernetes |
| BGP to the physical fabric or existing Tigera policy estate | Certified Tigera Calico |
| Fabric is Cisco ACI and EPGs are mandatory | Cisco ACI CNI, after you confirm the 4.22 certification row |
| “Cilium is what we use on EKS/AKS” with no OpenShift-specific requirement | Still OVN-Kubernetes—do not copy the other platform’s CNI by habit |

ROSA and other managed OpenShift shapes do not offer this fork. You get
OVN-Kubernetes. Design the application network for that.

## The solutions architect takeaway

1. **OVN-Kubernetes is the CNI.** OpenShift SDN is gone. UDN, localnet, ANP,
   and egress IP are why the default is the product, not a placeholder.
2. **Virtualization does not get a second CNI.** Masquerade, primary Layer 2
   UDN, and CUDN localnet are the 4.22 VM path. A Virt certification badge is
   not a substitute for UDN.
3. **Do not replace it to get extra NICs.** Multus secondary networks sit on
   top of the default CNI. VLAN attach for VMs is CUDN localnet.
4. **Vendor CNIs are certified exceptions.** Isovalent and Tigera are real
   4.22 options with Virt, Mesh, and HCP badges. Use them for L7/eBPF or BGP
   fabric requirements you can name, not for a preference.
5. **Confirm the matrix.** ACI, Antrea, and NSX rows lag. Read
   [Certified OpenShift CNI Plug-ins](https://access.redhat.com/articles/5436171)
   for the OpenShift version on the purchase order.
6. **Decide at install.** Third-party `networkType` needs vendor manifests and
   does not get a later in-place swap onto OVN-Kubernetes.

Keep host underlay and CUDN definitions in the **cluster** GitOps repository
the same way you keep the Network Operator. For a PoC, leave `networkType`
alone, finish DNS and the underlay, then prove a UDN or a localnet VM before
anyone schedules a Cilium bake-off. Sequencing for that path is in
[How to Get Started with an OpenShift PoC](/posts/getting-started-openshift-poc/).

## Related posts

- [OpenShift Virtualization Networking: Pod to Localnet](/posts/openshift-virtualization-networking/)
- [OpenShift Network Policies: Tenant, Admin, Secondary](/posts/openshift-network-policies/)
- [How to Install Network Observability on OpenShift 4.22](/posts/network-observability-openshift/)
- [How to Get Started with an OpenShift PoC](/posts/getting-started-openshift-poc/)

> Want help choosing a CNI for a landing zone? Reach out to your Red Hat
> account team—or install 4.22 with OVN-Kubernetes, prove a primary UDN and a
> CUDN localnet VM, and only then write down the requirement that would force
> Cilium, Calico, or ACI.
{: .prompt-tip }

## Further reading

- [About the OVN-Kubernetes network plugin (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/ovn-kubernetes_network_plugin/about-ovn-kubernetes)
- [Primary networks / UDN (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/multiple_networks/primary-networks)
- [Understanding multiple networks (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/multiple_networks/understanding-multiple-networks)
- [OpenShift Virtualization networking (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/networking)
- [Certified OpenShift CNI Plug-ins](https://access.redhat.com/articles/5436171)
- [Installation configuration parameters — `networkType` (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/installation_configuration/installation-config-parameters-generic)
- [Networking (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/post-installation/networking/)
- [Prerequisites — Networking (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/prerequisites/networking/)
