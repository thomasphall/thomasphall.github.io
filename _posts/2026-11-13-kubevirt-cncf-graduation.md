---
title: "KubeVirt Graduated. What Buyers Should Check"
description: >-
  KubeVirt graduated from the CNCF on November 10, 2026. That covers the
  upstream project. OpenShift Virtualization support still comes from the
  subscription.
date: 2026-11-13 07:50:00 -0600
categories: [OpenShift, Virtualization]
tags: [openshift, openshift-virtualization, security]
permalink: /posts/kubevirt-cncf-graduation/
social_title: |-
  KubeVirt graduated
  What buyers should check
social_label: OpenShift Virtualization
social_subtitle: Upstream project · Product support
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization.
{: .prompt-info }

The Cloud Native Computing Foundation (CNCF) announced
[KubeVirt's graduation](https://www.cncf.io/announcements/2026/11/10/cloud-native-computing-foundation-announces-kubevirt-graduation/)
on November 10, 2026, at KubeCon + CloudNativeCon North America in Salt
Lake City. The
[CNCF project page](https://www.cncf.io/projects/kubevirt/)
records the maturity change six days earlier, on November 4.

A buyer will hear "graduated" and ask whether
[Red Hat OpenShift Virtualization](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/index)
just became a different product. It did not. Graduation is the
foundation's highest level for an upstream project. Your virtual
machines (VMs) still run on OpenShift Virtualization, on the
OpenShift version you installed and with the subscription that supports it.

This is a design-review map for that conversation, based on the
November 10 announcement and Red Hat's
[graduation post](https://www.redhat.com/en/blog/kubevirts-cncf-graduation-recognizes-decade-community-work-and-years-production)
the same day. It is not a feature list for
[OpenShift Virtualization 5.0](/posts/openshift-virtualization-5-0-features/).

## What the foundation actually did

KubeVirt's first commit was on April 27, 2016. Red Hat started the project
that year so a Kubernetes cluster could run VMs through custom resources
and controllers, without a second control plane. The CNCF path after
that is short:

| Date | What changed |
| ---- | ------------ |
| September 6, 2019 | Accepted into the CNCF Sandbox |
| 2020 | OpenShift Virtualization became generally available, the year after the sandbox acceptance |
| April 19, 2022 | Moved to Incubating |
| July 2023 | KubeVirt v1.0 |
| March 2026 | v1.8, at the first in-person KubeVirt Summit |
| November 4, 2026 | Graduated, on the CNCF project page |
| November 10, 2026 | Announced at KubeCon NA |

The dates through Incubating come from the project page. The v1.0 date
and the OpenShift Virtualization general-availability year are Red Hat's
account. The March 2026 summit line and the graduation requirements come from
the CNCF announcement.

To graduate, the project completed a third-party security audit,
established a formal steering committee, and adopted the CNCF Code of
Conduct. The Technical Oversight Committee then reviewed production
adoption, engineering practices, governance, and security. That is the
bar. A press headline is not a second bar.

As of the November 10 announcement, the project cited 2,088
contributors across 520 organizations and 7,100 GitHub stars. A 2025
industry survey cited there said 86% of Kubernetes adopters were aware
of KubeVirt and 26% were using it in production. Named production users
include ByteDance, Cloudflare, CoreWeave, and NVIDIA. Swisscom's
August 2025 service, built on KubeVirt and Kube-OVN, is the scale
example in the announcement: 390 clusters, 2,100 worker nodes, and
160 TB of persistent storage.

Those estates are evidence the upstream project runs in production.
They are not a support statement for your cluster.

## Graduation and the subscription answer different questions

Red Hat's post is explicit: graduation applies to upstream KubeVirt, and
day-to-day operations for OpenShift Virtualization customers stay the
same. The independent assessment is the audit and the Technical
Oversight Committee review. The product lifecycle is unchanged.

| Question                                    | Graduation answers it                         | The product answers it                                      |
| ------------------------------------------- | --------------------------------------------- | ----------------------------------------------------------- |
| Is the upstream project mature?             | The CNCF graduated it                         | A feature's support status still depends on the applicable release notes   |
| Who supports this VM at 2 a.m.?             | The community, for upstream KubeVirt          | The OpenShift subscription and the published lifecycle     |
| Can I turn on the latest upstream capability? | The roadmap is public                       | The release notes for that OpenShift Virtualization version |
| Did the audit replace my review?            | A third-party audit was required to graduate | Hardening, roles, and CVE handling still apply             |

OpenShift Virtualization sits on two projects. KVM has been in the
Linux kernel since 2007. KubeVirt puts those VMs under the Kubernetes
API. Red Hat supports that combination as OpenShift Virtualization,
including in
[OpenShift Virtualization Engine](/posts/ove-vs-openshift-platform-plus/).
Which edition you buy is still a workload and subscription decision.
Graduation does not pick the SKU.

## The upstream roadmap is not a product release note

The announcement lists work that is planned or in progress. Treat each
item as a statement about upstream development, then check whether the OpenShift version you
will install has it, and at what support level.

- **Devices.** GPU claims through Kubernetes Dynamic Resource Allocation
  reached beta in KubeVirt v1.9. The same model is being extended to
  SR-IOV network devices, generic host devices, and CPUs so a VM can
  request them together. The GPU pool you can specify today is the one
  in
  [OpenShift Virtualization 4.22 on NVIDIA HGX](/posts/openshift-virtualization-nvidia-hgx/).
- **Confidential VMs.** AMD SEV and SEV-SNP are beta. IBM Secure
  Execution is generally available upstream. Intel TDX is alpha. Arm
  CCA is in development. Contributors are exploring attestation through
  Trustee, from the Confidential Containers project. The product shape
  of that idea is
  [Confidential AI on OpenShift: TEEs, GPUs, and Trustee](/posts/confidential-ai-openshift-trustee-nras/).
- **Extensibility.** Structured plugins are alpha in v1.9.
- **Other hypervisors.** v1.8 added a Hypervisor Abstraction Layer. The
  community is working toward out-of-tree alternatives to KVM, including
  Cloud Hypervisor, OpenVMM, and Firecracker.

Red Hat's post makes the same distinction: those efforts are at different
stages, and availability in OpenShift is decided in product releases.
A design that needs DRA GPUs, TDX, or a non-KVM hypervisor has to cite
the release notes for the version under contract. "KubeVirt graduated"
is not that citation.

The same distinction applies to security: the graduation audit is one input.
It does not retire
[Hardening OpenShift Virtualization: First Priorities](/posts/openshift-virtualization-hardening-priorities/)
or a feature-gate review such as
[CVE-2026-13434: Audit HCO Feature Gates as Code](/posts/cve-2026-13434-hco-feature-gates/).

## Takeaways for solutions architects

Use the announcement for what it measures, and the release notes for
what you will run.

1. **Graduation is a project level.** Sandbox in 2019, Incubating in
   2022, Graduated on November 4, 2026, announced November 10.
2. **The support statement is the subscription.** Day-to-day operations
   for OpenShift Virtualization customers do not change because the
   upstream project graduated.
3. **Quote the announcement's numbers as of November 10.** Contributor
   dashboards move. The audit, the steering committee, and the
   Technical Oversight Committee review are the durable part.
4. **Upstream adopters and OpenShift customers are different lists.**
   Swisscom on KubeVirt is not your OpenShift estate.
5. **The roadmap is not a feature you can open a ticket on.** GPU DRA,
   confidential VM stages, plugins, and alternate hypervisors ship in
   OpenShift only when a product release says so.
6. **Keep the existing review.** Hardening, roles, and feature gates
   are still yours. The third-party audit does not replace them.

Before a steering committee treats graduation as a migration
milestone, write down the OpenShift version, the OpenShift
Virtualization version, and the release-note status of every capability
the application owner asked for.

> Want help separating the KubeVirt roadmap from the OpenShift
> Virtualization release you will install? Work with your Red Hat
> account team and hold the design to that version's release notes.
{: .prompt-tip }

## Related posts

- [OpenShift Virtualization 5.0: The Updates That Matter](/posts/openshift-virtualization-5-0-features/)
- [OVE vs OpenShift Platform Plus: The SKU Choice](/posts/ove-vs-openshift-platform-plus/)
- [OpenShift Virtualization 4.22 on NVIDIA HGX](/posts/openshift-virtualization-nvidia-hgx/)
- [Confidential AI on OpenShift: TEEs, GPUs, and Trustee](/posts/confidential-ai-openshift-trustee-nras/)

## Further reading

- [CNCF announces KubeVirt graduation](https://www.cncf.io/announcements/2026/11/10/cloud-native-computing-foundation-announces-kubevirt-graduation/)
- [KubeVirt project page](https://www.cncf.io/projects/kubevirt/)
- [KubeVirt's CNCF graduation](https://www.redhat.com/en/blog/kubevirts-cncf-graduation-recognizes-decade-community-work-and-years-production)
- [KubeVirt](https://kubevirt.io/)
- [OpenShift Virtualization 5.0 release notes](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/release-notes)
