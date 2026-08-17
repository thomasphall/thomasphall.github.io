---
title: "RHACS Still Applies: Securing OpenShift Virtualization Workloads"
description: >-
  Why Red Hat Advanced Cluster Security still matters when VMs run on
  OpenShift Virtualization—what ACS sees, which policies help, and where
  guest OS hardening remains a separate layer.
date: 2026-08-04 10:00:00 -0500
categories: [OpenShift, Virtualization, Security]
tags: [acs, openshift-virtualization, rhacs, security]
permalink: /posts/acs-openshift-virtualization/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization.
{: .prompt-info }

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
networking, and security context rules. From an SA conversation standpoint, that
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
already triage in ACS—now applied to the virtualization surface as well as to
your applications.

**Images that feed VMs.** Many VM boot disks arrive as container disks or other
image-backed artifacts. Image risk does not stop being relevant because the
consumer is a VM. If an insecure or outdated image is how you seed guests,
treating that path as outside ACS scope recreates a blind spot you already
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

The useful ACS conversation for OpenShift Virtualization is not “turn on every
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
typical restricted application pod. That is not a reason to disable ACS policy
cluster-wide. Identify platform-owned virt namespaces and service accounts,
allowlist known-good virtualization behavior narrowly, and keep application
namespaces under the stricter baseline. In customer language: policy noise from
CNV is a scoping problem, not proof that “security tools don’t work on VMs.”

## VM vulnerability visibility in RHACS 4.10 (Technology Preview)

Workload and configuration visibility is the durable ACS story for OpenShift
Virtualization today. RHACS is also extending that story into guest package
risk.

[RHACS 4.10](https://www.redhat.com/en/blog/announcing-red-hat-advanced-cluster-security-kubernetes-410)
introduces **Technology Preview** vulnerability management for virtual machines
running on OpenShift Virtualization. The intent is unified visibility: identify
and manage vulnerabilities for VMs in the RHACS console alongside containerized
workloads, instead of treating guest package risk as an entirely separate silo.

Be precise in customer conversations. This capability is a
[Technology Preview](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_security_for_kubernetes/4.10/html/operating/examine-images-for-vulnerabilities#scanning-virtual-machines_operate-examine-images-for-vulnerabilities)
feature—not GA, not covered by production SLAs, and not a substitute for a
mature guest patching program. Red Hat documents prerequisites and an in-guest
agent path so RHACS can index installed packages on supported RHEL VMs and match
them against known vulnerabilities. If you evaluate it, treat it as early unified
visibility for architecture and feedback—not as a finished checkbox for regulated
production estates.

For requirements, limitations, and setup detail, use the official
[Scanning virtual machines](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_security_for_kubernetes/4.10/html/operating/examine-images-for-vulnerabilities#scanning-virtual-machines_operate-examine-images-for-vulnerabilities)
documentation rather than tribal runbooks.

## Platform posture vs guest OS: keep the boundary clear

RHACS does not replace guest operating system hardening. Say that out loud in
every design review.

| Layer | What it covers | Typical tools / controls |
| ----- | -------------- | ------------------------ |
| Platform & workload | Cluster posture, images, virt-launcher and related configs, deployment policy, multi-cluster risk | RHACS, OpenShift RBAC/SCCs, Compliance Operator |
| Virtualization hardening | Who can migrate/console, device allowlists, storage cloning, network segmentation | RBAC, HyperConverged device allowlists, MultiNetworkPolicy |
| Guest OS | Patching, CIS/STIGs inside RHEL or Windows, identity, endpoint controls | Guest OS hardening programs (separate from CNV posture) |

ACS helps you observe and gate the **platform and Kubernetes/virt control plane
around the VM**. Guest antivirus, guest patch SLAs, and OS baselines inside the
VM remain necessary. That boundary matches the
[OpenShift Virtualization hardening](/posts/openshift-virtualization-hardening-priorities/)
digest: harden OpenShift and RHCOS first; treat guest OS hardening as its own
program.

The broader hybrid pattern still holds—**observe, prove, and gate**—as described
in
[platform and supply-chain security](/posts/openshift-security-platform-supply-chain/).
Virtualization does not rewrite that pattern; it extends the “observe” and
“gate” legs to a new workload type.

## Complementary controls, not substitutes

RHACS is strongest as part of a stack, not as a single tool that claims to
finish security:

- **Compliance Operator** helps prove the OpenShift platform itself against
  agreed baselines and produces evidence you can manage as Kubernetes objects.
- **OpenShift Virtualization hardening** reduces blast radius with RBAC, device
  allowlists, storage isolation, and network segmentation.
- **RHACS** keeps multi-cluster risk and workload policy continuous—including
  for virt-launcher-backed VMs—and, in Technology Preview, begins unifying guest
  package vulnerability visibility for supported VMs.

None of these replaces the others. Auditors and risk committees buy consistency
and evidence, not a single product logo.

## The SA takeaway

Lead with outcomes:

1. **ACS still applies** — OpenShift Virtualization VMs run as Kubernetes
   workloads; RHACS can still surface risk and enforce policy on that surface.
2. **Scope exceptions** — virt components may need allowances that look noisy;
   allowlist intentionally instead of disabling policy.
3. **Treat VM vuln management as Technology Preview** — useful emerging
   visibility in RHACS 4.10; not a production substitute for guest hardening.
4. **Keep guest OS work separate** — platform posture and guest posture are both
   required.

If you are already running RHACS for containers and enabling OpenShift
Virtualization, start the next conversation with a simple proof point: show a
virt-launcher workload in the same risk view as your applications, agree which
policies stay enforced in virtualization namespaces, and decide whether
Technology Preview VM scanning belongs in a non-production evaluation track.

For GPU-backed AI where the security story is TEE attestation rather than
deployment policy alone, see
[Confidential AI on OpenShift](/posts/confidential-ai-openshift-trustee-nras/).
If you are standing up Virtualization in a PoC so ACS has a virt surface to
observe, start with
[OpenShift Virtualization (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/post-installation/virtualization/)
and
[deploying virtual machines](https://openshift-ssa.github.io/openshift-poc/workloads/workload-virtual-machines/).

## Related posts

- [Platform and Supply-Chain Security for Regulated Hybrid Cloud](/posts/openshift-security-platform-supply-chain/)
- [Hardening OpenShift Virtualization: Security Priorities That Matter First](/posts/openshift-virtualization-hardening-priorities/)
- [Confidential AI on OpenShift: From CPU TEEs to NVIDIA GPUs and Trustee Attestation](/posts/confidential-ai-openshift-trustee-nras/)

> Want a deeper walkthrough for your environment? Reach out to your Red Hat
> account team—or evaluate the pattern on a non-prod OpenShift cluster first.
{: .prompt-tip }
