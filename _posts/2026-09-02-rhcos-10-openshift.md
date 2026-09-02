---
title: "RHCOS 10 on OpenShift 4.22: What Changes"
description: >-
  RHCOS 10.2 is Technology Preview on OpenShift 4.22. What changes from
  RHCOS 9, how OSImageStream works, and how to test without delaying
  platform upgrades.
date: 2026-09-02 08:30:00 -0500
categories: [OpenShift]
tags: [openshift, bare-metal, security, gitops]
permalink: /posts/rhcos-10-openshift/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization.
{: .prompt-info }

Every OpenShift admin knows the calculus. A new
Red Hat Enterprise Linux CoreOS (RHCOS) ships with hardware enablement and
crypto you want. Adopting it has meant adopting it *everywhere*, on the same
weekend as the platform upgrade, with hardware certifications that do not
automatically follow. Teams delay the
[Red Hat OpenShift](https://www.redhat.com/en/technologies/cloud-computing/openshift)
minor so they can avoid the OS cutover—and miss capabilities they actually
need. The OS upgrade has been a cliff.

OpenShift Container Platform 4.22 is the start of the ramp. **RHCOS 10.2 is
Technology Preview.** The default node OS is still RHCOS 9, built from
Red Hat Enterprise Linux (RHEL) 9.8 packages. The Machine Config Operator
(MCO) grows an `OSImageStream` API so the payload can carry both streams.
A later OpenShift release is where mixed RHCOS 9 and RHCOS 10 nodes become
the supported transitional model—one MachineConfigPool at a time. That
split is the whole post: what 4.22 actually lets you do today, what changes
when a node boots RHEL 10, and how to evaluate it without trapping a
cluster you still intend to upgrade.

This is a solutions-architect planning note, not a substitute for
[Setting the RHCOS version in a cluster](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/machine_configuration/mco-image-streams).
Confirm that procedure and the
[4.22 release notes](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/release_notes/ocp-4-22-release-notes)
for the version you will install. If you are still sequencing the landing
zone, start with
[How to Get Started with an OpenShift PoC](/posts/getting-started-openshift-poc/)
and keep node config in GitOps the same way you keep everything else:
[GitOps Should Manage ACM, Not the Cluster](/posts/gitops-should-manage-acm/).

## Two timelines, one payload

| Question                         | OpenShift 4.22 today                                      | Destination Red Hat is shipping toward                         |
| -------------------------------- | --------------------------------------------------------- | -------------------------------------------------------------- |
| Default node OS                  | RHCOS 9 (RHEL 9.8 packages)                               | Fresh installs land on RHCOS 10                                |
| RHCOS 10                         | 10.2, Technology Preview, test clusters only              | GA node OS                                                     |
| Mixed RHCOS 9 and 10 in one cluster | **Not supported** in the 4.22 machine-config docs      | Supported transition, one MachineConfigPool at a time          |
| Upgrade from 4.22                | Nodes stay on RHCOS 9 unless you opt in                   | No forced OS migration on day one of the platform upgrade      |
| How you select the stream        | `OSImageStream` plus `TechPreviewNoUpgrade`               | Same API, without a one-way feature gate                       |

The product blog is describing the *operating model* that makes the cliff
go away. The 4.22 documentation is describing *what you can turn on now*.
Both are true. Do not design a production landing zone as if mixed pools
were already a supported day-2 knob.

> RHCOS 10 on 4.22 requires the `TechPreviewNoUpgrade` feature set. Enabling
> that feature set cannot be undone and **blocks minor version upgrades**.
> Use a disposable test cluster. Do not flip it on a cluster you still
> intend to take to 4.23.
{: .prompt-warning }

OpenShift Virtualization 4.22 lists dual-stream RHCOS—including live
migration between 9.x and 10.x workers—as Technology Preview. That is a
virt evaluation path, not a license to run mixed OS pools in production.
Treat it the same way as the rest of that TP list in
[What's New in OpenShift Virtualization 4.22](/posts/openshift-virtualization-4-22-features/).

## What RHCOS 10 actually is

RHCOS is still the immutable, `rpm-ostree`-managed node OS. It still ships
**inside the OpenShift release payload**, not as a DVD you install per
rack. Nodes still do not `dnf install`. The MCO still drains, writes
config, and reboots into a new tree. None of that goes away.

What changes is the **RHEL major** under that tree. RHCOS 9 tracks RHEL 9.
RHCOS 10 tracks RHEL 10. In 4.22 the TP stream is **RHCOS 10.2**; a debug
shell on a converted node shows `Red Hat Enterprise Linux release 10.2
(Coughlan)`. The payload exposes both as named streams on a cluster-scoped
`OSImageStream`:

```yaml
apiVersion: machineconfiguration.openshift.io/v1alpha1
kind: OSImageStream
metadata:
  name: cluster
spec:
  defaultStream: rhel-9   # or rhel-10
status:
  availableStreams:
    - name: rhel-9
    - name: rhel-10
```

`osImageStream: rhel-10` is **not** “install RHEL 10, ssh in, and manage
kubelet by hand.” It is the RHCOS image stream keyed off RHEL 10. RHEL
worker nodes, where they still exist, are a different compute model and
are not this API.

## What actually changes on the node

RHCOS 10 inherits the RHEL 10 kernel and userland. For an OpenShift
platform team, the deltas that matter are the ones that touch hardware,
crypto, and anything you layered or MachineConfigured on top of RHCOS 9.

| Area              | Why it shows up in an architecture review                                                                                          |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| Kernel 6.12       | Newer GPU, NIC, NVMe, and CXL enablement lands here first. Scheduler and reclaim behavior change on dense nodes.                   |
| Drivers           | NVIDIA GPU Operator, SR-IOV, NVMe/TCP, and SmartNIC offload need a lab pass on the new kernel, not a paper cert from RHCOS 9.      |
| Crypto            | RHEL 10 brings OpenSSL 3.5 and post-quantum algorithms (ML-KEM, ML-DSA). DEFAULT policy prefers PQC where the peer supports it.    |
| SELinux / systemd | Policy and unit behavior differ between majors. MachineConfigs that assume RHEL 9 paths or modules are the usual breakage.         |
| Image mode        | On-cluster layering (`MachineOSConfig`) is MachineConfigPool-scoped. Rebuild against **both** bases before you expand a migration. |
| Integrity         | RHEL 10 is the foundation for sealed image mode (composefs / fs-verity). That is the destination trust model, not a 4.22 day-2 toggle. |

The 4.22 payload also bumps Ignition, Butane, Afterburn, and
`coreos-installer`. Those tool versions apply to the 4.22 RHCOS line, not
only to the RHCOS 10 stream. Do not blame them on the major OS jump.

Crypto is the quiet one. Control-plane TLS has been growing post-quantum
support on the Go side of OpenShift independently of the node OS. RHCOS 10
is where the **host** libraries catch up. Hybrid ML-KEM should interoperate
and fall back; the failure mode to lab is the middle box, HSM, or
management appliance that *rejects* the new group instead of ignoring it.
That is a host-layer conversation next to Compliance Operator and File
Integrity Operator on the
[security tools stack](/posts/openshift-security-tools-stack/)—not a reason
to rewrite the workload supply chain.

Workloads still run in containers. A pod on UBI 9 does not magically
become RHEL 10 because the node did. Node OS and image UBI are separate
upgrade clocks. Keep them that way in the review.

## How you opt in on 4.22

Two supported shapes, both Technology Preview, both test-only.

**New cluster.** Set the feature set and the stream in
`install-config.yaml` so every machine is born on RHCOS 10:

```yaml
apiVersion: v1
featureSet: TechPreviewNoUpgrade
osImageStream: rhel-10
```

Valid `osImageStream` values are `rhel-9` and `rhel-10`. Omit it and you
get the 4.22 default: RHCOS 9.

**Existing 4.21.2+ or 4.22 cluster.** Enable `TechPreviewNoUpgrade` on the
`FeatureGate` named `cluster`, wait until `oc get osimagestreams/cluster`
shows a `rhel-10` stream, then point the MCO at it. Either set
`spec.defaultStream: rhel-10` on the `OSImageStream`, or patch every
MachineConfigPool—including custom ones:

```text
oc patch mcp worker --type merge -p '{"spec":{"osImageStream":{"name":"rhel-10"}}}'
oc patch mcp master --type merge -p '{"spec":{"osImageStream":{"name":"rhel-10"}}}'
```

The 4.22 docs are explicit: **do not leave a mixture**. If you move
workers, move masters and every custom pool in the same change window. You
can revert the stream to `rhel-9` on a test cluster; that is still a
drain/reboot cycle, not a free undo.

Boot images stay on RHCOS 9.x even after the running OS is 10.x. New nodes
boot 9, then the MCO upgrades them to 10. Update the boot image to a
current 9.x first, or scale-out looks like a mystery OS downgrade. That
procedure is
[Manually updating the boot image](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/machine_configuration/mco-update-boot-images).

On **hosted control planes**, the unit is a `NodePool`, not a classic
`oc patch mcp` in the hosted cluster’s API the way a standalone cluster
does it. Feature gates live on the `HostedCluster`. Do not copy the
standalone MCP commands into an HCP design and assume they apply. Form
factor first:
[hosted vs virtualized control planes](/posts/hosted-vs-virtualized-control-planes/).

On **Single Node OpenShift** there is one pool that matters. There is no
“move workers first.” Treat SNO as an all-or-nothing OS flip on that node,
which is why TP belongs in a lab SNO, not the plant-floor one. Edge form
factor still comes before OS experiments:
[OpenShift edge architectures](/posts/openshift-edge-architectures/).

## What to validate before you care about GA

Stand up a throwaway cluster. Enable the feature set. Put RHCOS 10 on it.
Then run the things that actually break on a kernel major.

1. **Hardware** — GPU Operator, SR-IOV VFs, NVMe/TCP or iSCSI + multipath,
   NIC offload, CXL if that is why you are here. The array-side MachineConfig
   patterns in
   [Pure FlashArray on Single Node OpenShift with NVMe/TCP](/posts/pure-flasharray-sno-nvme-tcp/)
   and
   [OpenShift Virtualization with Dell Unity over iSCSI](/posts/openshift-virt-dell-unity-iscsi/)
   are the right kind of test, not a `uname` screenshot.
2. **MachineConfig** — kernel arguments, sysctls, systemd units, and files
   that encode RHEL 9 assumptions. Butane/Ignition still apply; the
   *contents* may not.
3. **On-cluster layering** — every `MachineOSConfig` is pool-scoped. Rebuild
   the Containerfile against the RHCOS 10 base. Package names and module
   streams move between RHEL majors.
4. **Virtualization** — start, live-migrate, and storage-live-migrate a VM
   on the new kernel. KVM lives in this kernel; see
   [hardening priorities](/posts/openshift-virtualization-hardening-priorities/).
5. **SELinux** — watch `ausearch` / node denials on first boot of CSI,
   Multus, and virt-launcher, not only on `oc get nodes`.
6. **Crypto peers** — TLS and SSH from the node to BMCs, HSMs, and
   management planes. Prefer hybrid PQC; lab the appliance that hard-fails.
7. **Compliance** — re-run Compliance Operator and File Integrity Operator
   profiles. A CIS scan that was green on RHCOS 9 is not evidence on RHCOS
   10.

When mixed pools are GA, the evaluation loop the blog describes is the
right one: custom MachineConfigPool, one node, RHCOS 10 stream, validate,
then expand—or point that pool back at `rhel-9`. Same drain/cordon/reboot
risk model the MCO already uses. Until the product docs say mixed is
supported, that loop stays on a test cluster, and it stays all pools
together.

## What not to do

- **Do not delay the 4.22 platform upgrade to wait for RHCOS 10 GA.** The
  payload is designed so you can take the platform and keep RHCOS 9.
- **Do not enable `TechPreviewNoUpgrade` on anything you will still need
  to upgrade.** The name is the contract.
- **Do not treat the product blog’s “one pool at a time” as 4.22 support
  policy.** The machine-config docs still forbid mixed 9/10 nodes.
- **Do not GitOps `TechPreviewNoUpgrade` onto the production `FeatureGate`.**
  GitOps the *eventual* `OSImageStream` / MachineConfigPool choice. Keep
  the one-way feature gate off the cluster that has to live.
- **Do not assume container UBI follows the node.** Application images stay
  on the UBI you built them from until you rebuild them.

## The solutions architect takeaway

1. **4.22 is the rehearsal, not the cutover.** Default stays RHCOS 9
   (RHEL 9.8). RHCOS 10.2 is Technology Preview on a test cluster behind
   `TechPreviewNoUpgrade`.
2. **The cliff is the thing being removed.** A later OpenShift release is
   where mixed streams become a supported migration: stay on 9 through the
   platform upgrade, then move MachineConfigPools when hardware, layered
   images, and change control are ready.
3. **The value of 10 is the RHEL 10 kernel and crypto, not a new node
   operating model.** Immutable RHCOS, MCO, Ignition, and no `dnf` on the
   node all remain. Validate drivers, MachineConfigs, `MachineOSConfig`,
   KVM, and TLS peers.
4. **Host security still sits on this kernel.** Compliance Operator and
   File Integrity Operator stay the host layer in the
   [security tools stack](/posts/openshift-security-tools-stack/). A new
   major is when those scans earn their keep.
5. **Pick the stream in GitOps when it is GA; pick the lab cluster now.**
   Fresh TP installs set `osImageStream: rhel-10`. Existing test clusters
   patch `OSImageStream` or every MCP. Hosted control planes use
   `NodePool` / `HostedCluster`, not a copied standalone MCP command.

If the hardware that needs RHEL 10 drivers is already on the floor, stand
up a non-prod cluster and run the validation list. If it is not, take 4.22
on RHCOS 9 and keep the OS migration off the critical path.

## Related posts

- [How to Get Started with an OpenShift PoC](/posts/getting-started-openshift-poc/)
- [What's New in OpenShift Virtualization 4.22](/posts/openshift-virtualization-4-22-features/)
- [Security Tools Across the OpenShift Stack](/posts/openshift-security-tools-stack/)
- [Hosted vs Virtualized Control Planes on OpenShift 4.22](/posts/hosted-vs-virtualized-control-planes/)

> Want help planning an RHCOS 10 evaluation against a 4.22 landing zone?
> Reach out to your Red Hat account team—or build a disposable test
> cluster, enable the feature set there, and run hardware plus
> MachineConfig validation before anyone talks about production pools.
{: .prompt-tip }

## Further reading

- [Red Hat Enterprise Linux CoreOS 10 is coming to Red Hat OpenShift](https://www.redhat.com/en/blog/red-hat-enterprise-linux-coreos-10-coming-red-hat-openshift)
- [Setting the RHCOS version in a cluster (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/machine_configuration/mco-image-streams)
- [OpenShift Container Platform 4.22 release notes](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/release_notes/ocp-4-22-release-notes)
- [Installation configuration parameters (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/installation_configuration/installation-config-parameters-generic)
- [Enabling features using feature gates (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/nodes/nodes-cluster-enabling-features)
- [Manually updating the boot image (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/machine_configuration/mco-update-boot-images)
- [Image mode for OpenShift (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/machine_configuration/mco-coreos-layering)
- [Technology Preview Features Support Scope](https://access.redhat.com/support/offerings/techpreview)
- [Post-quantum cryptography in Red Hat Enterprise Linux 10](https://www.redhat.com/en/blog/post-quantum-cryptography-red-hat-enterprise-linux-10)
- [The road to quantum-safe cryptography in Red Hat OpenShift](https://www.redhat.com/en/blog/road-to-quantum-safe-cryptography-red-hat-openshift)
- [Machine Config (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/operations/machine-config/)
- [OpenShift PoC overview](https://openshift-ssa.github.io/openshift-poc/home/)
