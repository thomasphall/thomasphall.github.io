---
title: "Virtualization Autopilot vs GitOps on OpenShift"
description: >-
  Developer Preview in 4.22: what virt-platform-autopilot should own versus
  OpenShift GitOps, and how annotations stop GitOps from fighting the
  controller.
date: 2026-09-09 16:00:00 -0500
categories: [OpenShift, Virtualization]
tags: [openshift, openshift-virtualization, gitops]
permalink: /posts/virt-platform-autopilot-vs-gitops/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization. Virtualization platform
> autopilot is a Developer Preview in OpenShift Virtualization 4.22. It is
> not a production landing-zone default.
{: .prompt-info }

Install
[OpenShift Virtualization](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/index)
on
[Red Hat OpenShift](https://www.redhat.com/en/technologies/cloud-computing/openshift)
and you still do not have a virtualization *platform*. You have an operator.
Load-aware balancing wants the descheduler. Density wants swap and a kubelet
shape. High availability wants Node Health Check plus a remediator. PCI
passthrough wants VFIO. None of that is a `VirtualMachine` YAML problem. It
is a “did anyone apply the documented adjacent config, and will they still
apply it after the next minor?” problem.

[Virtualization platform autopilot](https://developers.redhat.com/articles/2026/05/07/introducing-virtualization-platform-autopilot)
is the 4.22 Developer Preview that tries to take that adjacent config away
from the cluster administrator. The controller watches the
`HyperConverged` resource in `openshift-cnv`, renders the documented
baseline for *this* cluster, and reconciles it for the life of the
install—not once at day one.

That sounds like it collides with
[OpenShift GitOps](https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.20/).
It does, if GitOps keeps owning every `MachineConfig` the autopilot is about
to rewrite. It does not, if GitOps owns the *contract*—the annotation that
turns the autopilot on, the exceptions, and everything that is not a
virt-adjacent default.

This post is that split. It is not an enablement runbook. Product procedure
and the current feature list live in the
[Red Hat Developer article](https://developers.redhat.com/articles/2026/05/07/introducing-virtualization-platform-autopilot).
The fleet cousin is still
[GitOps should manage ACM, not the cluster](/posts/gitops-should-manage-acm/).

## What the autopilot is (and is not)

Autopilot is a controller, not a new API. There is no Autopilot custom
resource and no status field to scrape. Objects it manages are labeled
`platform.kubevirt.io/managed-by: virt-platform-autopilot`. If it is doing
its job you hear from Events and Prometheus only when a human has to
intervene.

It is also not the
[HyperConverged Operator](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/about)
itself. HCO already gives opinionated defaults *inside* OpenShift
Virtualization. Autopilot reaches *outside* that operator: descheduler,
swap MachineConfigs, CPU Manager, MetalLB, Migration Toolkit for
Virtualization (MTV), Cluster Observability, PCI passthrough. Soft
dependencies are the design: if the CRD is missing, the controller waits
and retries. It does not fail the Virtualization install because you have
not subscribed MTV yet.

The day-0 cousin is the Assisted Installer virtualization bundle: a
recommended operator set for disconnected and UI-driven installs. Autopilot
is the day-1/day-2 continuation of that idea. The bundle gets operators onto
the cluster. The controller keeps the recommended *configuration* of those
operators aligned with the release.

In 4.22 the autopilot is **off by default**. You opt in on
`HyperConverged/kubevirt-hyperconverged`:

```shell
oc annotate hyperconverged kubevirt-hyperconverged -n openshift-cnv \
  platform.kubevirt.io/autopilot="true"
```

`true` enables every feature the shipped controller knows. A
comma-separated list enables a subset. The Developer Preview article names
this surface:

| Annotation value            | What it is asking the controller to manage      |
| --------------------------- | ----------------------------------------------- |
| `true`                      | All included features                           |
| `prometheus-alerts`         | Autopilot-specific alerting rules               |
| `swap-enable`               | Swap on workers for higher VM density           |
| `descheduler-loadaware`     | Load-aware descheduling                         |
| `kubelet-cpu-manager`       | CPU Manager                                     |
| `pci-passthrough`           | PCI passthrough                                 |
| `mtv-operator`              | MTV                                             |
| `metallb-operator`          | MetalLB                                         |
| `observability-operator`    | Observability UI plugin                         |

Treat that table as the 4.22 Developer Preview contract, not as a promise
that every row is equally mature on your z-stream. Render first (below).
The upstream
[virt-platform-autopilot](https://github.com/openshift-virtualization/virt-platform-autopilot)
repository moves faster than the operator that ships in 4.22; do not cite
its README as the support statement for a cluster you just installed from
the catalog.

The product intent after General Availability is the sentence that should
change landing-zone reviews: **new clusters on by default; existing
clusters stay manual until someone opts in; administrators who want to keep
full manual control opt out with an annotation.** Design the GitOps
ownership now, even if you leave the annotation off in production until GA.

## Two owners, one cluster

Both GitOps and the autopilot can be “desired state.” They must not own the
same fields.

```text
Git (cluster repo)                         Autopilot controller

HCO annotation + exceptions                Rendered baseline
NetworkPolicy, storage, identity           Descheduler, swap, CPU Manager
Security policies / compliance             MTV / MetalLB / observability
        │                                          │
        v                                          v
┌───────────────────────────┐              ┌───────────────────────────┐
│ OpenShift GitOps          │              │ virt-platform-autopilot   │
│ (hub policy or spoke app) │              │ watches HyperConverged    │
└─────────────┬─────────────┘              └─────────────┬─────────────┘
              │                                          │
              └─────────────── live API ─────────────────┘
```

| Layer                         | Owner                         | Why                                                                                          |
| ----------------------------- | ----------------------------- | -------------------------------------------------------------------------------------------- |
| HCO `autopilot` annotation    | GitOps                        | That is the contract. A click in the console is not a landing zone.                          |
| Escape-hatch annotations      | GitOps                        | Organizational exceptions have to survive reconcile and upgrade.                             |
| Descheduler profile, swap MC  | Autopilot                     | Values are release-encoded and sometimes computed from node count or hardware.               |
| Tenant `NetworkPolicy`, ANP   | GitOps (cluster vs app repo)  | Same split as [network policies](/posts/openshift-network-policies/).                        |
| StorageClasses, CSI, IdP      | GitOps                        | Not virt-adjacent defaults. The autopilot does not pick your array.                          |
| `VirtualMachine` CRs          | Application repo / tenants    | Workload, not platform.                                                                      |
| Designed NHC / FAR fence      | GitOps, then opt the object out | Do not let a Developer Preview overwrite [gray-failure HA](/posts/openshift-virt-gray-failure-ha/). |

The anti-pattern is committing the YAML the debug endpoint would have
rendered, then wondering why OpenShift GitOps and the controller thrash
after an upgrade. The autopilot’s job *is* to change that YAML when the
documented default changes. GitOps that insists on byte-for-byte equality
is fighting the feature.

## What GitOps should still own

Autopilot is convention over configuration for *virtualization platform
tuning*. It is not a replacement for a cluster repository.

Keep GitOps on:

- **Identity, ingress, and registry.** Autopilot will not stand up your
  IdP or pin the internal registry to PVCs.
- **Storage classes and snapshot classes.** Live migration still needs RWX
  block from a certified CSI. That choice stays in the
  [storage performance](/posts/openshift-storage-performance/)
  conversation.
- **Network attachment and NMState.** Secondary networks, localnet, and
  UDN remain a GitOps-shaped design; see
  [OpenShift Virtualization networking](/posts/openshift-virtualization-networking/).
- **Security posture.**
  [Red Hat Advanced Cluster Security for Kubernetes (RHACS)](/posts/acs-openshift-virtualization/)
  policies, Compliance Operator, and the virt-handler RBAC blast radius do
  not become “the controller will get to it.” Start from
  [hardening priorities](/posts/openshift-virtualization-hardening-priorities/).
- **Workload CRs.** InstanceTypes and golden-image DataVolumes can live in
  git. Running VM spec is a product decision; do not pretend the autopilot
  authors tenant YAML.

On a fleet, the same instinct as
[GitOps should manage ACM](/posts/gitops-should-manage-acm/)
applies. OpenShift GitOps on the hub should sync a
[Red Hat Advanced Cluster Management for Kubernetes (RHACM)](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/2.16/)
policy that stamps the HCO annotation onto clusters labeled for
virtualization. Do not ApplicationSet the swap `MachineConfig` to every
spoke. If the controller exists to compute that object, the hub’s job is
to turn the controller on—not to re-implement it in Kustomize.

## Escape hatches, not a second CRD

The controller uses a patched-baseline loop: render the documented default,
apply in-memory overrides from annotations, then server-side apply. Four
hatches keep GitOps in the loop without a new CRD. Put the annotations in
git. That is the whole GitOps story.

**JSON patch** when you want the object but one field is yours. The live
object (and the Git manifest that created it) carries
`platform.kubevirt.io/patch`. Autopilot applies the patch on top of its
baseline each reconcile:

```yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  name: 90-worker-swap-online
  annotations:
    platform.kubevirt.io/patch: |
      [
        {
          "op": "replace",
          "path": "/spec/config/systemd/units/0/contents",
          "value": "..."
        }
      ]
```

**Field masking** when GitOps or a human must own a path and the rest of
the resource can stay managed. `platform.kubevirt.io/ignore-fields` is a
comma-separated list of JSON pointers. Use it to stop edit wars on
`HyperConverged` fields you already tune:

```yaml
apiVersion: hco.kubevirt.io/v1beta1
kind: HyperConverged
metadata:
  name: kubevirt-hyperconverged
  namespace: openshift-cnv
  annotations:
    platform.kubevirt.io/ignore-fields: >-
      /spec/liveMigrationConfig/parallelMigrationsPerCluster,/spec/featureGates/enableCommonBootImageImport
```

**Per-resource unmanaged** when you need the whole object. Set
`platform.kubevirt.io/mode: unmanaged`. GitOps or `oc` then owns that
object with no further reconcile from the autopilot.

**Never create it** when even first render is wrong for the site. On the
HCO, `platform.kubevirt.io/disabled-resources` is a YAML list of kind /
name / namespace, with globbing. That is how you keep a Developer Preview
descheduler profile off a cluster whose `KubeDescheduler` is already a
designed object.

```yaml
apiVersion: hco.kubevirt.io/v1beta1
kind: HyperConverged
metadata:
  name: kubevirt-hyperconverged
  namespace: openshift-cnv
  annotations:
    platform.kubevirt.io/disabled-resources: |
      - kind: KubeDescheduler
        name: cluster
```

If `kubevirt_autopilot_paused_resources` lights up, you have an edit loop.
Fix the ownership annotation; do not add a syncwave and hope.

## Dry-run before you annotate

The preview ships a debug endpoint on the controller. Port-forward and
render before you opt in:

```shell
oc port-forward -n openshift-cnv deploy/virt-platform-autopilot 8081:8081
curl http://localhost:8081/debug/render
curl 'http://localhost:8081/debug/render?only-installed=true' | oc diff -f -
```

`only-installed=true` drops assets whose CRDs are not on the cluster, so
`oc diff` is not a wall of missing-type noise. Read the rendered
`KubeDescheduler` and MachineConfigs the way you would read a GitOps PR.
If the diff is a surprise, the annotation should not be `true` yet. Enable
a named subset, or disable the resource, or leave the feature off.

After enablement, `oc describe hyperconverged -n openshift-cnv` is the
event stream. Metrics to keep on a dashboard if you evaluate this at all:
`kubevirt_autopilot_compliance_status`,
`kubevirt_autopilot_customization_info`,
`kubevirt_autopilot_missing_dependency`, and
`kubevirt_autopilot_paused_resources`.

Turning a feature off stops management. It does not roll the cluster back.
MachineConfigs you already accepted still need an explicit delete and an
MCO drain. That is a landing-zone implication: subset enablement is
cheaper than `true` followed by cleanup.

## When GitOps stays in the driver's seat

Leave the autopilot off—or disable the colliding resources—when:

- You already GitOps a descheduler profile, swap layout, or CPU Manager
  kubelet that is *the* design, not a first-pass default.
- Node Health Check and Fence Agents Remediation are a written HA design,
  not “install whatever the operator README suggests.” See
  [Fence Gray Host Failures](/posts/openshift-virt-gray-failure-ha/).
- The estate is regulated and every node-touching object must exist in git
  *as rendered*, with a human change ticket when the YAML moves. Autopilot
  will move it. That is the feature.
- You are on production. Developer Preview is an evaluation on a non-prod
  cluster that already has
  [OpenShift Virtualization](https://openshift-ssa.github.io/openshift-poc/post-installation/virtualization/)
  and
  [OpenShift GitOps](https://openshift-ssa.github.io/openshift-poc/post-installation/openshift-gitops/)
  from the PoC sequence.

A compact or two-node edge cluster is not automatically a no. It is a
reason to render first. Swap, descheduler eviction limits, and remediation
operators are easy to over-fit on a three-node lab and then copy to a
constrained site. Form factor still comes before fleet defaults—see
[OpenShift edge architectures](/posts/openshift-edge-architectures/).

## The solutions architect takeaway

1. **Autopilot owns documented virt-adjacent defaults** — descheduler,
   swap, CPU Manager, and the other named features. GitOps owns the HCO
   annotation that allows that, plus identity, storage, network, and
   security.
2. **Do not GitOps the rendered MachineConfig** — you will fight the next
   z-stream. GitOps the patch, the ignore list, or `unmanaged`.
3. **Render and `oc diff` before `true`** — subset enablement on a non-prod
   cluster; full `true` is a later conversation.
4. **Fleet stamps the contract** — RHACM policy on virt-labeled clusters
   enables the controller. It does not re-implement the controller.
5. **Call Developer Preview by name** — off by default in 4.22; plan for
   GA default-on for *new* clusters so the ownership split is already in
   git.

If a non-prod cluster already runs Virtualization and GitOps, the next
proof is small: port-forward, render, diff, then annotate a subset such as
`descheduler-loadaware,prometheus-alerts`. Leave HA remediations and
storage classes in the cluster repo. Pair this evaluation with
[What's New in OpenShift Virtualization 4.22](/posts/openshift-virtualization-4-22-features/)
and the
[getting-started PoC sequence](/posts/getting-started-openshift-poc/).

## Related posts

- [GitOps Should Manage ACM, Not the Cluster](/posts/gitops-should-manage-acm/)
- [What's New in OpenShift Virtualization 4.22](/posts/openshift-virtualization-4-22-features/)
- [Fence Gray Host Failures on OpenShift Virtualization](/posts/openshift-virt-gray-failure-ha/)
- [How to Get Started with an OpenShift PoC](/posts/getting-started-openshift-poc/)

> Want help splitting virt-platform-autopilot from an existing GitOps
> cluster repo? Reach out to your Red Hat account team—or render and
> `oc diff` the controller on a non-prod cluster before you annotate
> `true`.
{: .prompt-tip }

## Further reading

- [Introducing virtualization platform autopilot](https://developers.redhat.com/articles/2026/05/07/introducing-virtualization-platform-autopilot)
- [virt-platform-autopilot (upstream)](https://github.com/openshift-virtualization/virt-platform-autopilot)
- [OpenShift Virtualization 4.22](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/index)
- [Red Hat OpenShift GitOps 1.20](https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.20/)
- [OpenShift Virtualization (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/post-installation/virtualization/)
- [OpenShift GitOps (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/post-installation/openshift-gitops/)
- [Workload Availability (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/post-installation/workload-availability/)
