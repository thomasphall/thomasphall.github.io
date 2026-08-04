# Design: RHACS with OpenShift Virtualization Blog (AI Prompt)

**Date:** 2026-08-04  
**Target repo:** `thomasphall/thomasphall.github.io`  
**Theme:** Jekyll Chirpy  
**Status:** Approved; post drafted at `_posts/2026-08-04-acs-openshift-virtualization.md`

## Goal

Produce a voice-matched, self-contained AI prompt that generates a solution-architect digest (~1,100–1,400 words) on how Red Hat Advanced Cluster Security for Kubernetes (RHACS) still applies when virtual machines run on OpenShift Virtualization—focusing on what ACS sees for VM workloads, which policies matter, and clear boundaries vs guest OS hardening. Minimal CLI; no YAML dumps.

## Audience & voice

- Red Hat Staff Solution Architect / OpenShift specialist
- Customer-facing, practical, confident — no hype
- Outcome-focused talking points for CNV + security conversations
- Match existing posts: platform/supply-chain security and OpenShift Virtualization hardening

## Approach

**Voice-matched full brief** (selected over two-stage prompt pack and minimal topic prompt): one copy-paste prompt with role, Chirpy front matter, fixed outline, accuracy guardrails, and cross-links.

## Angle

ACS still applies when VMs land on the platform: `virt-launcher` pods, images/disks that feed VMs, and policy/runtime visibility in the same multi-cluster risk view as containers. Guest OS hardening remains a separate layer.

## Deliverable (prompt metadata hints)

| Item | Value |
| ---- | ----- |
| Path hint | `_posts/YYYY-MM-DD-acs-openshift-virtualization.md` |
| Permalink | `/posts/acs-openshift-virtualization/` |
| Categories | `[OpenShift, Virtualization, Security]` |
| Tags | `[acs, openshift-virtualization, rhacs, security]` |
| Timezone | America/Chicago (`-0500`) |
| AI prompt file | `docs/superpowers/specs/2026-08-04-acs-openshift-virtualization-ai-prompt.md` |

## Content outline (forced by prompt)

1. Hook — VMs on OpenShift are Kubernetes workloads; RHACS still has a job
2. What ACS sees — virt-launcher, container disks/images, risky configs
3. Policies that matter for CNV — intentional allowlists, not blind disables
4. VM vulnerability visibility — RHACS 4.10 Technology Preview; not GA
5. Boundary — platform/workload posture vs guest OS hardening
6. Complementary story — Compliance Operator + virt hardening; soft CTA
7. Cross-links to existing posts

## Constraints

- Length ~1,100–1,400 words
- Accurate to Red Hat docs; do not invent ACS capabilities
- Label Technology Preview features honestly (VM vuln management in RHACS 4.10)
- Include personal-site disclaimer prompt used on other posts
- No secrets, credentials, or customer-identifying detail
- Markdown only; minimal audit commands; no YAML dumps
- Cross-link `/posts/openshift-security-platform-supply-chain/` and `/posts/openshift-virtualization-hardening-priorities/`

## Out of scope

- Full RHACS install/how-to
- Guest OS hardening checklist (covered by existing virt-hardening post)
- Generating/publishing the blog post itself in this step (prompt only)

## Publish path (when post is generated later)

1. Feature branch from `main`
2. Add Chirpy-compatible post under `_posts/`
3. Commit, push, open PR with `gh`
