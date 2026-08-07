# Design: Confidential AI on OpenShift blog post

**Date:** 2026-08-07  
**Site:** https://thomasphall.github.io/ (Jekyll + Chirpy)  
**Status:** Approved in conversation; awaiting final review of this spec before drafting the post

## Goal

Publish one full-journey blog post that takes a platform audience from CPU confidential computing through GPU TEEs, composite attestation (Trustee + NRAS), and the OpenShift sandboxed containers deployment path.

## Audience

Solution architects and platform engineers evaluating confidential AI on bare-metal OpenShift. Readers may know OpenShift operators but not the TEE/attestation stack.

## Approach

Single narrative arc (not a split series, not a CR dump). Solution-architect map with enough process detail to be actionable; product docs remain the source of truth for install steps.

## Front matter

```yaml
title: "Confidential AI on OpenShift: From CPU TEEs to NVIDIA GPUs and Trustee Attestation"
description: >-
  CPU TEEs alone do not protect AI on GPUs. Compare Intel TDX and AMD SEV-SNP,
  close the GPU gap with NVIDIA Confidential Computing, and wire composite
  attestation on OpenShift with Trustee and NRAS.
date: 2026-08-07 14:00:00 -0500
categories: [OpenShift]
tags: [openshift, confidential-computing, tdx, sev-snp, nvidia, gpu, trustee, attestation, sandboxed-containers, coco]
permalink: /posts/confidential-ai-openshift-trustee-nras/
```

**File:** `_posts/2026-08-07-confidential-ai-openshift-trustee-nras.md`

## Thesis

CPU confidential computing is necessary but not sufficient for AI. You need a CPU TEE (Intel TDX or AMD SEV-SNP), NVIDIA Confidential Computing on the GPU, and composite attestation (Red Hat build of Trustee + NVIDIA NRAS) before secrets leave the vault—and OpenShift sandboxed containers is how you operationalize that as pods.

## Outline

1. **Personal disclaimer** — standard Chirpy `prompt-info` block
2. **Why this matters** — data/models in use; host and hypervisor out of TCB for regulated or multi-tenant AI
3. **CPU TEEs: Intel TDX vs AMD SEV-SNP** — same job, different silicon; comparison table; fleet choice; do not mix TEE types in one cluster for this path
4. **The GPU gap** — CPU TEE does not encrypt GPU memory; NVIDIA CC (and PPCIE for multi-GPU HGX) extends the boundary; GPU attached via passthrough into the CVM
5. **Composite attestation (Trustee + NRAS)** — KBC → KBS auth/challenge → CPU + GPU evidence → AS verifies CPU (built-in TDX/SNP + RVPS) and GPU (NRAS remote verifier) → EAR token with `cpu0`/`gpu0` → resource policy → secret release; ASCII sequence diagram
6. **OpenShift process** — operator stack and deploy order; highlights for MachineConfig (IOMMU), NVIDIA ClusterPolicy (CC on, host driver off, VFIO/kata plugin), node labels, KataConfig (`kata-cc-nvidia-gpu`), TrusteeConfig Restricted, initdata binding, sample pod with `nvidia.com/pgpu`, CDH/sealed-secret secret path
7. **Design choices** — Trustee on a trusted cluster; HashiCorp Vault as KBS backend; signed images; start with one confidential GPU per pod; homogeneous TEE workers
8. **What this is not** — not invulnerable; guest OS/app hardening still required; vendor PKI trust remains; docs are authoritative
9. **Further reading** — Red Hat sandboxed containers / Trustee docs; NVIDIA confidential containers / NRAS docs

## Voice and form

- Match recent posts (edge architectures, ACS for Virt): thesis early, short sections, ASCII diagrams, selective bold for the one-line claim
- Length target: ~2.5–3.5k words
- YAML: initdata concept, TrusteeConfig/ClusterPolicy highlights, one workload pod—not a full install dump
- No secrets, tokens, or real registry credentials in examples
- Link to official Red Hat and NVIDIA documentation; do not invent version-specific install commands that may drift
- Explicit “views are my own” disclaimer

## Version / product framing (as of writing)

- Frame confidential GPU on bare-metal OpenShift sandboxed containers as GA in the 1.13 / Trustee 1.2 timeframe
- Call out OpenShift 4.21+ where relevant for the confidential GPU path
- Mention Azure confidential GPU only as Technology Preview if mentioned at all (optional one-liner; prefer bare metal as the main path)
- Prefer “latest stable OpenShift” language where exact minor versions are not essential

## Out of scope

- Step-by-step BIOS menus per OEM
- Full ClusterPolicy YAML paste of every field
- Air-gapped SNP deep dive (one-line mention OK)
- Intel SGX process enclaves as a primary path
- Creating MkDocs site structure (this repo is Jekyll/Chirpy)

## Delivery

1. Add the markdown post under `_posts/`
2. Local preview optional (`bundle exec jekyll serve`) if environment allows
3. Open a PR to `main` when the user asks to publish; do not push/merge unprompted

## Spec self-review

- [x] No TBD/placeholder sections in the outline
- [x] Single post, full journey (matches approved approach #3)
- [x] Scope matches site conventions (Chirpy post, not MkDocs)
- [x] No contradiction with “docs are source of truth” vs “explain the process”
- [x] Commit of this spec deferred unless the user asks (personal git commit preference)
