---
title: "External Secrets Operator vs Secrets Store CSI on OpenShift 4.22"
description: >-
  How External Secrets Operator and the Secrets Store CSI Driver differ on
  OpenShift 4.22—sync into Kubernetes Secrets versus mount at runtime—and when
  each delivery model fits platform teams.
date: 2026-08-03 10:00:00 -0500
categories: [OpenShift, Security]
tags: [external-secrets, secrets-store-csi, secrets, "4.22", gitops]
permalink: /posts/external-secrets-vs-secrets-store-csi/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization.
{: .prompt-info }

Platform teams rarely struggle to *store* secrets. The hard problem is delivery:
credentials must leave HashiCorp Vault, AWS Secrets Manager, Azure Key Vault, or
IBM Cloud Secrets Manager and reach a workload on
[OpenShift Container Platform](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/security_and_compliance/understanding-secrets-management)
without landing in Git, images, or tribal runbooks. On OpenShift 4.22, two first-class
patterns answer that question differently: the
[External Secrets Operator for Red Hat OpenShift](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/security_and_compliance/external-secrets-operator-for-red-hat-openshift)
and the
[Secrets Store CSI Driver](https://docs.redhat.com/en/learn/learning-paths/how-manage-kubernetes-secrets-red-hat-openshift/how-are-kubernetes-secrets-managed-red-hat-openshift).

They are not two installers for the same idea. One syncs external credentials into
native Kubernetes `Secret` objects. The other mounts credentials into the pod as a
CSI volume. The real choice is operating model—where secret material lives, how
apps consume it, and what your control-plane trust story can accept. This post is
a solution-architect comparison for platform and security teams making that
call—not an install runbook.

## Two delivery models

**External Secrets Operator (ESO)** is a cluster-wide Operator that deploys and
manages the `external-secrets` application. You declare where the external store
lives with a namespace-scoped `SecretStore` or cluster-scoped `ClusterSecretStore`,
then declare what to fetch with an `ExternalSecret`. The operand authenticates to
the provider, retrieves the material, and writes a native Kubernetes `Secret`.
Workloads keep using `envFrom`, `secretKeyRef`, Secret volume mounts,
`imagePullSecrets`, Ingress TLS refs, and GitOps objects that point at Secret
names. Rotation is controller-driven: update the external store, and ESO refreshes
the cluster Secret on its reconciliation interval. Red Hat documents ESO as a Day
2 Operator you can add without rewriting apps that already speak Kubernetes Secrets.

**Secrets Store CSI Driver (SSCSI)** takes a different cut. When a pod is
scheduled, the kubelet asks the CSI driver to create an inline ephemeral volume
(typically tmpfs). The driver talks to a provider plugin—AWS Secrets Manager,
HashiCorp Vault, and others—fetches credentials, and writes them as files in the
pod filesystem. When the pod goes away, the mount goes away. The primary model is
“secret as volume at runtime,” not “always materialize a cluster Secret.” Optional
sync-to-Kubernetes-Secret exists in some CSI setups; treat that as secondary, not
the architectural center. OpenShift 4.22 ships an updated Secrets Store CSI Driver
Operator (upstream secrets-store-csi-driver v1.5.6) with broader platform coverage,
including IBM Z, as part of the supported suite alongside ESO and cert-manager.

Red Hat’s learning guidance draws the contrast cleanly: ESO puts credentials into
Kubernetes Secrets; SSCSI mounts them without making etcd the system of record.

## Side-by-side

| Dimension | External Secrets Operator | Secrets Store CSI Driver |
| --------- | ------------------------- | ------------------------ |
| Delivery form factor | Sync into native `Secret` objects | Mount into pod as CSI volume (files) |
| Primary APIs | `SecretStore` / `ClusterSecretStore`, `ExternalSecret` | `SecretProviderClass` + CSI volume in the pod spec |
| Where material lands | etcd-backed Kubernetes Secrets (encrypt at rest matters) | Ephemeral mount in the pod; gone when the pod is gone |
| App consumption | Env vars, Secret volumes, image pulls, TLS Secret refs | File paths in the container; apps must read files (or you add sync) |
| Refresh model | Controller reconciliation / configurable refresh | Mount-time fetch; driver can refresh mounted content / optional synced Secrets |
| GitOps fit | Declare ExternalSecrets; apps keep Secret name references | Declare SecretProviderClass + volume mounts; Secret objects optional |
| Control-plane trust | You accept Secrets in the cluster (with encryption/RBAC) | You minimize Secrets in etcd; stronger when control plane is shared/managed |
| Typical OpenShift surface | Operator + CRDs; non-privileged controller model | CSI driver DaemonSet + provider plugins; privileged / hostPath considerations on OpenShift |
| Best-fit use | Platform integration, templating, image pulls, GitOps-native apps | Compliance “no secrets in etcd,” mount-only apps, tenant privacy from platform admins |

## Day-2 differences that matter

Choosing a secrets Operator from a slide is easy. Operations is where the
architectures diverge.

### Lifecycle and rotation

With ESO, the external store remains the source of truth, but the cluster holds a
reconciled copy. Platform teams reason in refresh intervals, ExternalSecret
status, and whether the Secret updated before a deploy rolled. Templating is a
first-class advantage: stitch multiple vault keys into a connection string or JWT
shape the app already expects. Short-lived credentials on the `SecretStore` /
`ClusterSecretStore` itself are a documented hardening practice—limit blast radius
of store auth, not only of the payload.

With SSCSI, bring-up is tied to pod scheduling. Rotation shows up as refreshed
file content for running pods (and refreshed synced Secrets if enabled). There is
less Secret-object inventory to drift, but more coupling between pod lifecycle and
secret availability. If the provider is unreachable at mount time, the pod fails
to start instead of quietly running on a stale Secret—fail-closed for security,
and a different paging story for SREs.

### Blast radius and etcd exposure

This is the compliance conversation in one sentence: **ESO materializes Secrets
in the cluster; SSCSI prefers not to.**

ESO’s documented trade-off is explicit—the operand stores fetched material in a
native Secret, which creates a *secret zero* / etcd-resident copy problem. Mitigate
it the OpenShift way: encrypt Secrets at rest, tighten RBAC on Secret get/list,
prefer short-lived provider credentials, and treat namespace boundaries as real.
Teams that trust the control plane—or run platform encryption and strong audit—
often accept that trade for compatibility.

SSCSI’s appeal is the inverse: credentials stay in the central store and appear
only as a short-lived mount for that pod. That maps to “secrets must not live in
etcd” policies and to shared or managed control planes where tenants want
credential privacy from platform admins. Optional sync-to-Secret narrows that
advantage—the moment you sync, you reintroduce an etcd copy—so enable it
deliberately.

### Developer UX

Most OpenShift application manifests still assume Kubernetes Secrets. ESO wins
on change cost: developers keep `envFrom` and Secret volume mounts; platform
engineers own ExternalSecret YAML and store bindings. Image pull secrets, Ingress
TLS, and Operators that require a Secret name continue to work because the object
type never changed.

SSCSI asks more of the workload contract. The natural interface is files under a
mount path. Apps that only know environment variables need a rewrite, a
reloader/sidecar pattern, or the optional Secret sync path—which undercuts the
“no Secrets in etcd” story if used broadly. Image pulls are a classic mismatch:
pull happens before volume mounts exist, so mount-only CSI secrets are a poor fit
for `imagePullSecrets`. Red Hat’s learning path calls this out directly—SSCSI is
not the tool for every credential type.

### Multi-tenancy and store scoping

ESO gives platform teams a clean tenancy dial. `ClusterSecretStore` centralizes
provider connectivity for the fleet; namespace `SecretStore` and ExternalSecret
objects keep app teams inside their namespaces. RBAC on those CRDs becomes part
of the landing-zone design—who may create ExternalSecrets is as important as who
may `get` Secrets.

SSCSI tenancy tends to live in `SecretProviderClass` objects, provider auth
(IAM roles, Vault policies, Kubernetes SA projection), and which namespaces may
mount which classes. On OpenShift, provider DaemonSets and privileged /
`hostPath` needs are not a footnote—Vault CSI provider install guides routinely
call out Security Context Constraints and privileged pods. Budget platform
engineering time for that surface, not only for the happy-path mount YAML.

### GitOps and desired state

Both patterns work with
[Red Hat OpenShift GitOps](https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.20/html/security/managing-secrets-securely-using-sscsid-with-gitops);
they put different objects in Git.

ESO GitOps usually commits ExternalSecret (and store) manifests. Argo CD
reconciles desired *references*; ESO fills Secret *data*. Apps stay Secret-native;
Git stays secret-free. Red Hat also documents ESO with OpenShift GitOps for
short-lived tokens consumed by the GitOps path itself.

SSCSI GitOps commits SecretProviderClass definitions and pod specs with CSI
volume mounts. Desired state describes *how to mount*, not a Secret blob—attractive
when auditors ask whether GitOps materializes credentials as cluster objects. The
cost is pod-spec coupling and debug that shifts from `oc get secret` to mount
events and provider logs.

### Failure modes you will operate at 2 a.m.

- **ESO:** stale Secrets if reconciliation lags; store auth broken but pods still
  running on last-known Secret data; RBAC mistakes that expose Secrets broadly;
  forgetting etcd encryption while celebrating “we use Vault.”
- **SSCSI:** pods stuck ContainerCreating when the provider or network path fails;
  SCC/privileged misconfiguration on provider DaemonSets; apps that cannot find
  files after a mount path change; teams that enabled Secret sync everywhere and
  accidentally rebuilt the etcd problem.

Pick the failure mode your on-call runbooks already know how to debug.

## Complementary patterns, not rival religions

Do not let architecture reviews collapse this into “ESO versus CSI, pick one
forever.” OpenShift’s secrets-management chapter presents both as supported tools
in the same suite, alongside cert-manager for certificate lifecycle.

Practical combinations show up often:

- **ESO as the platform default** for application Secrets, GitOps, image pulls,
  and anything that must be a Kubernetes Secret by API contract.
- **SSCSI for specific high-sensitivity workloads** that must not leave durable
  Secret objects in etcd, or for tenants that insist on mount-only delivery on a
  shared control plane.
- **cert-manager** for certificates—adjacent problem, different Operator; do not
  stretch ESO or CSI into a general-purpose PKI substitute.

If a stakeholder asks “should we use External Secrets or the Secrets Store CSI?”
the precise answer is usually “which consumption contract and etcd posture are we
standardizing—and which exception path do we document?” That clarification alone
prevents a surprising number of circular design reviews. For broader platform
security context on hybrid OpenShift estates, see
[Platform and Supply-Chain Security for Regulated Hybrid Cloud](/posts/openshift-security-platform-supply-chain/).

## When to choose which

**Lean External Secrets Operator when:**

- Applications and Operators already consume Kubernetes Secrets
- You need `imagePullSecrets`, Ingress TLS Secrets, or other Secret-name APIs
- GitOps should declare ExternalSecrets while apps keep Secret references
- You want templating into complex Secret shapes, or Secrets that persist across
  short provider blips (with encryption/RBAC)
- You trust the control plane enough to hold reconciled Secret copies

**Lean Secrets Store CSI when:**

- Compliance forbids durable credentials in etcd as Kubernetes Secrets
- Workloads are file-oriented (or you will invest in that contract)
- Control plane is shared/managed and tenants want credential privacy from platform admins
- You can operate privileged CSI/provider DaemonSets under OpenShift SCCs
- Image pulls and Secret-only APIs are handled by a different path (often ESO)

**A practical sequencing note for many customers:** standardize on External Secrets
Operator as the default delivery model for OpenShift application platforms—especially
with OpenShift GitOps—then introduce Secrets Store CSI for the workloads and
tenancy cases that genuinely require mount-only, non-etcd delivery. Reversing that
order forces every Secret-native integration through an awkward sync or rewrite.

## Closing

External Secrets Operator and the Secrets Store CSI Driver solve the same pressure—
get enterprise vault material onto OpenShift without putting it in Git—with different
boundaries. ESO optimizes for Kubernetes-native Secret consumption, templating, and
GitOps-friendly platform integration. SSCSI optimizes for ephemeral mounts and an
etcd-light posture at the cost of app and privileged-driver complexity. Pick the
delivery model you can rotate, audit, and debug at 2 a.m.—not only the one that
looks cleanest on a zero-trust slide.

Authoritative starting points:

- [Understanding secrets management (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/security_and_compliance/understanding-secrets-management)
- [External Secrets Operator for Red Hat OpenShift (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/security_and_compliance/external-secrets-operator-for-red-hat-openshift)
- [How to manage Kubernetes Secrets with Red Hat OpenShift](https://docs.redhat.com/en/learn/learning-paths/how-manage-kubernetes-secrets-red-hat-openshift/how-are-kubernetes-secrets-managed-red-hat-openshift)
- [Managing secrets with Secrets Store CSI and OpenShift GitOps](https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.20/html/security/managing-secrets-securely-using-sscsid-with-gitops)

If you are mapping either pattern into a broader platform or regulated landing-zone
conversation, that is exactly the kind of design discussion Red Hat solution
architects exist for.
