---
title: "GitOps Should Manage ACM, Not the Cluster"
description: >-
  When OpenShift GitOps should feed RHACM policies instead of applying CRs
  to every cluster, and when a field framework like AutoShift is the
  example—not the SKU.
date: 2026-08-19 06:00:00 -0500
categories: [OpenShift]
tags: [openshift, gitops, acm]
permalink: /posts/gitops-should-manage-acm/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization.
{: .prompt-info }

Install is the easy sentence. Someone still has to land operators, cluster
configuration, and the labels that decide which spokes get which of those
things. On
[OpenShift Container Platform](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/)
4.22 that work is GitOps either way. The split that actually changes the
landing zone is *what GitOps is allowed to touch.*

One model points
[OpenShift GitOps](https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.20/)
at every managed cluster and syncs Kubernetes objects onto those APIs.
The other points GitOps at the hub:
[Red Hat Advanced Cluster Management (RHACM) 2.16](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/2.16/)
policies, placements, and bindings. ACM then enforces the same intent on
spokes by label. This post is a solution-architect split for that choice. It
is not an enablement runbook, and it is not a tour of a GitHub README.

[ACM as the fleet control plane for OpenShift VMs](/posts/acm-openshift-virtualization/)
is the hub conversation. This is how desired state gets onto that hub after
the cluster exists.
[GitOps Zero Touch Provisioning](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/edge_computing/index)
is the install-time cousin; do not treat day-2 configuration as a second ZTP
pipeline you invent from scratch.

## Two delivery models

Both models can be “GitOps.” They do not own the same object.

```text
ApplicationSets to each spoke              GitOps feeds the hub

Git (per-cluster apps / CRs)               Git (PolicyGenerator + labels)
        │                                          │
        v                                          v
┌───────────────────────────┐              ┌───────────────────────────┐
│ Hub OpenShift GitOps      │              │ Hub OpenShift GitOps      │
│ ApplicationSets           │              │ Policy / Placement        │
└──┬────────────┬───────────┘              │ RHACM enforces            │
   │ push CRs   │ push CRs                 └──────────┬────────────────┘
   v            v                                     │ placement
┌────────┐  ┌────────┐                          ┌─────┴─────┐
│ Spoke  │  │ Spoke  │                          v           v
└────────┘  └────────┘                       ┌────────┐  ┌────────┐
                                             │ Spoke  │  │ Spoke  │
                                             └────────┘  └────────┘
```

| Model                           | What GitOps syncs                                | Who changes the spoke | Use when                                                        |
| ------------------------------- | ------------------------------------------------ | --------------------- | --------------------------------------------------------------- |
| ApplicationSets to each cluster | Apps and CRs onto spoke APIs                     | OpenShift GitOps      | Few clusters, heavy per-site drift, tenant application repos    |
| GitOps feeds ACM                | `Policy`, `Placement`, and bindings onto the hub | ACM governance        | A fleet of similar clusters, Platform Plus, compliance evidence |

The cluster-versus-application repository split from
[OpenShift network policies](/posts/openshift-network-policies/)
still applies inside both columns. Tenant `NetworkPolicy` stays in the
application repo. ANP, operators, and platform CRs stay in the cluster repo.
ACM policies are a *delivery mechanism* for the cluster-repo column across
many clusters. They are not a reason to put tenant apps into governance YAML.

Do not flatten a third path into this table.
[GitOpsCluster](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/2.16/html/gitops/gitops-overview)
registers managed clusters to an OpenShift GitOps instance so Argo CD can
deploy *applications* to those spokes. That is ACM helping GitOps reach
workloads. It is the opposite direction of GitOps managing ACM so ACM can
reach platform configuration. You can run both. Name which one you mean in
the design review.

## Why the hub should own day-2

A spoke is a bad system of record for fleet intent. ApplicationSets that
target every cluster make drift a per-cluster Argo problem: health is “did
this Application sync,” not “is this estate compliant.” ACM already has the
objects for that second sentence.
[Policy deployment](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/2.16/html/governance/policy-deployment)
puts configuration on the hub. Placement selects clusters. Compliance is
visible in the same console that already inventories the fleet.

That is why the ACM virtualization backup path is policy plus labels rather
than a Velero click on each cluster. The same instinct applies to operators
and platform CRs. If the hub is how you stop a VM, it should also be how you
prove ACS, logging, or GitOps itself is present on the clusters that need
them.

GitOps still matters. Someone has to create the `Policy` objects, and those
objects should not be clicked into the hub. OpenShift GitOps on the hub
syncs generated policy to ACM. ACM places it. The spoke never becomes the
Git remote for platform day-2.

## PolicyGenerator is the product primitive

Hand-writing `Policy` wrappers around every `Subscription` and `ConfigMap`
is how the model dies in review. ACM’s
[Policy Generator](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/2.16/html/governance/policy-deployment#policy-generator)
is the supported way to keep Git looking like Kubernetes. You commit native
manifests. A `PolicyGenerator` Kustomize plug-in wraps them into `Policy`,
`Placement`, and `PlacementBinding` resources on the hub.

The generator is not preinstalled in the OpenShift GitOps container image.
ACM documentation has you copy the plug-in from the RHACM application
subscription image into the GitOps repo-server and enable Kustomize alpha
plugins. That is a landing-zone implication, not trivia: on the hub, GitOps
that generates policy is not an unmodified OpenShift GitOps instance. Install and image-pin ACM
before you expect that repo-server to render policies. GitOps ZTP uses the
same generator family for site configuration; day-2 is the same primitive
after the cluster already exists.

A generator file is the control surface. This shape matches the ACM 2.16
example that wraps ordinary manifests and places them with a label selector:

```yaml
apiVersion: policy.open-cluster-management.io/v1
kind: PolicyGenerator
metadata:
  name: install-compliance-operator
policyDefaults:
  namespace: policies
  remediationAction: enforce
  placement:
    labelSelector:
      matchExpressions:
        - key: vendor
          operator: In
          values:
            - "OpenShift"
policies:
  - name: install-compliance-operator
    manifests:
      - path: compliance-operator.yaml
```

`compliance-operator.yaml` is a Namespace, OperatorGroup, and Subscription—
the same YAML you would apply to one cluster. The generator is what makes
that YAML a fleet object. Inform versus enforce is a policy field, not a
second GitOps tool. Dry-run and staged rollout belong here: inform first,
then enforce, then expand placement.

## Labels are the feature flag

Placement is how the hub answers “which clusters.” The honest UX for a
platform team is not forty ApplicationSets. It is labels on `ManagedCluster`
and ClusterSets: this spoke gets virtualization, that spoke gets ACS, the
sandbox set does not get production logging retention.

That is the same selector idea as
[ACM Virtualization](/posts/acm-openshift-virtualization/)
stamping `acm-virt-config` or `acm/cnv-operator-install`. The anti-pattern
is a unique Git overlay per cluster that reimplements placement in folder
names. Folders are fine for manifests the generator should wrap. They are a
poor substitute for ACM labels when the question is membership in a
capability set.

Version pins belong on the same axis. Operator subscriptions can follow a
channel, or they can require a CSV. Encode that as labels or as generator
patches—not as a one-off change in a spoke’s Argo Application. When you need
a canary, versioned ClusterSets (or a second placement) beat a Friday
edit of `main`.

## AutoShift is the worked example

[AutoShift v2](https://github.com/auto-shift/autoshiftv2) is an Apache-2.0
IaC framework that implements this model in one repository: OpenShift GitOps
manages RHACM; ACM policies—mostly PolicyGenerator directories—manage the
fleet. ClusterSet and per-cluster values become labels. Those labels turn
operators and platform components on and off. The catalog is the
[OpenShift Platform Plus](https://www.redhat.com/en/resources/openshift-platform-plus-datasheet)
shape this site already writes about: ACS, Ansible Automation Platform,
GitOps, Quay, OpenShift Data Foundation, Virtualization, MTV, External
Secrets, Pipelines, Developer Hub, Service Mesh, logging.

Treat it as a field framework, not a SKU. It is not a Red Hat product. There
is no GSS contract and no `docs.redhat.com` page. Releases are still
`0.0.x` while `main` moves. The project’s own badges have pinned OpenShift
4.20.x and ACM 2.17; this site’s product line is OpenShift 4.22 and ACM
2.16. Verify every operator version against the
[ACM support matrix](https://access.redhat.com/articles/7136928)
and the OpenShift version you actually run. Do not cite an AutoShift values
file as the source of truth for a supported pairing.

What is worth stealing even if you never clone the repo:

- GitOps on the hub owns ACM; ACM owns spokes.
- PolicyGenerator directories instead of hand-wrapped `Policy` YAML.
- Labels as the enablement API, with ClusterSet defaults and per-cluster
  overrides.
- OCI artifacts when Git is the wrong distribution path for disconnected
  hubs—prerendered policy, not a repo-server that must copy the generator
  plug-in at install time.
- Inform/dry-run before enforce.

What is *their* opinion, not a product requirement: Helm values composition,
one ApplicationSet discovering `policies/{stable,certified,community}`, and
a label vocabulary such as `acs: 'true'` plus `acs-version:`. That
vocabulary is convenient. It is not an ACM API. If you fork, you own the
fork.

A 10-module
[Showroom lab](https://github.com/auto-shift/autoshift-showroom)
covers the label flow, PolicyGenerator authoring, OCI publishing, and a
spoke. Use that for hands-on. Do not turn this post into a second copy of
their quick start.

## When to keep a cluster repo

The ApplicationSet-to-spoke model is not a failure. It is the right column
when the estate is small, the sites are unlike each other, or the objects
are tenant applications.

Keep a hand-rolled
[OpenShift GitOps](https://openshift-ssa.github.io/openshift-poc/post-installation/openshift-gitops/)
cluster repository when:

- You have a handful of clusters and the overlay *is* the design.
- Per-site networking, storage classes, or identity are the majority of
  Git—not a boolean “install ODF.”
- You already operate a kustomize factory with namespace folders and
  syncwaves, and ACM would only wrap the same unique trees.
- The objects are applications. Those still belong in an application
  repository, often with `GitOpsCluster` so the hub GitOps instance can
  target spokes.

You can still use PolicyGenerator for the shared subset: compliance
operator, cluster-wide ANP, External Secrets Operator as the
[platform secrets default](/posts/external-secrets-vs-secrets-store-csi/).
Shared intent goes through ACM. Unique intent stays in the cluster or app
repo. The failure mode is forcing unique site YAML through a label that
means “everywhere.”

Fork AutoShift when the Platform Plus catalog matches what you would have
written anyway and you will accept their values file as the UX. Extract the
pattern—hub GitOps, PolicyGenerator, ClusterSet labels—when you need four
operators, not forty, or when their Helm layout fights a cluster factory you
already trust. Product procedure for the generator itself stays in ACM
governance docs either way.

## The SA takeaway

1. **GitOps on the hub, ACM on the spokes** — day-2 platform intent is
   `Policy` plus placement, not an Application per cluster.
2. **PolicyGenerator is the supported wrapper** — commit native manifests;
   do not hand-write policy envelopes. Hub GitOps that generates policy is
   not an unmodified OpenShift GitOps instance.
3. **Labels select capabilities** — ClusterSets and `ManagedCluster` labels
   are the feature flag. Folder-per-cluster overlays reimplement placement.
4. **GitOpsCluster is the other direction** — it registers spokes so Argo
   can ship apps. Do not use it as a synonym for GitOps managing ACM.
5. **AutoShift is an example, not a SKU** — steal the operating model;
   verify versions against product matrices; use their Showroom if you want
   a lab.

If a non-prod hub and two spokes already exist, the next proof is small:
one PolicyGenerator that installs a single operator onto labels you control,
inform first, then enforce. Leave tenant apps on ApplicationSets. For a PoC
hub, start with
[Advanced Cluster Management (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/fleet-management/acm-install/)
and
[OpenShift GitOps (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/post-installation/openshift-gitops/).
Edge form factor still comes first—see
[OpenShift edge architectures](/posts/openshift-edge-architectures/)—
then feed the hub on purpose.

## Related posts

- [ACM as the Fleet Control Plane for OpenShift VMs](/posts/acm-openshift-virtualization/)
- [OpenShift Edge Architectures: Form Factor, Then Fleet](/posts/openshift-edge-architectures/)
- [OpenShift Network Policies: Tenant, Admin, Secondary](/posts/openshift-network-policies/)
- [External Secrets vs Secrets Store CSI on OpenShift](/posts/external-secrets-vs-secrets-store-csi/)

> Want help choosing hub-fed ACM policies versus per-cluster ApplicationSets
> for a real fleet? Reach out to your Red Hat account team—or prove one
> PolicyGenerator on a non-prod hub and two labeled spokes first.
{: .prompt-tip }

## Further reading

- [ACM 2.16 policy deployment and Policy Generator](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/2.16/html/governance/policy-deployment)
- [ACM 2.16 GitOps overview (`GitOpsCluster`)](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/2.16/html/gitops/gitops-overview)
- [Red Hat OpenShift GitOps 1.20](https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.20/)
- [Edge computing and GitOps ZTP (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/edge_computing/index)
- [ACM support matrix](https://access.redhat.com/articles/7136928)
- [AutoShift v2](https://github.com/auto-shift/autoshiftv2)
- [Getting to know AutoShift (Showroom)](https://github.com/auto-shift/autoshift-showroom)
