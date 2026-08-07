---
title: "OpenShift Virtualization Networking: From Pod Network to Localnet"
description: >-
  A layered OpenShift 4.22 mental model for OpenShift Virtualization
  networking—pod network, User-Defined Networks, host architectures, and CUDN
  localnets—with field YAML for platform teams.
date: 2026-07-27 18:00:00 -0500
categories: [OpenShift, Virtualization, Networking]
tags: [openshift-virtualization, networking, udn, localnet, ovn-kubernetes, "4.22"]
permalink: /posts/openshift-virtualization-networking/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization.
{: .prompt-info }

Virtual machines on [Red Hat OpenShift](https://www.redhat.com/en/technologies/cloud-computing/openshift)
share the same networking plane as pods—but live migration, persistent guest
IPs, and datacenter VLANs change the design questions. If you come from VMware,
you already think in port groups and uplinks. On
[OpenShift Virtualization](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/index)
4.22, the durable mental model is layered: CNI and Multus, the default pod
network, User-Defined Networks, host bridges for provider access, then
Cluster User Defined Networks for VLAN attach. This post is a
solution-architect field guide—not a full CNI catalog.

For release context around networking and day-2 operations, see also
[What's New in OpenShift Virtualization 4.22](/posts/openshift-virtualization-4-22-features/).
Segmentation and MAC spoof filtering sit beside the broader
[hardening priorities](/posts/openshift-virtualization-hardening-priorities/)
conversation. Network maps also show up in VMware exit waves—see
[storage copy offload for MTV](/posts/mtv-storage-copy-offload-vmware/) when disk
copy is the bottleneck and VLAN/port-group mapping is still on the critical path.

## Foundation: CNI, Multus, and OVN-Kubernetes

The [Container Network Interface (CNI)](https://www.cni.dev/) is how runtimes
ask plugins to configure interfaces. OpenShift's default story is
OVN-Kubernetes. Secondary networks—extra NICs on pods or VMs—come through
[Multus](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/multiple_networks/understanding-multiple-networks)
and `NetworkAttachmentDefinition` objects that tell Multus which plugin and
config to apply.

OpenShift Virtualization uses that same path. KubeVirt creates VNICs and
bindings; OVN-Kubernetes (or another secondary CNI) owns connectivity on the
pod that hosts the VM. The bindings you will see most often are
**masquerade** (default pod network), **bridge** / **l2bridge** (secondary or
primary UDN paths), and **SR-IOV** when hardware requires it.

## Default pod network: enough until it is not

Every virt-launcher pod gets a primary interface on the cluster network. That
network is the pod's default route. The default `clusterNetwork` is typically
`10.128.0.0/14` with a `/23` per node—room for on the order of hundreds of pods
per host. Confirm with:

```bash
oc get network.config/cluster -o yaml | yq .spec.clusterNetwork
```

Inside the guest, OpenShift Virtualization's masquerade binding usually presents
a fixed guest address such as `10.0.2.2/24`, with the virt-launcher side at
`10.0.2.1` as the gateway. Externally, the VM **masquerades as the pod IP**.
That pod IP is drawn from the node's `/23` and **changes if the VM live
migrates** to another node. At the node edge, egress commonly masquerades again
via `br-ex`.

Use the default pod network when Kubernetes access patterns are enough:
Services, Routes, and LoadBalancer objects. Reach for something else when the
workload needs a stable L2/L3 identity on a datacenter VLAN, tenant isolation
with overlapping subnets, or migration-safe addressing that does not follow the
pod IP.

## User-Defined Networks: tenant-friendly overlays

[User-Defined Networks (UDN)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/multiple_networks/primary-networks)
give projects isolated, VM-friendly networks without hand-building every Multus
YAML. Tenants use `UserDefinedNetwork`; cluster admins use
`ClusterUserDefinedNetwork` (CUDN). Both sit on OVN-Kubernetes and unlock
persistent IPAM for VMs, overlapping subnets across tenants, and topologies that
map cleanly to virtualization conversations. OpenShift Virtualization's supported
UDN topologies for VMs are **Layer2** and **Localnet**—treat Layer3 as a pod
overlay option, not your default VM design.

| Topology | Role | VM-friendly | Typical use |
| -------- | ---- | ----------- | ----------- |
| Layer2 overlay | Primary | Yes | Tenant default network; live-migration-friendly L2; pod default interface |
| Layer2 overlay | Secondary | Yes | Extra L2 segment for VMs without replacing the primary |
| Layer3 overlay | Primary / Secondary | Limited | Per-node CIDRs; not the usual VM primary path |
| Localnet (physnet) | Secondary only | Yes | Direct attach to provider VLANs (“Virtual Machine Network” in the console) |

For most OpenShift Virtualization designs on 4.22, two patterns matter first:

1. **Primary Layer2 UDN** — isolated-by-default tenant network with persistent
   guest IPs and a logical switch that spans nodes for live migration. The
   virt-launcher still keeps an infrastructure-locked interface on the cluster
   network for kubelet health checks; the guest's default NIC is on the UDN.
2. **Secondary localnet** — VM on a real datacenter VLAN without SNAT to the
   node IP. Think “port group on a trunked uplink,” expressed as Kubernetes
   objects.

On a primary Layer2 UDN, the guest typically receives an address from the UDN
subnet (for example `10.1.1.3/24`) with a UDN gateway, rather than the fixed
`10.0.2.2/24` masquerade pattern. That is the migration-friendly identity many
virtualization teams are asking for when they say “the VM IP must not be the
pod IP.”

Localnet is always secondary on the pod/VM network model (unless you take
unsupported Multus routing tricks). Only the admin API—CUDN—can define
localnet; the tenant `UserDefinedNetwork` API intentionally cannot, for
security. Existing Multus secondary networks are not displaced when you adopt
UDN—you can introduce CUDN localnets alongside older NADs during a migration.

## Host networking: where localnet actually lands

Localnet does not invent an uplink. It attaches OVN to an OVS bridge that
already sees provider VLANs. Day-0 OpenShift networking still centers on
`br-ex`: the external bridge that holds the node IP and carries Geneve overlay
traffic between nodes. Day-2 host configuration belongs in
[Kubernetes NMState](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/networking_operators/k8s-nmstate-about-the-k8s-nmstate-operator)—
`NodeNetworkState` for inspection, `NodeNetworkConfigurationPolicy` (NNCP) for
desired state, and enactments for status.

Three host architectures show up constantly in POCs and landing zones:

1. **Native single bond/NIC** — machine network on the native VLAN; `br-ex`
   sees the trunk. Map localnet to `br-ex` when that trunk already carries VM
   VLANs. The same pattern applies to a single NIC without a bond.
2. **Tagged single bond/NIC** — machine network on a tagged VLAN (for example
   `bond0.123`); `br-ex` sees only that VLAN. Add a second OVS bridge
   (`br-vmdata`) on the parent bond so VM VLANs have a trunk. This is the most
   common POC shape in practice—and the place teams get surprised when they
   assume `br-ex` still sees every tag.
3. **Dual bond** — one bond for machine/cluster traffic (`br-ex`), a second
   bond for VM data into `br-vmdata`. Clean separation for production-minded
   estates and the second most common POC when labs have enough NICs.

Use `nodeSelector` on NNCPs when workers are heterogeneous. Do not invent a
fourth architecture mid-migration without redrawing the switch trunk plan—most
“localnet does not work” tickets are uplink or mapping mismatches, not CUDN
syntax errors.

The glue between OVN and those bridges is an **OVN bridge mapping**: a
physical network name (for example `physnet-vmdata`) associated with an OVS
bridge. CUDN and NAD configs reference that name—not the bond or VLAN ID
directly. One mapping per bridge is enough; many VLANs can share
`physnet-vmdata` and differ only in the CUDN VLAN id.

## Field path on 4.22: dual bond, mapping, CUDN, VM

Prefer this modern path on OpenShift 4.22: configure the host with NNCP, define
VLANs with CUDN, let the controller generate NADs, then attach the VM. Do not
hand-author the generated `NetworkAttachmentDefinition` unless you are on an
older Multus-only workflow.

### 1) Second bond for VM data

```yaml
apiVersion: nmstate.io/v1
kind: NodeNetworkConfigurationPolicy
metadata:
  name: bond1
spec:
  nodeSelector:
    node-role.kubernetes.io/worker: ""
  desiredState:
    interfaces:
      - name: bond1
        type: bond
        state: up
        ipv4:
          enabled: false
        link-aggregation:
          mode: 802.3ad
          options:
            miimon: "150"
          port:
            - eno3
            - eno4
```

### 2) Dedicated OVS bridge

```yaml
apiVersion: nmstate.io/v1
kind: NodeNetworkConfigurationPolicy
metadata:
  name: br-vmdata
spec:
  nodeSelector:
    node-role.kubernetes.io/worker: ""
  desiredState:
    interfaces:
      - name: br-vmdata
        description: Dedicated OVS bridge for VM VLANs on bond1
        type: ovs-bridge
        state: up
        bridge:
          allow-extra-patch-ports: true
          options:
            stp: false
            mcast-snooping-enable: false
          port:
            - name: bond1
```

Keep bond and bridge definitions coherent—prefer one NNCP per logical change
set rather than scattering the same interface across many policies.

### 3) Bridge mapping

```yaml
apiVersion: nmstate.io/v1
kind: NodeNetworkConfigurationPolicy
metadata:
  name: ovs-bridge-mapping-physnet-br-vmdata
spec:
  nodeSelector:
    node-role.kubernetes.io/worker: ""
  desiredState:
    ovn:
      bridge-mappings:
        - localnet: physnet-vmdata
          bridge: br-vmdata
          state: present
```

By default, a localnet named `physnet` is already mapped to `br-ex`. That is how
you attach a VM to the machine network segment when that is intentional. For
dedicated VM data, use your own mapping name consistently in every CUDN that
shares the bridge.

### 4) Cluster User Defined Network per VLAN

```yaml
apiVersion: k8s.ovn.org/v1
kind: ClusterUserDefinedNetwork
metadata:
  name: localnet-1924
spec:
  namespaceSelector:
    matchLabels:
      vlan-1924: ""
  network:
    topology: Localnet
    localnet:
      role: Secondary
      physicalNetworkName: physnet-vmdata
      vlan:
        mode: Access
        access:
          id: 1924
      ipam:
        mode: Disabled
```

Label namespaces that should see the network (`vlan-1924: ""`), or match the
`default` namespace when every project should be able to consume it. The
controller creates a NAD in each selected namespace. Treat those NADs as owned
objects—edit the CUDN, not the generated NAD. Namespace deletion can block
until the CUDN selector no longer matches.

If you still maintain estates on the older pattern: one NAD per VLAN per
namespace (or in `default`), with `"topology": "localnet"` and the same
`physicalNetworkName`. On 4.22, prefer CUDN so VLAN intent and namespace access
live in one admin API.

### 5) Attach the VM

```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: ldap
  namespace: demo-ldap
spec:
  template:
    spec:
      domain:
        devices:
          interfaces:
            - name: nic-1924
              bridge: {}
              model: virtio
      networks:
        - name: nic-1924
          multus:
            networkName: localnet-1924
```

The namespace must be selected by the CUDN. The guest then sits on VLAN 1924 via
`physnet-vmdata` / `br-vmdata` without SNAT to the node IP—exactly the
“give me that VLAN” outcome VMware admins expect from a port group.

## Linux bridge: only when required

Default to OVS bridges and CUDN. Future networking investment is centered there.
Use a Linux bridge when you truly need capabilities the OVS/CUDN path does not
cover—most commonly **VLAN guest tagging (VGT)**, where 802.1Q tags must pass
into the guest for a virtual firewall or router. That choice costs you
User-Defined Network simplicity and the cleaner NAD lifecycle. If you do not
need trunked tags inside the guest, do not take the Linux bridge path “just in
case.”

## When to choose what

| Need | Prefer |
| ---- | ------ |
| Services / Routes only; IP can change on migrate | Default pod network (masquerade) |
| Tenant isolation, persistent VM IPs, overlapping subnets | Primary Layer2 UDN |
| Datacenter VLAN / provider L2 without node SNAT | Secondary localnet via CUDN |
| 802.1Q tags inside the guest (VGT) | Linux bridge (exception) |
| Highest NIC performance / hardware offload | SR-IOV (when hardware and ops model fit) |

## The SA takeaway

1. **Start with the pod network** when Kubernetes exposure is enough—and be
   honest about migration changing the pod IP.
2. **Use primary Layer2 UDN** when tenants need isolation and persistent guest
   addressing.
3. **Use CUDN localnet** when VMs must join real VLANs; map once per OVS
   bridge, define VLANs as CUDN, attach with Multus.
4. **Design the host first**—native, tagged, or dual-bond—so `br-ex` and
   `br-vmdata` match how the switch is trunked.
5. **Keep Linux bridge rare**—justify it with a concrete VGT or similar
   requirement.

Configure host networking and CUDNs through GitOps the same way you configure
the rest of the platform. For authoritative detail, start with the OpenShift
4.22 docs on
[multiple networks](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/multiple_networks/index),
[primary / user-defined networks](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/multiple_networks/primary-networks),
[secondary networks](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/multiple_networks/secondary-networks),
and
[OpenShift Virtualization networking](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/networking).

## Related posts

- [What's New in OpenShift Virtualization 4.22](/posts/openshift-virtualization-4-22-features/)
- [Hardening OpenShift Virtualization: Security Priorities That Matter First](/posts/openshift-virtualization-hardening-priorities/)
- [Storage Copy Offload for VMware Migrations to OpenShift Virtualization](/posts/mtv-storage-copy-offload-vmware/)

> Want help mapping these patterns into a landing zone or VMware migration
> design? Reach out to your Red Hat account team—or prove the dual-bond + CUDN
> path on a non-prod cluster before you standardize on it.
{: .prompt-tip }
