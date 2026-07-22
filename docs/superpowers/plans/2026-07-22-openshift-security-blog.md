# OpenShift Security Blog Post Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish one Chirpy-compatible blog post on OpenShift platform and supply-chain security to `thomasphall/thomasphall.github.io` on `main`.

**Architecture:** Single Markdown file under `_posts/` with Chirpy front matter. GitHub Actions workflow `pages-deploy.yml` builds and deploys on push to `main`.

**Tech Stack:** Jekyll, jekyll-theme-chirpy (~> 7.4), GitHub Pages Actions

## Global Constraints

- Repo: `thomasphall/thomasphall.github.io`, branch `main`
- Working copy: `/tmp/thomasphall-blog-gh` (or equivalent clone)
- Filename: `_posts/2026-07-22-openshift-security-platform-supply-chain.md`
- Length: ~700–900 words
- Voice: Red Hat SA, regulated hybrid-cloud audience
- Themes: RHACS, Compliance Operator, signed supply chain (RHTAP / Enterprise Contract / Trusted Artifact Signer)
- Do not commit or push `docs/superpowers/` to the remote
- Do not modify `_config.yml`, theme files, or workflows
- User explicitly requested commit + push to `main`

---

### Task 1: Create Chirpy blog post

**Files:**
- Create: `_posts/2026-07-22-openshift-security-platform-supply-chain.md`
- Verify: front matter keys `title`, `description`, `date`, `categories`, `tags`
- Do not modify: `_config.yml`, `.github/workflows/pages-deploy.yml`

**Interfaces:**
- Consumes: Approved design in `docs/superpowers/specs/2026-07-22-openshift-security-blog-design.md`
- Produces: Published post path `/posts/openshift-security-platform-supply-chain/` after Pages deploy

- [ ] **Step 1: Confirm clean working tree for publishable files**

Run:
```bash
cd /tmp/thomasphall-blog-gh
git status -sb
git pull --ff-only origin main
```
Expected: `main` up to date with `origin/main`; only local untracked `docs/superpowers/` may exist.

- [ ] **Step 2: Write the post file with this exact content**

Create `_posts/2026-07-22-openshift-security-platform-supply-chain.md`:

```markdown
---
title: "OpenShift Security for Regulated Hybrid Cloud: Platform and Supply Chain"
description: >-
  How ACS, Compliance Operator, and signed supply-chain controls help teams
  prove security posture across hybrid OpenShift estates.
author: thomasphall
date: 2026-07-22 12:00:00 -0500
categories: [OpenShift, Security]
tags: [acs, compliance, supply-chain, hybrid-cloud]
---

Regulated organizations rarely fail an audit because they lack security tools.
They fail because posture is inconsistent: one cluster hardened, another drifted;
one pipeline signing images, another promoting unsigned builds; evidence scattered
across spreadsheets when an assessor asks for proof.

For hybrid OpenShift estates—on-premises, ROSA, or other managed OpenShift—the
winning pattern is the same: **observe risk continuously, prove configuration
against known baselines, and gate what is allowed to run**. Recent OpenShift
platform and supply-chain capabilities make that pattern repeatable instead of
heroic.

## See risk across the estate with RHACS

[Red Hat Advanced Cluster Security for Kubernetes (RHACS)](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_security_for_kubernetes/)
gives security and platform teams a single place to understand risk across
clusters. Rather than treating each OpenShift cluster as an island, RHACS
surfaces vulnerable images, risky deployments, and misconfigurations in context.

For a solution architect conversation, the value is operational: you can show
leadership *where* exposure lives and *whether* policy is enforced—not just that
a scanner exists. Built-in and custom policies can warn or block deployments that
violate your standards before they become audit findings. Pairing RHACS with
workload scanning means “we scan images” becomes “we prevent known-bad images
from landing in regulated environments.”

That multi-cluster view matters in hybrid designs. Controls should look the same
whether the cluster runs in your data center or in AWS `us-east-2`. Consistency
is what auditors and risk committees actually buy.

## Prove the platform with the Compliance Operator

Visibility alone is not enough. Regulated customers need evidence that the
*platform* itself matches an agreed baseline.

The [OpenShift Compliance Operator](https://docs.redhat.com/en/documentation/openshift_container_platform/4.19/html/security_and_compliance/compliance-operator)
automates inspection of cluster and node configuration against industry profiles
(for example CIS-oriented OpenShift profiles) using OpenSCAP. Administrators get
a clear picture of gaps and recommended remediations—expressed as Kubernetes
objects you can manage with GitOps, not one-off shell scripts.

Important nuance for customer conversations: the Compliance Operator **assists**
compliance programs; it does not replace an authorized auditor. What it *does*
deliver is continuous, automatable evidence of technical controls—exactly the
raw material assessors ask for when they sample configurations.

RHACS and the Compliance Operator are complementary. Compliance Operator
profiles cover much of the OpenShift infrastructure surface; RHACS strengthens
workload and deployment policy. Together they tell a fuller story than either
tool alone—and RHACS can surface Compliance Operator results in a shared
compliance view when both are in place.

## Gate the supply chain: sign, attest, verify

The third leg is supply chain integrity: proving that what runs in the cluster
is what your approved pipeline produced.

OpenShift already verifies signatures on platform release images during
updates. For *your* application images, the same discipline should apply:
sign builds, attach attestations, and verify before promote or deploy. Red Hat’s
software supply-chain tooling—including
[Trusted Application Pipeline](https://docs.redhat.com/en/documentation/red_hat_trusted_application_pipeline/)
patterns,
[Enterprise Contract](https://docs.redhat.com/en/documentation/red_hat_trusted_application_pipeline/1.4/html/managing_compliance_with_enterprise_contract/index)
(policy checks that an image is signed and attested by a trusted build system),
and [Trusted Artifact Signer](https://docs.redhat.com/en/documentation/red_hat_trusted_artifact_signer/)
for signing infrastructure—lets teams encode “only approved provenance runs here”
as policy, not tribal knowledge.

For regulated hybrid cloud, that closes a common gap: strong cluster hardening
undermined by an unsigned image promoted on Friday afternoon. When signature and
attestation checks sit in the pipeline *and* at admission, security stops being
a slide and becomes a gate.

## The SA takeaway

Lead with outcomes, not product lists:

1. **Observe** — RHACS for continuous, multi-cluster risk and policy.
2. **Prove** — Compliance Operator for baseline evidence and remediations.
3. **Gate** — signed, attested images verified with Enterprise Contract–style
   policy before they reach production.

Apply the same pattern on every OpenShift cluster in the estate. Hybrid should
mean *location* flexibility, not *control* flexibility.

If you are shaping a regulated landing zone, start in non-production: enable
Compliance Operator profiles, connect a cluster to RHACS, and require signed
images on one critical pipeline. The conversation with risk and audit gets much
easier when you can show the same controls working—quietly—every day.

> Want a deeper walkthrough for your environment? Reach out to your Red Hat
> account team—or try the pattern on a non-prod OpenShift cluster first.
{: .prompt-tip }
```

- [ ] **Step 3: Verify front matter and word count**

Run:
```bash
cd /tmp/thomasphall-blog-gh
python3 - <<'PY'
from pathlib import Path
p = Path('_posts/2026-07-22-openshift-security-platform-supply-chain.md')
text = p.read_text()
assert text.startswith('---\n')
assert 'title:' in text
assert 'categories: [OpenShift, Security]' in text
assert 'tags: [acs, compliance, supply-chain, hybrid-cloud]' in text
body = text.split('---', 2)[2]
words = len(body.split())
print(f'words={words}')
assert 650 <= words <= 950, words
print('OK')
PY
```
Expected: `words=` in ~700–900 range and `OK`.

- [ ] **Step 4: Commit only the post**

Run:
```bash
cd /tmp/thomasphall-blog-gh
git add _posts/2026-07-22-openshift-security-platform-supply-chain.md
git commit -m "$(cat <<'EOF'
Add OpenShift platform and supply-chain security blog post.

EOF
)"
git status -sb
```
Expected: commit succeeds; working tree clean for tracked files (local `docs/superpowers/` may remain untracked).

---

### Task 2: Push to main and confirm deploy trigger

**Files:**
- Remote: `origin` → `thomasphall/thomasphall.github.io`
- No local file changes beyond Task 1 commit

**Interfaces:**
- Consumes: Commit from Task 1 on `main`
- Produces: GitHub Actions run for `Build and Deploy`; post live at site URL after success

- [ ] **Step 1: Push main**

Run:
```bash
cd /tmp/thomasphall-blog-gh
git push -u origin HEAD:main
```
Expected: push accepted to `main`.

- [ ] **Step 2: Confirm Actions workflow started**

Run:
```bash
gh run list --repo thomasphall/thomasphall.github.io --limit 3
```
Expected: recent `Build and Deploy` run for the push (queued, in progress, or completed).

- [ ] **Step 3: Report URLs to user**

Provide:
- Repo file: `https://github.com/thomasphall/thomasphall.github.io/blob/main/_posts/2026-07-22-openshift-security-platform-supply-chain.md`
- Live post (after Pages finishes): `https://thomasphall.github.io/posts/openshift-security-platform-supply-chain/`

---

## Spec coverage check

| Spec requirement | Task |
| ---------------- | ---- |
| Chirpy post path/front matter | Task 1 |
| SA outline (hook → ACS → Compliance → supply chain → takeaway) | Task 1 Step 2 |
| ~700–900 words | Task 1 Step 3 |
| Push to main | Task 2 |
| Do not publish design/plan docs | Task 1 Step 4 stages only `_posts/` |
