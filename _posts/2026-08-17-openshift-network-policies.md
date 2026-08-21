---
title: "OpenShift Network Policies: Tenant, Admin, Secondary"
description: >-
  How NetworkPolicy, AdminNetworkPolicy, and MultiNetworkPolicy fit on
  OpenShift 4.22: who owns each control plane, evaluation order, and VM
  secondary nets.
date: 2026-08-17 08:00:00 -0500
categories: [OpenShift, Security]
tags: [openshift, security, networking, gitops]
og_image: /assets/img/og/openshift-network-policies.png
permalink: /posts/openshift-network-policies/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization.
{: .prompt-info }

Ask a platform team how they isolate traffic on
[Red Hat OpenShift](https://www.redhat.com/en/technologies/cloud-computing/openshift)
and the answer is often “we have NetworkPolicy.” That is necessary. It is not
the isolation story. On OpenShift Container Platform 4.22 with OVN-Kubernetes,
namespace-scoped `NetworkPolicy` sits in the middle of a three-tier ACL for the
pod network, and it does not see secondary NICs at all. Cluster admins have
`AdminNetworkPolicy` and `BaselineAdminNetworkPolicy`. Virtual machines and pods
on localnet, SR-IOV, or other extra attachments need `MultiNetworkPolicy`. Mixing
those APIs is how “we have NetworkPolicy” still leaves VMs on a flat VLAN—or
lets a tenant punch a hole through admin intent.

This post is a solution-architect field guide for who owns which control, what
traffic each one actually evaluates, and how that split lands in GitOps. It is
not a policy catalog. For how VM attachments land on the host, start with
[OpenShift Virtualization networking](/posts/openshift-virtualization-networking/).
Segmentation is also a
[virtualization hardening](/posts/openshift-virtualization-hardening-priorities/)
priority, not a bolt-on after go-live.

## Three APIs, not three spellings of NetworkPolicy

OpenShift has three complementary policy planes. `AdminNetworkPolicy` does not
replace tenant `NetworkPolicy`. `MultiNetworkPolicy` does not enforce on the
default cluster network.

| API | Who writes it | Scope | What traffic it covers |
| --- | ------------- | ----- | ---------------------- |
| `NetworkPolicy` | Namespace owners | Namespace | Default cluster network and primary user-defined networks |
| `AdminNetworkPolicy` / `BaselineAdminNetworkPolicy` | Cluster / network admins | Cluster | The same pod-network plane, evaluated in admin tiers |
| `MultiNetworkPolicy` | Typically cluster admins | Namespace object, bound to a secondary NAD | Secondary networks only—not the default cluster network, not a primary UDN |

If the workload’s extra NIC is the path that matters, a perfect `NetworkPolicy`
on the pod network will not save you. If the requirement is “tenants must not
override this,” a namespace `NetworkPolicy` will not save you either.

## NetworkPolicy: tenant microsegmentation

[`NetworkPolicy`](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/network_security/network-policy)
(`networking.k8s.io/v1`) is the right tool for east-west isolation *inside* a
project on the default or primary pod network. It is namespace-scoped. Once a
policy selects a pod, unmatched traffic is implicitly denied; additional policies
in that namespace are additive allows, not a priority stack.

A default-deny ingress policy is the usual starting point:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-by-default
  namespace: app-prod
spec:
  podSelector: {}
  policyTypes:
    - Ingress
  ingress: []
```

That object is not a complete design. DNS and the Kubernetes API must still be
reachable in a default-deny namespace, or the project simply fails closed in the
wrong way. Host-networked pods are generally outside this model. OpenShift 4.22
also ships deny-all `NetworkPolicy` objects in some platform namespaces (DNS and
Ingress operators among them); leave those alone.

On primary user-defined networks, `NetworkPolicy` microsegments *within* the UDN.
Create the policies after the UDN exists. Isolated primary UDNs have no
connectivity to each other; a `NetworkPolicy` cannot stitch that gap.

In GitOps terms, these objects belong in the **application** repository—written
by tenants, or by the platform team acting for them. They are not cluster-wide
guardrails.

## Admin Network Policy: intent tenants cannot override

[Admin Network Policy](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/network_security/admin-network-policy)
is how cluster and network administrators set rules before a namespace exists,
and keep tenants from undoing them. OVN-Kubernetes evaluates the pod-network
plane in three tiers:

1. **Tier 1 — `AdminNetworkPolicy` (ANP).** An **Allow** or **Deny** match stops
   evaluation. **Pass** hands the connection to the next tier.
2. **Tier 2 — `NetworkPolicy`.** Tenant rules. If nothing matches, evaluation
   continues.
3. **Tier 3 — `BaselineAdminNetworkPolicy` (BANP).** The cluster guardrail.

ANP is cluster-scoped. `priority` is **0–99**; the **lower** number wins. A
cluster supports at most **100** ANPs. Do not create two ANPs at the same
priority and hope for a deterministic winner. Rule order *inside* an ANP also
matters: higher in the list wins. Actions are **Allow**, **Deny**, and **Pass**.
Tenant `NetworkPolicy` cannot override Allow or Deny. Only Pass delegates.

BANP is a **cluster singleton named `default`**. Actions are **Allow** or
**Deny** only—there is no Pass. Use it as the floor when tenants write nothing,
or as the fallback after an ANP Pass.

The pattern that shows up in landing-zone conversations is the monitoring split.
Allow platform scrape of some tenants. Deny scrape of restricted tenants
(priority 5 beats priority 9). Pass scrape of `security: internal` tenants so
they opt in with their own `NetworkPolicy`; BANP denies that scrape unless they
do. Red Hat’s examples use a namespace named `monitoring` and labels such as
`security: restricted`—map those to the labels you actually stamp on projects.

Pass is the action people skip, and it is the one that makes the three-tier model
worth running:

```yaml
apiVersion: policy.networking.k8s.io/v1alpha1
kind: AdminNetworkPolicy
metadata:
  name: pass-monitoring
spec:
  priority: 7
  subject:
    namespaces:
      matchLabels:
        security: internal
  ingress:
    - name: pass-ingress-from-monitoring
      action: Pass
      from:
        - namespaces:
            matchLabels:
              kubernetes.io/metadata.name: monitoring
```

ANP and BANP can use `nodes` and `networks` peers for **egress** (northbound to
nodes or CIDRs). Cluster ingress from outside the cluster is not an ANP feature.
FQDN peers are not supported. A Deny to `0.0.0.0/0` without higher-priority
Allows will break API and DNS; do not learn that in production.

These objects belong in the **cluster** configuration repository under
[OpenShift GitOps](https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/),
not in tenant app repos. Cluster admins own them; tenants should not. Across
a fleet, that cluster-repo intent is usually an RHACM policy the hub places by
label, not an Argo Application per spoke—see
[GitOps should manage ACM, not the cluster](/posts/gitops-should-manage-acm/).

## MultiNetworkPolicy: secondary networks and VMs

[`MultiNetworkPolicy`](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/multiple_networks/secondary-networks)
(`k8s.cni.cncf.io/v1beta1`) is the NetworkPolicy mental model on a **secondary**
NIC. It applies to OVN-Kubernetes secondary and localnet networks, SR-IOV kernel
NICs, MacVLAN, IPVLAN, and Bond CNI over SR-IOV. It does **not** cover the
default cluster network. It does **not** cover a primary UDN. SR-IOV plus DPDK
is not a supported policy path—kernel NICs only.

Enable it on the cluster before you write objects:

```bash
oc patch network.operator.openshift.io cluster --type=merge \
  -p '{"spec":{"useMultiNetworkPolicy":true}}'
```

That sets `spec.useMultiNetworkPolicy: true` on
`Network.operator.openshift.io/cluster`. The CLI resource name is
`multi-networkpolicy`. Bind each policy to a `NetworkAttachmentDefinition` with
`k8s.v1.cni.cncf.io/policy-for: <namespace>/<network-name>`. Once a policy
selects a pod (or a virt-launcher that carries the VM), unmatched traffic on
that secondary attachment is denied.

```yaml
apiVersion: k8s.cni.cncf.io/v1beta1
kind: MultiNetworkPolicy
metadata:
  name: deny-by-default
  annotations:
    k8s.v1.cni.cncf.io/policy-for: virt-prod/vlan-100
spec:
  podSelector: {}
  policyTypes:
    - Ingress
  ingress: []
```

OpenShift 4.22’s backend is **nftables**; the iptables backend is gone. Existing
`MultiNetworkPolicy` objects keep working. You do not need a rewrite for that
change.

For OpenShift Virtualization, VLAN or localnet isolation is the underlay, not
the finish line. After CUDN or NAD attach—covered in
[OpenShift Virtualization networking](/posts/openshift-virtualization-networking/)—
`MultiNetworkPolicy` is the microsegmentation layer on that NIC. Pair it with MAC
spoof filtering from the
[hardening priorities](/posts/openshift-virtualization-hardening-priorities/)
digest. RHACS still observes the virt-launcher workload; it does not replace
this control. See
[RHACS for OpenShift Virtualization Workloads](/posts/acs-openshift-virtualization/).
To see whether ANP or `NetworkPolicy` is actually dropping packets, install
[Network Observability on OpenShift 4.22](/posts/network-observability-openshift/)
and look for `OVS_DROP_LAST_ACTION` after you enable `PacketDrop`.

## When to use what

| Need | Prefer |
| ---- | ------ |
| Default-deny inside an app namespace on the pod network | `NetworkPolicy` |
| Isolation that must exist before namespaces, and tenants cannot undo | `AdminNetworkPolicy` Allow or Deny |
| Tenants may opt in; otherwise deny | ANP Pass plus BANP named `default` |
| Guardrail if tenants write nothing | BANP named `default` |
| Monitoring may scrape some tenants, never others, internal tenants opt in | ANP Allow + ANP Deny + ANP Pass + BANP + tenant `NetworkPolicy` |
| VM or pod extra NIC on localnet, VLAN, or other secondary CNI | `MultiNetworkPolicy` (after enabling it) |
| North-south CIDR allow/deny from a namespace | OVN `EgressFirewall`—a different API, not a fourth NetworkPolicy |

`EgressFirewall` is the usual confusion at the edge of this conversation. It is
namespace-scoped north-south policy on OVN-Kubernetes. Do not treat it as another
`NetworkPolicy` kind, and do not expect it to microsegment a VM’s localnet NIC.

## The SA takeaway

1. **Three planes.** Tenant `NetworkPolicy`, admin ANP/BANP, and
   `MultiNetworkPolicy` for secondary NICs. Complementary, not interchangeable.
2. **Evaluation order.** ANP Allow/Deny stop the stack. Pass delegates to
   `NetworkPolicy`. BANP is the floor.
3. **Secondary nets are a different API.** Enable `useMultiNetworkPolicy`, bind
   to the NAD, then microsegment. The default pod-network policy will not do it.
4. **GitOps split.** ANP, BANP, and the enable flag live in the cluster repo.
   Tenant `NetworkPolicy` lives in the application repo. `MultiNetworkPolicy`
   usually rides with platform networking because it is tied to NAD names.

The broader observe / prove / gate pattern still sits above this:
[supply-chain security for regulated hybrid cloud](/posts/openshift-security-platform-supply-chain/).

## Related posts

- [How to Install Network Observability on OpenShift 4.22](/posts/network-observability-openshift/)
- [GitOps Should Manage ACM, Not the Cluster](/posts/gitops-should-manage-acm/)
- [OpenShift Virtualization Networking: Pod to Localnet](/posts/openshift-virtualization-networking/)
- [RHACS for OpenShift Virtualization Workloads](/posts/acs-openshift-virtualization/)

> Want help mapping tenant, admin, and secondary-network policy into a
> landing zone? Reach out to your Red Hat account team—or prove ANP/BANP
> plus a default-deny NetworkPolicy on a non-prod cluster first.
{: .prompt-tip }

## Further reading

- [Understanding network policy APIs (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/network_security/network-policy-apis)
- [Admin network policy (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/network_security/admin-network-policy)
- [Network policy (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/network_security/network-policy)
- [Configuring multi-network policy (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/multiple_networks/secondary-networks)
- [Networking (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/post-installation/networking/)
