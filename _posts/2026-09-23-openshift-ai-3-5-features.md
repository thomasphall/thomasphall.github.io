---
title: "What's New in Red Hat OpenShift AI 3.5"
description: >-
  A themed digest of Red Hat OpenShift AI 3.5: EvalHub GA, Models-as-a-Service
  OIDC, llm-d inference operations, and the 2.x-to-3.5 migration path for teams.
date: 2026-09-23 09:00:00 -0500
categories: [OpenShift]
tags: [openshift, security, gitops, hosted-control-planes]
permalink: /posts/openshift-ai-3-5-features/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization.
{: .prompt-info }

[Red Hat OpenShift AI](https://www.redhat.com/en/technologies/cloud-computing/openshift/openshift-ai)
3.5 is a production-operations release. The interesting surface is not another
notebook image. It is how you **evaluate** models, **govern** who can call them,
and **keep inference up** while you patch, scale, and rotate versions—on
[Red Hat OpenShift](https://www.redhat.com/en/technologies/cloud-computing/openshift),
including Hosted Control Planes on
[OpenShift Virtualization](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/index).

This post is a themed digest, not a complete changelog. For the authoritative
list—including fixed and known issues—start with the
[OpenShift AI 3.5 release notes](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/release_notes/index).

## Get off 2.x with a plan

Customers still on the 2.25 line should treat 3.5 as a **migration**, not an
Operator click-through. OpenShift AI 3.x changed enough components that Red Hat
ships a dedicated guide—*Assess and plan for migration from Red Hat OpenShift AI
2.25.9 (and later) to 3.5*—built around `rhai-cli`. It covers side-by-side and
in-place approaches, Kueue management-state prerequisites, and component-specific
`rhai-cli migrate` actions for Kueue, AI Pipelines, model serving, workbenches,
TrustyAI, training, Llama Stack/OGX, and Ray.

The 3.3 migration guide remains for estates that are landing on 3.3, not 3.5.
After you cut over, leave the `support-required-upgrade-3.5` channel and pick
`stable-3.5`, `stable-3.x`, or `eus-3.5` from the OpenShift AI Self-Managed life
cycle policy. Run `rhai-cli` on the **source** cluster before you upgrade; it is
a gap analysis, not a post-facto health check.

## EvalHub is the evaluation platform

EvalHub is generally available. That is the headline if your AI review still
means a spreadsheet of accuracy scores. EvalHub orchestrates evaluation for
models, applications, agents, tools, and vulnerability scanning, with a versioned
API, a breaking-change policy, must-gather, and Prometheus scrape via an
operator-managed `ServiceMonitor`.

What I would actually put on a landing-zone slide:

- **SDK and CLI** (`eval-hub-sdk`) so jobs live in pipelines and notebooks, not
  only in the UI
- **EvalCards** as schema-validated JSON (MLflow or OCI artifacts) for provenance
  and pass/fail, optionally next to OCI Model Cards
- **Automated Red Teaming** (Garak) as GA: OpenAI Responses endpoints, multilingual
  scans, parallel detectors, and disconnected (air-gapped) runs through EvalHub or
  Kubeflow Pipelines
- **Catalog scores**: new Red Hat-validated models pick up adversarial scan
  results in Hugging Face listings, with a Safety and Security Insights tab in
  the model catalog
- **Per-tenant EvalHub** (`spec.tenancy: single`) when a namespace must own its
  instance; shared multi-tenant remains the default recommendation

LM-Eval (`LMEvalJob` and the old evaluation UI) is deprecated. New evaluation
work goes to EvalHub. FMS Guardrails Orchestrator is also deprecated;
[NeMo Guardrails](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/release_notes/support-removals_relnotes)
is the recommended LLM safety framework, including on IBM Z.

This is adjacent to—not a substitute for—
[confidential AI with TEEs, GPUs, and Trustee](/posts/confidential-ai-openshift-trustee-nras/).
EvalHub tells you how the model behaves. Trustee tells you whether the runtime
was allowed to see the weights.

## Models-as-a-Service without an OpenShift account for every caller

Models-as-a-Service (MaaS) can authenticate against an **external OpenID Connect
(OIDC)** provider. Map IdP groups to MaaS subscriptions and quotas, then hand
users API keys scoped to those groups. That is the difference between "every
data scientist needs a cluster login" and "the platform uses the enterprise
directory you already run."

On the wire, MaaS now accepts the standard OpenAI `/v1/chat/completions` body
(`model` in the JSON) and still applies subscription, rate-limit, and
authorization policy. Path-based routing remains for existing clients. Admins
get a single **MaaS governance** page for subscriptions and authorization
policies; users get a Subscriptions tab for what they can actually call.

## Inference that survives day-2

Distributed Inference with llm-d is the serving story to lead with when the
workload is generative and the GPUs are expensive.

**Generally available on OpenShift**, and also on Azure Kubernetes Service and
CoreWeave Kubernetes Service, with Istio as the supported gateway and the
Gateway API Inference Extension in the supported set. Multi-model serving,
intelligent scheduling, and disaggregated serving are the utilization pitch.

The operational pieces that matter after the demo:

1. **Inference-aware pod lifecycle** — rolling updates, scale-down, and node
   maintenance finish in-flight requests and do not send traffic to pods still
   loading weights.
2. **Priority flow control** — `InferenceObjective` priority bands so interactive
   traffic stays ahead of batch on the same deployment, with holdback and
   sheddable eviction. If you configured the 3.4 Technology Preview, this is a
   breaking change: API group `inference.networking.x-k8s.io` → `llm-d.ai`,
   metrics prefix `inference_extension_` → `llm_d_epp_`, and saturation detection
   moves under `flowControl`.
3. **Controlled deployment** — weight-based split across versions of the same
   endpoint so you can prove a model or engine change on a slice of production
   traffic.
4. **KServe RawDeployment canary** — progressive rollouts on a single
   `InferenceService` via OpenShift Route alternate backends or Gateway API
   weights. Canary replicas are fixed-size; no HPA/KEDA on the canary.
5. **Observability** — Perses dashboards (now reachable by namespace-scoped
   users, not only cluster admins), service-level TTFT/TPOT/ITL histograms from
   the Endpoint Picker, and OpenTelemetry traces across the request path.

You can pin **Red Hat AI Inference fast** container images as a custom serving
runtime without waiting for the next OpenShift AI z-stream—useful when vLLM and
model support move faster than the platform Operator. OAuth proxy sidecar CPU and
memory for KServe are now fields on `DataScienceCluster`
(`spec.components.kserve.oauthProxy.resources`) so you are not forced into an
unmanaged `inferenceservice-config` ConfigMap.

## Platform day-2: queues, secrets, roles, GPUs

Kueue stops being invisible. Workbenches show Queued, Starting, Preempted,
Evicted, and Requeued, plus queue position when you can read the Kueue Visibility
API. A cluster **Infrastructure** page rolls up accelerator count, DCGM
utilization, hardware inventory by model, and Kueue cohort borrow/lend—when Kueue
is enabled.

GitOps-minded platform teams can leave queues in git. The `DataScienceCluster`
flag that controls automatic `ClusterQueue` and `LocalQueue` creation is
**disabled by default**, so the Operator does not create those objects unless
you enable the flag. Associate Hardware Profiles with the queues you already
manage. That matches the split in
[GitOps should manage ACM, not the cluster](/posts/gitops-should-manage-acm/):
the Operator should not fight the repo.

Workbenches can inject **existing Opaque Secrets** as environment variables
without showing values in the dashboard—the secrets
[External Secrets Operator](/posts/external-secrets-vs-secrets-store-csi/),
Vault, or Argo CD already synced into the project. ConfigMaps are not in that
dropdown in 3.5. Project admins can also create custom RBAC roles for workbenches
from a form (maintainer / reader / updater templates) without YAML.

**Hosted Control Planes on OpenShift Virtualization** is a supported OpenShift AI
3.5 configuration. If the AI landing zone is a fleet of tenant clusters on a virt
management plane, put that next to
[hosted vs virtualized control planes](/posts/hosted-vs-virtualized-control-planes/)
instead of treating AI as a separate topology conversation. Hardware BOMs still
come from the vendor RA, then you re-pin versions—see
[OpenShift hardware vendor reference architectures](/posts/openshift-hardware-vendor-reference-architectures/).

Elsewhere in 3.5, worth a lab ticket rather than a slide: MLflow tracking in
pipelines, workbenches, and Trainer; Training Hub algorithms preinstalled on the
Ray CUDA image (SFT, LoRA, GRPO, including disconnected); Feast
`SparkApplication` batch materialization; OGX Responses API; and IBM Power
coverage for OGX, KubeRay, MLflow, AutoML, and AutoRAG.

## Deprecated and removed

Upgrade planners should not skip this section. Details live in
[support removals for 3.5](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/release_notes/support-removals_relnotes).

**Deprecated (plan the replacement)**
- FMS Guardrails Orchestrator → NeMo Guardrails
- LM-Eval / `LMEvalJob` → EvalHub
- OGX Evaluation, Safety, and Shields APIs (already removed from the OGX
  Operator in the 3.5 EA train)

**Removed in 3.5**
- RStudio Server and CUDA RStudio workbench images (licensing). Running RStudio
  workbenches keep running; you cannot create or restart them from the dashboard.
  RStudio remains on the 2.25 and 3.3 streams through their stated EOLs, or you
  build unsupported images yourself and move R workflows to code-server or
  JupyterLab.
- Selected Kubeflow Training Operator v1 training images (v1 itself was already
  on the deprecation path)

2025.2 workbench and pipeline images stay selectable—marked outdated—so you can
validate against the new Red Hat Python index images before you force the cut.

## The solutions architect takeaway

When you frame OpenShift AI 3.5 for a platform review, lead with outcomes:

1. **Migrate** — `rhai-cli` against 2.25.9+, then a real update channel. Do not
   improvise a 2.x → 3.5 jump from OperatorHub screenshots.
2. **Evaluate** — EvalHub and Automated Red Teaming are the supported evaluation
   and safety-scan path; LM-Eval and FMS Guardrails are exit work.
3. **Govern** — MaaS plus external OIDC and OpenAI-shaped APIs so LLM access is
   an IAM problem, not an OpenShift user-provisioning problem.
4. **Serve without drama** — llm-d flow control, inference-aware rollouts, and
   controlled/canary promotions are the day-2 inference design, not a later
   add-on.
5. **Operate in git** — Kueue queues left in git (automatic creation is off
   by default), existing Secrets, dashboard roles, and HCP-on-virt as a
   supported AI topology.

Validate in non-production first: run the migration assessment, replay any 3.4
llm-d Technology Preview objects onto the new APIs, prove an EvalHub job and a
Garak scan, and confirm workbenches still start after you hide incompatible
default images. Pair the release with
[confidential AI](/posts/confidential-ai-openshift-trustee-nras/)
if weights-in-use is in scope, and with a vendor AI RA only after you re-validate
the OpenShift and GPU Operator versions.

## Related posts

- [Confidential AI on OpenShift: TEEs, GPUs, and Trustee](/posts/confidential-ai-openshift-trustee-nras/)
- [External Secrets vs Secrets Store CSI on OpenShift](/posts/external-secrets-vs-secrets-store-csi/)
- [Hosted vs Virtualized Control Planes on OpenShift 4.22](/posts/hosted-vs-virtualized-control-planes/)
- [OpenShift Hardware Vendor Reference Architectures](/posts/openshift-hardware-vendor-reference-architectures/)

> Want help planning an OpenShift AI 3.5 landing zone or a 2.x migration?
> Reach out to your Red Hat account team—or read the
> [OpenShift AI 3.5 release notes](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/release_notes/index)
> and prove EvalHub plus one llm-d rollout on a non-prod cluster first.
{: .prompt-tip }

## Further reading

- [OpenShift AI 3.5 release notes](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/release_notes/index)
- [New features and enhancements (OpenShift AI 3.5)](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/release_notes/new-features-and-enhancements_relnotes)
- [Support removals (OpenShift AI 3.5)](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/release_notes/support-removals_relnotes)
- [Red Hat OpenShift AI Self-Managed 3.5 documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/)
- [Red Hat OpenShift AI product page](https://www.redhat.com/en/technologies/cloud-computing/openshift/openshift-ai)
