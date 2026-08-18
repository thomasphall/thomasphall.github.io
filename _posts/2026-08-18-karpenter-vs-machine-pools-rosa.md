---
title: "Karpenter vs Machine Pools on ROSA HCP"
description: >-
  When Karpenter should own ROSA HCP compute versus machine pools, how it
  coexists with Cluster Autoscaler, and what self-managed OpenShift uses
  instead.
date: 2026-08-18 08:00:00 -0500
categories: [OpenShift]
tags: [openshift, karpenter, rosa, hosted-control-planes]
permalink: /posts/karpenter-vs-machine-pools-rosa/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization.
{: .prompt-info }

Machine pools are honest about what they do: they scale a *shape you already
picked*. On
[Red Hat OpenShift Service on AWS](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/)
that is a worker pool with an instance type, a size range, and often a Cluster
Autoscaler that adds or removes copies of that shape. The model works when the
workload is known. It becomes a tax when pending pods disagree about CPU,
memory, or how interruptible they are. You either over-provision a large common
denominator, or you proliferate pools until the cluster looks like a
spreadsheet.

[Red Hat build of Karpenter](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/cluster_administration/managing-compute-nodes-using-red-hat-build-of-karpenter)
on ROSA with hosted control planes (OpenShift 4.22 or later) is the other
control. It watches pods the scheduler marked unschedulable, provisions an
Amazon EC2 instance that matches those constraints, and consolidates nodes
when the work is gone. This post is a solution-architect split: what Karpenter
should own, what stays on machine pools, and what self-managed
[OpenShift](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/)
does instead. It is not an enablement runbook.

## What the Red Hat build actually is

Karpenter is a Kubernetes-native node autoscaler. The Red Hat build is that
project, hosted on ROSA, not an operator you park on worker nodes. The
controllers run in the
[hosted control plane](/posts/hosted-vs-virtualized-control-planes/), so there
is no extra Karpenter footprint competing with application pods. You can enable
it on an existing ROSA HCP cluster once the cluster is on 4.22. In OpenShift
Cluster Manager, the toggle is AutoNode; name the product Red Hat build of
Karpenter in architecture reviews.

The object you write is a `NodePool` (`karpenter.sh/v1`). Red Hat’s
`OpenshiftEC2NodeClass` wraps the upstream `EC2NodeClass`; NodePools reference
the `EC2NodeClass` through `nodeClassRef`. When you enable Karpenter, a default
`OpenshiftEC2NodeClass` appears with the hosted control plane’s OpenShift
version. That default class is immutable. Do not plan a design that starts
with “we will edit `default`.”

This surface is **ROSA with hosted control planes**. It is not ROSA classic. It
is not self-managed OpenShift Container Platform. If the cluster is not that
ROSA HCP 4.22 shape, skip to the self-managed section—do not install upstream
Karpenter and call it the Red Hat build.

Karpenter evaluates pending-pod constraints the scheduler already knows:
resource requests, node selectors, affinities, taints and tolerations, and
topology spread. It does not replace those APIs. It provisions compute that
can satisfy them.

## Who should own the shape

Cluster Autoscaler and Karpenter are easy to conflate because both “add
nodes.” They do not own the same decision.

| Control | Owns the instance shape? | What it scales | Use when |
| ------- | ------------------------ | -------------- | -------- |
| Red Hat build of Karpenter (`NodePool`) | Yes — from pending-pod constraints | Nodes that match those pods, then consolidates | Diverse, bursty, or right-size-sensitive compute you can interrupt or explicitly mark on-demand |
| ROSA machine pool | Yes — you picked the type when you created the pool | Replica count of that pool | Known, pinned, or interrupt-intolerant capacity |
| Cluster Autoscaler | No — it only counts copies of a predetermined pool or MachineSet | Replica count inside min/max | You already chose the shape and need elastic *count* |

Capacity type is a second axis, not a third autoscaler. Keep it in the same
review:

| Capacity type | What it means for the split |
| ------------- | --------------------------- |
| On-demand | Set `karpenter.sh/capacity-type` to `on-demand` when interruption is unacceptable. Do not assume the default is safe. |
| Spot | ROSA Karpenter docs warn that Spot is the default and that AWS can reclaim it. Fine for interruptible apps; wrong for the platform floor. |
| On-Demand Capacity Reservations (ODCR) | Karpenter can consume reserved on-demand capacity you already bought. That is still Karpenter picking *which* instance to launch into the reservation, not a reason to skip the interruptibility question. |
| Capacity Blocks for ML | Documented for reserved training windows. Treat it as a capacity type in the table, not as an ML architecture. |

Two more defaults belong in the same conversation. Nodes expire after 30 days
unless you change that behavior. Instance types must meet a **4 vCPU** floor.
`NodePool` `spec.replicas` / static capacity is not supported—Karpenter is not
a MachineSet with a replica field. If the requirement is “always keep twelve
of *this* type,” that is a machine pool.

## Coexistence, not a cutover

The Red Hat product blog is explicit: Karpenter and Cluster Autoscaler can run
in the same cluster. That is the migration path. Leave the machine pools that
must not move. Add a `NodePool` for the workloads that should. Do not schedule
a Friday “delete every worker pool” event.

**Move first.** Stateless services whose pending pods are the reason you keep
inventing instance types. Batch and CI that come and go. Anything you would
happily right-size every week if you had the time.

**Move last—or never.** Ingress, registry, and monitoring if a reclaim or a
Spot interruption would take the cluster’s face down with it. Workloads that cannot
tolerate node expiry. Families you already purchased as a reservation *and*
must keep as a named pool for procurement or support reasons.

The hosted control plane still upgrades on its own cadence. NodePools that
reference the default `OpenshiftEC2NodeClass` follow the control plane. For
independent worker versioning, use a non-default class with `spec.version`
pinned—out of scope here, but it is why “edit `default`” is the wrong instinct.
For how hosted clusters split control-plane and worker lifecycle, see
[hosted vs virtualized control planes](/posts/hosted-vs-virtualized-control-planes/).
Karpenter does not replace a fleet hub. If the question is many clusters, not
many instance types, start with
[edge form factor then fleet](/posts/openshift-edge-architectures/).

## What stays on machine pools

Write this list before anyone enables AutoNode:

- **Platform floor.** Nodes that must exist for the cluster to be operable
  even when no application pods are pending.
- **Interrupt-intolerant workloads.** If the app cannot survive Spot reclaim
  or a 30-day node expiry, either pin `on-demand` *and* prove disruption
  policy, or keep a machine pool.
- **Pinned families.** “This licensed or reserved shape, always,” including
  capacity you already bought as a pool rather than as a Karpenter selector.
- **Known steady headroom.** A small always-on worker pool is cheaper
  operationally than teaching every platform component to tolerate
  just-in-time nodes.

## Self-managed OpenShift: do this instead

On self-managed OpenShift Container Platform the supported analog is still
[Cluster Autoscaler plus Machine API](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/machine_management/applying-autoscaling).
You create compute `MachineSet`s for each shape you will run. A
`ClusterAutoscaler` sets cluster-wide limits; a `MachineAutoscaler` per
MachineSet sets min and max replica counts. The autoscaler adds or removes
*copies of that MachineSet*. It does not pick a new instance type per pending
pod.

That is the same split as ROSA, with a blunter API. Diverse, bursty,
mixed-constraint workloads still want many MachineSets (or they sit pending until
a human invents another). Known, interrupt-intolerant, pinned capacity still
wants a MachineSet that does not shrink to zero. Upstream Karpenter on
self-managed OpenShift is not the Red Hat build. Do not install it and tell
a regulated customer it is the ROSA feature. When they need Karpenter’s
shape-picking, the supported Red Hat answer today is ROSA HCP 4.22—or wait
until Red Hat ships an equivalent on the cluster they actually run.

## The control surface, in one object

A `NodePool` is the ROSA-side intent. This example forces on-demand and the
4 vCPU floor, and it binds to the system `default` EC2 node class. Apply it
only after Karpenter is already enabled; the docs cover IAM and the AutoNode
toggle.

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: apps-ondemand
spec:
  template:
    metadata:
      labels:
        autonode: "true"
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"]
        - key: karpenter.k8s.aws/instance-cpu
          operator: Gte
          values: ["4"]
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
```

The contrast on self-managed OpenShift is a `MachineAutoscaler` pointing at a
`MachineSet` you already defined: min/max replicas of a known shape, not a
new shape per pending pod. Do not set `spec.replicas` on a Karpenter
`NodePool`. That field is not the supported static-capacity path.

## The SA takeaway

1. **Machine pools own known shape; Karpenter owns pending-pod shape.** If
   you cannot name which workloads are which, do not enable AutoNode yet.
2. **Defaults are interruptible.** Spot and 30-day expiry are docs warnings,
   not trivia. On-demand is an explicit `NodePool` requirement.
3. **Coexist, then shrink pools.** Cluster Autoscaler and Karpenter can share
   a ROSA HCP cluster. Move stateless burst first; keep the platform floor.
4. **Self-managed stays on Cluster Autoscaler and MachineSets.** That scales
   replica count, not instance type. Upstream Karpenter is not the Red Hat
   build.
5. **HCP is the substrate, not the fleet hub.** Controllers live in the hosted
   control plane. Many clusters is still a form-factor-then-fleet problem.

If a ROSA HCP 4.22 cluster is already the landing zone, the next proof is
small: one on-demand `NodePool` for an interruptible app, machine pools left
for the floor. Enablement steps live in the
[ROSA Karpenter chapter](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/cluster_administration/managing-compute-nodes-using-red-hat-build-of-karpenter).
The
[July 2026 product blog](https://www.redhat.com/en/blog/introducing-red-hat-build-karpenter)
is the short capability list. For a hosted-cluster PoC shape, see
[OpenShift on OpenShift (Hosted Control Planes)](https://openshift-ssa.github.io/openshift-poc/installation/openshift-on-openshift/)
in the
[OpenShift PoC docs](https://openshift-ssa.github.io/openshift-poc/home/).

## Related posts

- [Hosted vs Virtualized Control Planes on OpenShift 4.22](/posts/hosted-vs-virtualized-control-planes/)
- [OpenShift Edge Architectures: Form Factor, Then Fleet](/posts/openshift-edge-architectures/)

> Want help splitting Karpenter NodePools from the machine-pool floor on a
> ROSA HCP cluster? Reach out to your Red Hat account team—or prove one
> on-demand NodePool beside an existing worker pool on a non-prod cluster
> first.
{: .prompt-tip }
