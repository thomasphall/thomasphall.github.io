---
title: "RHACS for OpenShift Virtualization Workloads"
description: >-
  Why RHACS still matters for VMs on OpenShift Virtualization—what RHACS
  sees, which policies help, and where guest OS hardening remains a
  separate layer.
date: 2026-08-04 10:00:00 -0500
categories: [OpenShift, Security]
tags: [openshift, openshift-virtualization, security, acs]
permalink: /posts/acs-openshift-virtualization/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization.
{: .prompt-info }

**November 24, 2026 update.** RHACS 5.0 supports guest package vulnerability scanning for eligible RHEL 8, 9, and 10 VMs on secured clusters running OpenShift Virtualization. Verify the cluster pairing and enable VSOCK on both the cluster and each scanned VM. Red Hat lists x86_64 as the tested architecture. [RHACS support matrix and VM requirements](https://access.redhat.com/kb/7045053).

When virtual machines land on
[Red Hat OpenShift](https://www.redhat.com/en/technologies/cloud-computing/openshift),
a familiar assumption shows up in architecture reviews: *we are back in the VM
world, so our container security stack no longer applies.* That framing is
convenient—and wrong.

[OpenShift Virtualization](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/index)
runs each VM as a Kubernetes workload. The guest still needs its own hardening
program, but the platform surface around that guest—pods, images, policies,
misconfigurations that widen host-to-guest blast radius—is still in the
Kubernetes security plane. That is exactly where
[Red Hat Advanced Cluster Security for Kubernetes (RHACS)](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_security_for_kubernetes/)
earns its keep.

## What RHACS sees when VMs run on OpenShift

OpenShift Virtualization does not hide VMs from the cluster. For each virtual
machine, a virt-launcher pod runs the VM process under Kubernetes scheduling,
networking, and security context rules. From a solutions architect conversation standpoint, that
means VMs are not opaque hypervisor snowflakes sitting beside the platform. They
are first-class workloads with pods, images, volumes, and configuration that
security tooling can observe.

RHACS already helps teams answer three questions across clusters: *what is
running, how risky is it, and is policy enforced?* Those questions do not
disappear when the workload is a VM.

**Workloads and configuration risk.** Virt-launcher pods and related
virtualization components show up in the same multi-cluster inventory and risk
views you use for application Deployments. Capabilities, privileged paths, host
devices, and other host↔guest expansions are the kinds of signals platform teams
already triage in RHACS—now applied to the virtualization surface as well as to
your applications.

**Images that feed VMs.** Many VM boot disks arrive as container disks or other
image-backed artifacts. Image risk does not stop being relevant because the
consumer is a VM. If an insecure or outdated image is how you seed guests,
treating that path as outside RHACS scope recreates a blind spot you already
closed for containers.

**Consistency across hybrid estates.** The value of RHACS in hybrid designs is
operational sameness: one place to discuss risk whether the cluster is on-premises
or a managed OpenShift service. Virtualization on OpenShift should inherit that
consistency, not invent a second security console for “the VM clusters.”

For product context on how OpenShift Virtualization models VM security—unprivileged
virt-launcher pods, SCCs for the controller service account, and related
controls—see the
[OpenShift Virtualization security model](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/about)
documentation.

## Policies that matter when CNV is in play

The useful RHACS conversation for OpenShift Virtualization is not “turn on every
default and hope.” It is “keep the risk plane on, and make exceptions intentional.”

**Deployment-time policy** still helps. Teams use RHACS to warn or block
workloads that violate standards before risky configurations become permanent
estate furniture. Virtualization namespaces are not exempt from that discipline.
If a VM-related workload suddenly needs host devices, broad mounts, or other
high-impact settings, that should be a reviewed exception—not an unnoticed drift
from day-one posture.

**Runtime and visibility context** still helps. Unusual behavior on
virt-adjacent pods deserves the same curiosity you give suspicious application
pods. Consoles, migrations, and device attachments are high-value operations;
visibility around them supports the least-privilege story in
[hardening priorities for OpenShift Virtualization](/posts/openshift-virtualization-hardening-priorities/).

**Expect legitimate noise—and scope it.** OpenShift Virtualization components
may require capabilities and SCC allowances that look aggressive next to a
typical restricted application pod. That is not a reason to disable RHACS policy
cluster-wide. Identify platform-owned virt namespaces and service accounts,
allowlist known-good virtualization behavior narrowly, and keep application
namespaces under the stricter baseline. In customer language: policy noise from
CNV is a scoping problem, not proof that “security tools don’t work on VMs.”

## Guest vulnerability scanning in RHACS 4.10 and 5.0

RHACS 4.10 introduced guest scanning as a Technology Preview. For production
use with RHACS 5.0, check the secured cluster’s OpenShift version against the
support matrix and select a supported RHEL guest. Enable the cluster’s VSOCK
feature gate and set `spec.domain.devices.autoattachVSOCK: true` on the VM.
OpenShift Virtualization must be installed on the secured cluster. Central
can run on a separate cluster.

Verify that the VM’s installed packages appear in its scan report. Assign
findings to the team that patches the guest.
[Red Hat’s VM scanning requirements](https://access.redhat.com/kb/7045053).

## Platform posture vs guest OS: keep the boundary clear

RHACS does not replace guest operating system hardening. Say that out loud in
every design review.

| Layer | What it covers | Typical tools / controls |
| ----- | -------------- | ------------------------ |
| Platform & workload | Cluster posture, images, virt-launcher and related configs, deployment policy, multi-cluster risk | RHACS, OpenShift RBAC/SCCs, Compliance Operator |
| Virtualization hardening | Who can migrate/console, device allowlists, storage cloning, network segmentation | RBAC, HyperConverged device allowlists, MultiNetworkPolicy |
| Guest OS | Patching, CIS/STIGs inside RHEL or Windows, identity, endpoint controls | Guest OS hardening programs (separate from CNV posture) |

RHACS helps you observe and gate the **platform and Kubernetes/virt control plane
around the VM**. Guest antivirus, guest patch SLAs, and OS baselines inside the
VM remain necessary. That boundary matches the
[OpenShift Virtualization hardening](/posts/openshift-virtualization-hardening-priorities/)
digest: harden OpenShift and RHCOS first; treat guest OS hardening as its own
program.

The broader hybrid pattern still holds—**observe, prove, and gate**—as described
in
[platform and supply-chain security](/posts/openshift-security-platform-supply-chain/)
and the layer map in
[Security Tools Across the OpenShift Stack](/posts/openshift-security-tools-stack/).
Virtualization does not rewrite that pattern; it extends the “observe” and
“gate” legs to a new workload type.

## Complementary controls, not substitutes

RHACS is strongest as part of a stack, not as a single tool that claims to
finish security:

- **Compliance Operator** helps prove the OpenShift platform itself against
  agreed baselines and produces evidence you can manage as Kubernetes objects.
- **OpenShift Virtualization hardening** reduces blast radius with RBAC, device
  allowlists, storage isolation, and network segmentation. For the tenant vs
  admin vs secondary-network policy split, see
  [OpenShift Network Policies: Tenant, Admin, Secondary](/posts/openshift-network-policies/).
- **RHACS** keeps multi-cluster risk and workload policy continuous—including
  for virt-launcher-backed VMs. RHACS 5.0 also reports package vulnerabilities for supported guests.

None of these replaces the others. Auditors and risk committees buy consistency
and evidence, not a single product logo.

## The solutions architect takeaway

Lead with outcomes:

1. **RHACS still applies** — OpenShift Virtualization VMs run as Kubernetes
   workloads; RHACS can still surface risk and enforce policy on that surface.
2. **Scope exceptions** — virt components may need allowances that look noisy;
   allowlist intentionally instead of disabling policy.
3. **Check guest scanning eligibility.** Verify the RHACS and OpenShift versions, the RHEL guest release, and VSOCK configuration before relying on scan coverage.

4. **Keep guest OS work separate** — platform posture and guest posture are both
   required.

If you are already running RHACS for containers and enabling OpenShift
Virtualization, start the next conversation with a simple proof point: show a
virt-launcher workload in the same risk view as your applications, agree which
policies stay enforced in virtualization namespaces, and verify that a supported RHEL guest returns a package report in RHACS 5.0.

For GPU-backed AI where the security story is TEE attestation rather than
deployment policy alone, see
[Confidential AI on OpenShift](/posts/confidential-ai-openshift-trustee-nras/).
If you are standing up Virtualization in a PoC so RHACS has a virt surface to
observe, start with
[OpenShift Virtualization (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/configure-the-cluster/virtualization/)
and
[deploying virtual machines](https://openshift-ssa.github.io/openshift-poc/workloads-and-operations/virtual-machine-workloads/).

## Related posts

- [Security Tools Across the OpenShift Stack](/posts/openshift-security-tools-stack/)
- [OVE vs OpenShift Platform Plus: The SKU Choice](/posts/ove-vs-openshift-platform-plus/)
- [Hardening OpenShift Virtualization: First Priorities](/posts/openshift-virtualization-hardening-priorities/)
- [Supply-Chain Security for Regulated Hybrid Cloud](/posts/openshift-security-platform-supply-chain/)

> Want help applying this in your environment? Reach out to your Red Hat
> account team—or evaluate the pattern on a non-prod OpenShift cluster first.
{: .prompt-tip }
