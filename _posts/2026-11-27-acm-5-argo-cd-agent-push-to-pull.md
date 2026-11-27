---
title: "ACM 5.0 Argo CD Agent: Switch Push to Pull"
description: >-
  The Argo CD Agent pull model is GA in RHACM 5.0. Learn when outbound
  spokes beat hub push, what the switch breaks, and what to check before
  the hub upgrade.
date: 2026-11-27 06:30:00 -0600
categories: [OpenShift]
tags: [openshift, gitops, acm, edge]
permalink: /posts/acm-5-argo-cd-agent-push-to-pull/
social_title: |-
  ACM 5.0
  Switch Argo CD to pull
social_label: RHACM
social_subtitle: Outbound spokes · GitOpsCluster
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization. Operator life-cycle dates are
> from the OpenShift operators life-cycle page as reviewed on November 27,
> 2026.
{: .prompt-info }

[GitOps should manage ACM, not the cluster](/posts/gitops-should-manage-acm/)
is the design split. OpenShift GitOps on the hub feeds
Red Hat Advanced Cluster Management for Kubernetes (RHACM)
policies, and a `GitOpsCluster` is the other direction: Argo CD reaching
spokes. That post stops at the design. This one is the cutover.

The pull path is generally available in RHACM 5.0. Red Hat's
[November 11 announcement](https://www.redhat.com/en/blog/red-hat-advanced-cluster-management-kubernetes-5)
calls the Argo CD Agent integration generally available. The
[November 25 Red Hat Developer article](https://developers.redhat.com/articles/2026/11/25/scaling-multicluster-gitops-with-argocd-agent-and-red-hat-advanced-cluster-management-for-kubernetes)
walks managed mode, the default, and the `GitOpsCluster` that bootstraps it.
RHACM 2.16 still documents that add-on as
[Technology Preview](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/2.16/html/gitops/gitops-overview).
The YAML is familiar. RHACM 5.0 is the release whose guide and announcement
call the integration generally available.

## The two fields that flip the model

Push and pull both start from a `GitOpsCluster`. Push registers spokes with
the hub Argo CD and leaves `gitopsAddon` off. The RHACM 5.0 agent sample
turns the add-on on and turns the agent on under it. `mode` is optional.
The guide's default is `managed`.

```yaml
apiVersion: apps.open-cluster-management.io/v1beta1
kind: GitOpsCluster
metadata:
  name: agent-gitops
  namespace: openshift-gitops
spec:
  argoServer:
    argoNamespace: openshift-gitops
  placementRef:
    kind: Placement
    apiVersion: cluster.open-cluster-management.io/v1beta1
    name: gitops-placement
  gitopsAddon:
    enabled: true
    argoCDAgent:
      enabled: true
```

Nest `argoCDAgent` under `gitopsAddon`. That is the field the
[RHACM 5.0 pull guide](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/5.0/html/gitops/gitops-pull-overview)
reads. The November 25 article sets `mode: managed` in its example. Omit
`mode` and the default is still managed.

`gitopsAddon.enabled` installs the OpenShift GitOps operator and an Argo CD
instance on every cluster the placement selects. `argoCDAgent.enabled` adds
the agent and the hub principal. In managed mode you keep authoring
`Application` and `ApplicationSet` objects on the hub. The principal
dispatches them. The spoke application controller reconciles them. Set
`mode: autonomous` only when the spoke owns the `Application` and the hub
copy must stay a read-only mirror.

The placement that `placementRef` names is the infrastructure placement. It
decides who receives the add-on. The `ApplicationSet` needs a second
`Placement`, even when the selectors match. The documented infrastructure
placement tolerates unreachable and unavailable clusters, selects
`vendor=OpenShift`, and excludes `local-cluster`.

One sentence in the pull guide decides the change window: enabling the
OpenShift GitOps add-on on a `GitOpsCluster` disables the push model for
all applications.

## When outbound spokes beat hub push

Push keeps the application controller on the hub. Managed clusters do not
run their own Argo CD. RHACM creates a cluster secret per spoke. The
default `application-manager` service account on the spoke is
`cluster-admin`, so that secret can apply anything. RHACM 2.16 documents
the secret's server URL as the cluster proxy by default, and as the
managed cluster API only when that add-on is unavailable, and only for
OpenShift. Read the server field on the hub you have. A proxy URL means
push is already using the tunnel the spoke opened for RHACM. An API URL
means the hub must route to that API.

The agent changes the failure domain either way. The spoke dials the
principal over mutual TLS, the apply happens on the spoke, and the agent
authenticates with the client certificate the add-on issues. After the
switch, delete the old `application-manager` cluster secrets. The
uninstall steps still name them.

```text
Push                                    Agent pull, managed mode

Git --> hub controller --> spoke API    Git --> spoke controller --> spoke API
              ^                                      ^
              |                                      |
        cluster secret                         spoke dials the principal
        on the hub                             outbound gRPC, mTLS
```

| Question | Push | Argo CD Agent, managed | ManifestWork pull |
| -------- | ---- | ---------------------- | ----------------- |
| Who reconciles | Hub application controller | Spoke application controller | Spoke application controller |
| How the ApplicationSet addresses the spoke | Cluster server URL from the generator | Cluster name from the generator | Local Kubernetes API, plus the pull annotations |
| Delivery path | Hub applies through the cluster secret | Spoke opens gRPC to the principal | Hub ships the Application as a ManifestWork |
| Hub console | Full Argo CD UI | Full Argo CD UI, including trees and logs | Aggregated health and sync |
| Subscription | OpenShift, for GitOps | Platform Plus, for the agent | OpenShift, for GitOps |
| Fits | A small fleet the hub already reaches | Restricted or high-latency spokes, with the full UI | OpenShift spokes where aggregated status is enough |

Outbound-only spokes beat hub push when any of these are true.

**The hub cannot apply.** The cluster proxy is off, or the fallback API
URL is not reachable from the hub. Retail, factory, and other restricted
sites in the November 11 announcement are this case. The agent needs
egress from the spoke to the principal route. It does not need a new
inbound path to the spoke API. The RHACM klusterlet on that spoke is
already outbound. GitOps delivery joins it.

**The hub should stop holding spoke admin tokens.** Anyone who can read
secrets in `openshift-gitops` can use the push cluster secrets. The agent
session uses the client certificate the add-on issues. Delete the push
secrets once the agent is the path you mean to keep. The documented spoke
policy is a separate privilege question, covered below.

**The hub controller is the scale limit.** A
[September 24, 2026 lab](https://developers.redhat.com/articles/2026/09/24/scaling-gitops-pull-architecture-global-fleets)
on OpenShift 4.21, RHACM 2.16, and OpenShift GitOps 1.20 synced 31,200
applications and 3.12 million resources across 480 spokes in about 13
minutes. The limits they recorded were hub API and etcd throughput, and
ApplicationSet controller memory. That lab is the evidence for moving
reconciliation off the hub. It is an RHACM 2.16 measurement. The November
25 article is the RHACM 5.0 integration: the add-on bootstraps the
principal and the agents from a `GitOpsCluster`.

**The spoke should keep applying when the hub path is down.** The
November 25 article says a spoke keeps reconciling if the hub is offline.
New hub-authored changes wait until the agent reconnects. Upstream
[managed-mode guidance](https://argocd-agent.readthedocs.io/stable/user-guide/managed-agent/)
adds the condition: if the spoke controller uses the hub repo server or
hub Redis, the hub is still a single point of failure for rendering. The
RHACM add-on installs an Argo CD instance on the spoke. Keep that
instance's repository access on the spoke when hub loss is the failure
you are buying pull to survive. The spoke still needs a path to Git for
new commits. Repository secrets are created on the hub and distributed
to matching agents. A gRPC session with no Git egress syncs nothing new.

Keep push when the fleet is small, the hub already reaches every API, and
you will not run an OpenShift GitOps operator on every spoke. Keep push
when you do not have
[OpenShift Platform Plus](/posts/ove-vs-openshift-platform-plus/)
on those spokes. RHACM does not include the agent entitlement. The
ManifestWork pull path is the OpenShift-subscription alternative: each
spoke runs GitOps, the hub shows aggregated health, and the full resource
tree stays on the spoke. ManifestWork pull is supported on OpenShift
spokes. For other Kubernetes distributions, the agent path is the one
the RHACM 5.0 guide documents.

Hub-local policy sync stays on the hub GitOps instance from
[GitOps on the hub, RHACM on the spokes](/posts/gitops-should-manage-acm/).

## What the switch breaks

**Every push ApplicationSet on that `GitOpsCluster`.** The add-on
disables push for all applications, so a mixed fleet on one object ends
in the same change. Rewrite `destination.server` to `destination.name`
before the add-on is enabled. The principal routes on the name. A
template that still carries the server URL is the push shape, and push
is off.

{% raw %}
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: guestbook-appset
  namespace: openshift-gitops
spec:
  generators:
    - clusterDecisionResource:
        configMapRef: acm-placement
        labelSelector:
          matchLabels:
            cluster.open-cluster-management.io/placement: app-placement
        requeueAfterSeconds: 30
  template:
    metadata:
      name: "{{name}}-guestbook"
    spec:
      project: default
      source:
        repoURL: https://github.com/argoproj/argocd-example-apps
        targetRevision: HEAD
        path: guestbook
      destination:
        name: "{{name}}"
        namespace: guestbook
```
{% endraw %}

`configMapRef: acm-placement` is the ConfigMap the `GitOpsCluster`
controller creates. `app-placement` is the application placement, a
different object from `gitops-placement`.

**Hub-local Applications, if you copy the sample `ArgoCD`.** The hub
procedure rewrites the hub `ArgoCD` before you create the
`GitOpsCluster`. The sample sets the application controller off, turns
the principal on, and exposes a route for the agents:

```yaml
apiVersion: argoproj.io/v1beta1
kind: ArgoCD
metadata:
  name: openshift-gitops
  namespace: openshift-gitops
spec:
  controller:
    enabled: false
  sourceNamespaces:
    - "*"
  argoCDAgent:
    principal:
      enabled: true
      destinationBasedMapping: true
      auth: "mtls:CN=system:open-cluster-management:cluster:([^:]+):addon:gitops-addon:agent:gitops-addon-agent"
      namespace:
        allowedNamespaces:
          - "*"
      server:
        route:
          enabled: true
```

`destinationBasedMapping: true` is the managed-mode switch. Set it to
false only for autonomous mode. `controller.enabled: false` stops that
instance from reconciling anything itself, including the hub `Policy`
objects from the earlier design. OpenShift GitOps 1.22 marks
[hybrid architecture](https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.22/html/release_notes/index)
generally available: the hub controller stays for hub-local applications,
and agent applications sync through the pull path, isolated by label
selectors and `argocd.argoproj.io/skip-reconcile`. The November 25
article uses that layout. Its rule: the `GitOpsCluster` placement
selects remote clusters and excludes the hub. Hybrid keeps hub-local
applications on the hub controller. Spoke applications on that
`GitOpsCluster` follow the pull path once the add-on is enabled.

**The operator Subscription, if the three variables are missing or
replaced blindly.** The hub procedure adds them before the `ArgoCD`
rewrite:

```yaml
spec:
  config:
    env:
      - name: ARGOCD_CLUSTER_CONFIG_NAMESPACES
        value: openshift-gitops,local-cluster
      - name: ARGOCD_PRINCIPAL_TLS_SERVER_ALLOW_GENERATE
        value: "false"
      - name: ARGOCD_PRINCIPAL_REDIS_SERVER_ADDRESS
        value: openshift-gitops-redis:6379
```

Merge names into an existing `ARGOCD_CLUSTER_CONFIG_NAMESPACES` value.
Replacing the list drops cluster-scoped rights from any namespace you
omit. OpenShift GitOps treats the namespaces in that variable as
cluster-scoped instances, and
[warns](https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.22/html/declarative_cluster_configuration/configuring-an-openshift-cluster-by-deploying-an-application-with-cluster-configurations)
that users of those instances can elevate themselves.
`ARGOCD_PRINCIPAL_TLS_SERVER_ALLOW_GENERATE=false` keeps the principal
on the add-on's certificates. A generated certificate will not match
the CA the agents trust. The Redis value is the service the default
OpenShift GitOps instance creates, `openshift-gitops-redis`.

**AppProjects the principal will not propagate.** The principal ships
an `AppProject` only when its destinations and `sourceNamespaces` match
the agent. The documented `default` project uses wildcards so a lab
can connect. Narrow `sourceRepos`, destinations, and
`clusterResourceWhitelist` to the clusters and namespaces you deploy
before that project is the one production Applications use.

**An empty placement.** The `ManagedClusterSetBinding` has to exist in
`openshift-gitops`. Without it the placement selects nothing, the
add-on goes nowhere, and the failure looks like a Git problem.

**Spokes that already run GitOps.** The add-on enforces an `ArgoCD`
named `acm-openshift-gitops` in `openshift-gitops`, with the spoke
server disabled and the agent enabled. The documented customization of
that policy binds `cluster-admin` to the spoke application-controller
service account. The guide states that binding grants full cluster
administrator privileges. Replace it with the role those applications
need before the placement includes a production spoke. Where a spoke
must keep its own GitOps object, the add-on honors
`gitops-addon.open-cluster-management.io/skip: "true"` on that object.

**An old add-on config that silently wins.** `overrideExistingConfigs`
defaults to false. Existing `AddOnDeploymentConfig` values stay, and
the `GitOpsCluster` adds only values that were missing. Set it to true
when a spoke already has a ManifestWork-era add-on config and you mean
for the agent settings to replace it.

**A rollback that deletes objects in the wrong order.** Remove the
`ApplicationSet` resources and wait until the generated Applications
are gone, then delete the `GitOpsCluster`, then the generated `Policy`
and `PlacementBinding`. A `Policy` left behind keeps enforcing the
spoke `ArgoCD`. The guide says the uninstall takes minutes and that
finalizers should be left in place until cleanup finishes.

ApplicationSet objects outside the Argo CD namespace, and progressive
rollout, are still Technology Preview in the RHACM 5.0 GitOps guide.
Leave both out of the cutover.

## What to check before you upgrade the hub

RHACM 5.0 is platform-aligned with OpenShift 5.0. On the operators
life-cycle page it supports OpenShift 4.22 and 5.0, with general
availability on November 6, 2026, full support through November 30,
2027, and maintenance through November 30, 2028. RHACM 2.16 supports
OpenShift 4.19 through 4.22 and does not list 5.0. RHACM 2.17 lists
4.20, 4.21, 4.22, and 5.0. A 5.0 hub can run 2.17 or 5.0. The agent
procedure in this post is the 5.0 guide. The 2.17 GitOps PDF still
titles the agent enablement Technology Preview. Confirm that release's
chapter before you treat the agent as supported there.
[Park on 4.22 or hop to 5.0](/posts/openshift-4-22-vs-5-0-upgrade-decision/)
is the cluster decision. This is the GitOps decision that follows it.

Red Hat describes the RHACM 5.0 upgrade as seamless in the same way as
earlier releases. The pull switch is a separate edit. Leave the hub
upgrade and `gitopsAddon.enabled` in different windows. Existing
`GitOpsCluster` objects keep their current spec through the hub
upgrade. Pull starts when you set `gitopsAddon.enabled`.

| Check | What you want before the placement goes wide |
| ----- | -------------------------------------------- |
| Hub OpenShift | 4.22 or 5.0, matching the RHACM 5.0 row |
| RHACM after the upgrade | 5.0 for this procedure |
| OpenShift GitOps on the hub | A release whose principal matches the guide. Hybrid is GA in 1.22 |
| Platform Plus | An entitlement on every cluster the agent placement will select |
| Push cluster secrets | The server URL, proxy or spoke API, and who can read `openshift-gitops` |
| ApplicationSet templates | Which ones still set a server URL |
| Hub-local apps | Policy sync and any other Application on this `openshift-gitops` instance |
| Spoke GitOps | An existing `ArgoCD`, and whether `acm-openshift-gitops` may join it |
| Egress | Spoke to the principal route, and spoke to Git |
| Add-on config | `overrideExistingConfigs` left false unless you mean to replace it |
| Placements | One for the add-on, one for applications, `local-cluster` excluded, unreachable and unavailable tolerated |
| Images | `ManagedClusterImageRegistry` pointed at the mirror before a disconnected spoke pulls the add-on |

RHACM 5.0 integrates the managed-cluster image registry with the GitOps
add-on, including CNCF-conformant Kubernetes clusters. On a disconnected
spoke, confirm the mirror before the placement selects it. If add-on
detection misses an OpenShift cluster, `olmSubscription.enabled: true`
under `gitopsAddon` forces the Operator Lifecycle Manager install path.

After the flip, read `status.conditions` on the `GitOpsCluster`:
`Ready`, `PlacementResolved`, `CertificatesReady`, and
`ArgoCDAgentPrereqsReady`. The principal pod label on the hub is
`app.kubernetes.io/name=openshift-gitops-agent-principal`. The spoke
agent label is `app.kubernetes.io/part-of=argocd-agent`. Applications
should reach `Synced` from the spoke, visible on the hub.

## The solutions architect takeaway

1. **The cutover is two fields under `gitopsAddon`** — `enabled` and
   `argoCDAgent.enabled`. Managed mode is the default. Author
   Applications on the hub, reconcile them on the spoke.
2. **Enabling the add-on disables push for every application on that
   `GitOpsCluster`** — rewrite destinations to the cluster name in the
   same window. Hybrid keeps the hub controller for hub-local work and
   still excludes the hub from the agent placement.
3. **Outbound spokes beat push when the hub cannot apply, should not
   hold spoke admin tokens, or should not be the reconciler** — the
   spoke still needs Git, and a hub repo server puts the hub back in
   the render path.
4. **Platform Plus is the agent entitlement** — RHACM does not include
   it. ManifestWork pull is the OpenShift-subscription path, with
   aggregated status, on OpenShift spokes.
5. **Upgrade the hub first, on its own** — RHACM 5.0 is the release
   whose guide documents this as generally available. Prove one
   non-prod spoke, then widen the placement.

For sites where the WAN is the design input, start with
[OpenShift edge architectures](/posts/openshift-edge-architectures/).
For the fleet that is already a virtualization estate, the hub's job
is unchanged:
[ACM as the fleet control plane for OpenShift VMs](/posts/acm-openshift-virtualization/).

## Related posts

- [GitOps Should Manage ACM, Not the Cluster](/posts/gitops-should-manage-acm/)
- [ACM as the Fleet Control Plane for OpenShift VMs](/posts/acm-openshift-virtualization/)
- [OpenShift Edge Architectures: Form Factor, Then Fleet](/posts/openshift-edge-architectures/)
- [OVE vs OpenShift Platform Plus: The SKU Choice](/posts/ove-vs-openshift-platform-plus/)

> Want help deciding which spokes leave hub push before an RHACM 5.0
> hub upgrade? Reach out to your Red Hat account team—or inventory one
> non-prod `GitOpsCluster` and its ApplicationSet destinations before
> you enable the add-on.
{: .prompt-tip }

## Further reading

- [RHACM 5.0 pull model, including the managed-mode GitOpsCluster](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/5.0/html/gitops/gitops-pull-overview)
- [RHACM 5.0 GitOps overview: push, agent pull, and ManifestWork pull](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/5.0/html/gitops/gitops-overview)
- [RHACM 2.16 GitOps token and cluster-proxy priority](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/2.16/html/gitops/gitops-overview)
- [Scaling multicluster GitOps with argocd-agent and RHACM (November 25, 2026)](https://developers.redhat.com/articles/2026/11/25/scaling-multicluster-gitops-with-argocd-agent-and-red-hat-advanced-cluster-management-for-kubernetes)
- [Scaling GitOps: the pull architecture lab (September 24, 2026)](https://developers.redhat.com/articles/2026/09/24/scaling-gitops-pull-architecture-global-fleets)
- [RHACM 5.0 announcement](https://www.redhat.com/en/blog/red-hat-advanced-cluster-management-kubernetes-5)
- [OpenShift GitOps 1.22 release notes (hybrid architecture)](https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.22/html/release_notes/index)
- [OpenShift operators life cycle](https://access.redhat.com/support/policy/updates/openshift_operators)
- [Self-managed OpenShift subscription guide](https://www.redhat.com/en/resources/self-managed-openshift-subscription-guide)
- [argocd-agent managed mode](https://argocd-agent.readthedocs.io/stable/user-guide/managed-agent/)
