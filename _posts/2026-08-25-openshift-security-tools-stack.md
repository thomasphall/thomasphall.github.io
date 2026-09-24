---
title: "Security Tools Across the OpenShift Stack"
description: >-
  Layer-by-layer: how RHACS, the Compliance Operator, Conforma, and
  HashiCorp Vault integrate with OpenShift across hypervisor, VMs, pods,
  and supply chain.
date: 2026-08-25 15:00:00 -0500
categories: [OpenShift, Security]
tags: [openshift, security, openshift-virtualization, supply-chain, acs, gitops]
og_image: /assets/img/og/openshift-security-tools-stack.png
permalink: /posts/openshift-security-tools-stack/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization.
{: .prompt-info }

Security reviews for
[Red Hat OpenShift](https://www.redhat.com/en/technologies/cloud-computing/openshift)
often start with a product list: a scanner, a compliance dashboard, a vault, a
signing tool. That is the wrong first cut. OpenShift is a stack. A virtual
machine, a pod, and a container image are not three names for the same
workload. They sit on different isolation boundaries, and each boundary has a
tool that actually owns it.

The useful question is not *which security product should we buy?* It is
*which layer is this control for, and what still sits below or beside it?*
This post is a solutions-architect map of that stack on OpenShift Container
Platform 4.22—hypervisor and host, virtual machines, pods, and the supply
chain that feeds all three. The names that keep recurring are
Red Hat Advanced Cluster Security for Kubernetes (RHACS), the Compliance
Operator, Conforma, HashiCorp Vault, and
Red Hat Advanced Cluster Management for Kubernetes (RHACM). This is not an
install runbook, and it is not a substitute for the deep dives already on
this site. Those posts stay the source of detail. This one is the picture
you draw on the whiteboard before anyone argues about SKUs.

## The stack, not the catalog

| Layer                 | What it isolates                          | Tools that actually integrate here                                                                                        |
| --------------------- | ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| Hypervisor and host   | RHCOS kernel, KVM, node config            | Compliance Operator, File Integrity Operator, SELinux / sVirt                                                             |
| Virtual machines      | Guest OS plus the virt-launcher around it | OpenShift Virtualization hardening, [RHACS](/posts/acs-openshift-virtualization/), guest OS program                       |
| Pods                  | Containers, SCCs, east-west traffic       | RHACS, NetworkPolicy / AdminNetworkPolicy, [Network Observability](/posts/network-observability-openshift/), sandboxed containers |
| Supply chain          | What is allowed to build, sign, and run   | Red Hat Quay, Trusted Artifact Signer, Conforma, Trusted Profile Analyzer, [Lightwell](/posts/red-hat-lightwell-open-source-remediation/) |
| Secrets and identity  | Credentials in motion                     | [External Secrets Operator](/posts/external-secrets-vs-secrets-store-csi/), HashiCorp Vault, OIDC                         |
| Fleet                 | Same controls on every cluster            | [RHACM](/posts/acm-openshift-virtualization/), OpenShift GitOps                                                           |

A scanner that never sees virt-launcher pods will not save you when
OpenShift Virtualization is in scope. A CIS profile that never sees image
signatures will not save you when Friday’s unsigned build lands in
production. Pair the tool to the layer.

The observe / prove / gate pattern from
[platform and supply-chain security](/posts/openshift-security-platform-supply-chain/)
still holds. This map is where those three verbs attach.

## Hypervisor and host: KVM is not a side appliance

OpenShift Virtualization does not sit next to a separate hypervisor manager
the way a classic VMware estate sat next to ESXi and vCenter. The hypervisor
is **Kernel-based Virtual Machine (KVM)** in the
Red Hat Enterprise Linux CoreOS (RHCOS) kernel. OpenShift 4.22 still defaults
to RHCOS 9 (RHEL 9.8); RHCOS 10.2 is Technology Preview—see
[RHCOS 10 on OpenShift 4.22: What Changes](/posts/rhcos-10-openshift/).
Each VM is a QEMU process
inside a `virt-launcher` pod. `libvirt` runs in session mode as a non-root
user. SELinux **sVirt** labels isolate those QEMU processes from each other
and from the host. That is the security model in the
[OpenShift Virtualization documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/about):
unprivileged virt-launcher pods, restricted pod security, and
security context constraints (SCCs) on the `kubevirt-controller` service
account—not a privileged hypervisor daemon with a second console.

If someone asks for “hypervisor security tooling,” the honest answer on
OpenShift is: harden the host, then treat the virt control plane as
Kubernetes. Two Operators cover most of the host story.

The
[Compliance Operator](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/security_and_compliance/compliance-operator)
scans cluster and node configuration against supported profiles (CIS-oriented
OpenShift profiles, PCI-DSS, and others) using OpenSCAP. Results and
remediations are Kubernetes objects you can manage with GitOps. It
**assists** a compliance program; it does not replace an authorized auditor.
Use it first on the platform—before you argue about Virtualization
exceptions—as the
[hardening priorities](/posts/openshift-virtualization-hardening-priorities/)
digest already recommends.

The
[File Integrity Operator](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/security_and_compliance/file-integrity-operator)
runs AIDE on RHCOS nodes and reports unexpected file changes. That is host
integrity, not workload scanning. It answers *did someone change `/etc` or a
binary on the node?* RHACS answers a different question. The Operator is not
supported on hosted control planes; on ROSA HCP the host story lives on the
worker pool and the management cluster, not inside the guest control plane.

Leave nested virtualization disabled unless a guest truly needs it (WSL2
inside Windows is the usual example). Confirm CPU vulnerability mitigations
on workers. Spectre-class issues are not “solved by KVM” if the host kernel
still reports `Vulnerable`. Device pass-through, empty
`permittedHostDevices` allowlists, and closed feature gates belong in the
same host conversation—they expand what a guest can touch on the node.

Confidential computing is the exception that still lives at this layer: a
CPU trusted execution environment (Intel TDX, AMD SEV-SNP, ARM CCA) plus,
for GPU AI, NVIDIA Confidential Computing and
[Trustee attestation](/posts/confidential-ai-openshift-trustee-nras/).
That is hardware isolation of a confidential VM, not a replacement for
Compliance Operator profiles.

## Virtual machines: guest OS is a separate program

Once KVM is in play, two more surfaces appear, and they are easy to
conflate.

**Around the guest.** Each VM is still a Kubernetes workload. The
virt-launcher pod, its image, its SCC, its volumes, and its NetworkAttachment
show up in the same control plane as a Deployment. That is why
[RHACS](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_security_for_kubernetes/)
still applies. Policies that warn or block privileged paths, host devices,
and risky images are the same policies you already run for containers—scoped
so OpenShift Virtualization namespaces get intentional allowlists instead of
a cluster-wide mute. RHACS 4.10 adds Technology Preview guest package
scanning for supported RHEL VMs; treat that as emerging visibility, not a
production substitute for guest patching. Detail lives in
[RHACS for OpenShift Virtualization Workloads](/posts/acs-openshift-virtualization/).

**Inside the guest.** Patching, CIS/STIG baselines, identity, and endpoint
controls inside RHEL or Windows remain a guest operating system program.
RHACS, the Compliance Operator, and KubeVirt RBAC do not replace it. Say that
in every design review.

The highest-impact Virtualization controls after host hardening are still
least privilege on live migration, exec, and VNC; empty host-device
allowlists; no casual cross-namespace disk clones; and VLAN / localnet
segmentation with MultiNetworkPolicy. That is platform configuration, not a
new product. See
[Hardening OpenShift Virtualization: First Priorities](/posts/openshift-virtualization-hardening-priorities/).
For who owns `NetworkPolicy` versus `AdminNetworkPolicy` versus
`MultiNetworkPolicy` on VM secondary nets, see
[OpenShift Network Policies](/posts/openshift-network-policies/).

## Pods: admission, runtime, and the overlay

Application pods are the layer most security catalogs already describe. On
OpenShift the integration points are specific.

**Admission.** Restricted SCC and Pod Security Admission are the default
floor. RHACS adds deployment-time policy on top: warn or block images and
configurations that violate your standard before they become estate
furniture. Sandboxed containers (Kata) are the isolation step-up for
untrusted or multi-tenant pods—a lightweight VM per pod, which is the
hypervisor layer reused for containers rather than a different product.

**Runtime.** RHACS continues after the pod is scheduled: process, network,
and configuration risk across clusters. Unusual behavior on an application
pod and unusual behavior on a virt-adjacent pod deserve the same curiosity.
Scope platform-owned namespaces; do not turn the product off.

**Network.** OVN-Kubernetes is the default CNI on 4.22. Tenant
`NetworkPolicy`, cluster `AdminNetworkPolicy`, and `MultiNetworkPolicy` on
secondary NICs are three control planes, not one. Proof that a drop actually
happened is
[Network Observability](/posts/network-observability-openshift/)—eBPF flows
in the console, not a node `tcpdump`. Why the default CNI is the design, not
a bake-off: [OVN-Kubernetes](/posts/ovn-kubernetes-openshift-cni/).

A partner data plane does not get a bypass. A
[Confluent](https://www.confluent.io/) Kafka cluster, or AMQ Streams, on
OpenShift is still pods, images, and Service accounts. It consumes the same
signed images, the same Vault-delivered credentials, and the same
NetworkPolicy as everything else. Treat it as a workload class, not a
parallel security stack.

## Supply chain: sign, attest, verify, then scan

Cluster hardening is wasted if the thing you schedule was not what the
pipeline produced. The supply-chain layer is the gate in front of both pods
and VM container-disks.

[Red Hat Advanced Developer Suite - software supply chain (RHADS - SSC)](https://docs.redhat.com/en/documentation/red_hat_advanced_developer_suite_-_software_supply_chain/1.9/html-single/understanding_red_hat_advanced_developer_suite_-_software_supply_chain/index)
is the current name for what used to be Red Hat Trusted Application Pipeline.
It is a DevSecOps assembly, not a single Operator: Developer Hub templates,
OpenShift Pipelines, GitOps, and the signing/policy pieces below. You can
adopt the pieces without buying the whole suite; the suite is how Red Hat
packages a default SLSA-oriented path.

The pieces that matter in architecture reviews:

1. **Sign.** [Red Hat Trusted Artifact Signer (RHTAS)](https://docs.redhat.com/en/documentation/red_hat_trusted_artifact_signer/)
   is the on-prem Sigstore stack. Cosign signatures and attestations, a
   transparency log, and—as of RHTAS 1.4—a generally available Sigstore
   Policy Controller that can refuse unsigned images at admission.
2. **Attest and inventory.** [Red Hat Trusted Profile Analyzer (RHTPA)](https://docs.redhat.com/en/documentation/red_hat_trusted_profile_analyzer/3.0)
   holds SBOMs and vulnerability intelligence so “what is in this image”
   is an API, not a spreadsheet.
3. **Verify.** [Conforma](https://conforma.dev/) (formerly Enterprise
   Contract; the `ec` CLI and `EnterpriseContractPolicy` CRD keep the old
   names) checks that an image is signed and attested by a trusted build
   system before promote or deploy. Pipeline gate and admission gate, not
   a slide.
4. **Scan and store.** [Red Hat Quay](https://docs.redhat.com/en/documentation/red_hat_quay/)
   is the registry. Clair scanning in Quay plus RHACS image scanning is
   how “we scan” becomes “we know what is in the registry *and* what is
   running.” OpenShift already verifies signatures on *platform* release
   images during updates; your application images need the same discipline.
5. **Remediate when you cannot upgrade.** [Lightwell](/posts/red-hat-lightwell-open-source-remediation/)
   is the Red Hat and IBM path for pinned application libraries that have
   no safe major bump. Scanning without a remediation story is how CVE
   backlogs become theater.

Put signature and attestation checks in the pipeline *and* at admission.
One without the other is how an unsigned image still reaches a namespace
that “trusts the registry.”

## Secrets that every layer consumes

None of the layers above should read credentials from Git, from a container
disk, or from a tribal wiki. The
[External Secrets Operator for Red Hat OpenShift](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/security_and_compliance/external-secrets-operator-for-red-hat-openshift)
syncs from an external system of record into native Kubernetes `Secret`
objects. The usual system of record in mixed estates is
[HashiCorp Vault](https://developer.hashicorp.com/vault); AWS Secrets
Manager, Azure Key Vault, and IBM Cloud Secrets Manager are the same pattern
with a different `SecretStore`. Secrets Store CSI is the mount-at-runtime
alternative when you do not want the material in etcd. That comparison is
[External Secrets vs Secrets Store CSI](/posts/external-secrets-vs-secrets-store-csi/).

Identity in front of the cluster is OIDC. Keycloak is a common IdP; the
cluster should stay IdP-agnostic. GitOps (OpenShift GitOps / Argo CD) then
owns the *declaration* of stores, policies, and NetworkPolicy—not the secret
bytes.

## Fleet: one map, many clusters

A single cluster with this stack is a landing zone. An estate is a fleet.
[RHACM](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/2.16/)
is the hub for inventory, policy, and—when Virtualization is in scope—VM
lifecycle across clusters. RHACS is the hub for workload risk. They are not
duplicates: RHACM asks *is the cluster configured the way we declared?*
RHACS asks *what is running, and should it be?* GitOps should manage the
RHACM policy set, not a snowflake per cluster; see
[GitOps Should Manage ACM](/posts/gitops-should-manage-acm/).

Hybrid (on-premises, ROSA in AWS `us-east-2`, other managed OpenShift)
should change *where* the cluster lives, not *which* layers you skip.

## The solutions architect takeaway

Lead with the layer, then the tool:

1. **Host and hypervisor** — Compliance Operator and File Integrity Operator
   on RHCOS; KVM / sVirt / unprivileged virt-launcher as the virt security
   model; nested virt off; pass-through empty by default.
2. **VMs** — RHACS on the Kubernetes surface around the guest; Virtualization
   hardening for RBAC, devices, disks, and networks; guest OS hardening as
   its own program.
3. **Pods** — restricted SCC, RHACS deploy and runtime policy, OVN-Kubernetes
   NetworkPolicy / AdminNetworkPolicy, Network Observability for proof.
4. **Supply chain** — sign with RHTAS, inventory with RHTPA, verify with
   Conforma, scan in Quay and RHACS, remediate pinned libraries with
   Lightwell.
5. **Secrets and fleet** — Vault (or equivalent) plus External Secrets;
   RHACM and GitOps so the same map applies on every cluster.

If you are shaping a landing zone, start in non-production: enable a
Compliance Operator profile, connect RHACS, require signed images on one
pipeline, and show a virt-launcher pod in the same risk view as an
application Deployment. The rest of the catalog gets easier to place once
those four proofs exist.

PoC-sized day-2 starting points:
[External Secrets Operator](https://openshift-ssa.github.io/openshift-poc/configure-the-cluster/external-secrets-operator/),
[identity providers](https://openshift-ssa.github.io/openshift-poc/configure-the-cluster/configuring-identity-providers/),
[OpenShift GitOps](https://openshift-ssa.github.io/openshift-poc/configure-the-cluster/openshift-gitops/),
[OpenShift Virtualization](https://openshift-ssa.github.io/openshift-poc/configure-the-cluster/virtualization/),
and the
[OpenShift PoC overview](https://openshift-ssa.github.io/openshift-poc/home/).

## Related posts

- [Supply-Chain Security for Regulated Hybrid Cloud](/posts/openshift-security-platform-supply-chain/)
- [RHACS for OpenShift Virtualization Workloads](/posts/acs-openshift-virtualization/)
- [Hardening OpenShift Virtualization: First Priorities](/posts/openshift-virtualization-hardening-priorities/)
- [RHCOS 10 on OpenShift 4.22: What Changes](/posts/rhcos-10-openshift/)

> Want help mapping these tools onto a landing zone? Reach out to your Red
> Hat account team—or place one control on each layer of a non-prod
> OpenShift cluster first.
{: .prompt-tip }

## Further reading

- [OpenShift Virtualization security model (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/about)
- [Compliance Operator (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/security_and_compliance/compliance-operator)
- [File Integrity Operator (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/security_and_compliance/file-integrity-operator)
- [Red Hat Advanced Cluster Security for Kubernetes](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_security_for_kubernetes/)
- [Red Hat Trusted Artifact Signer](https://docs.redhat.com/en/documentation/red_hat_trusted_artifact_signer/)
- [Red Hat Trusted Profile Analyzer 3.0](https://docs.redhat.com/en/documentation/red_hat_trusted_profile_analyzer/3.0)
- [Understanding RHADS - SSC](https://docs.redhat.com/en/documentation/red_hat_advanced_developer_suite_-_software_supply_chain/1.9/html-single/understanding_red_hat_advanced_developer_suite_-_software_supply_chain/index)
- [Conforma](https://conforma.dev/)
- [External Secrets Operator for Red Hat OpenShift (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/security_and_compliance/external-secrets-operator-for-red-hat-openshift)
- [HashiCorp Vault](https://developer.hashicorp.com/vault)
