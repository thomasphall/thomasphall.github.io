# Design: OpenShift Security Blog Post

**Date:** 2026-07-22  
**Target repo:** `thomasphall/thomasphall.github.io`  
**Theme:** Jekyll Chirpy  
**Status:** Approved in conversation; awaiting final review before implementation

## Goal

Publish a short (~700–900 word) solution-architect blog post on OpenShift platform and supply-chain security capabilities for regulated hybrid-cloud audiences, compatible with the existing Chirpy blog setup, pushed directly to `main`.

## Audience & voice

- Red Hat Staff Solution Architect / OpenShift specialist
- Customer-facing, practical, confident — no hype
- Emphasize business/compliance outcomes over CLI walkthroughs

## Deliverable

| Item | Value |
| ---- | ----- |
| Path | `_posts/2026-07-22-openshift-security-platform-supply-chain.md` |
| Title | OpenShift Security for Regulated Hybrid Cloud: Platform and Supply Chain |
| Description | How ACS, Compliance Operator, and signed supply-chain controls help teams prove security posture across hybrid OpenShift estates. |
| Categories | `[OpenShift, Security]` |
| Tags | `[acs, compliance, supply-chain, hybrid-cloud]` |
| Timezone | America/Chicago |

## Content outline

1. **Hook** — Regulated teams fail audits from inconsistent hybrid posture, not lack of tools.
2. **Why now** — Platform + supply chain controls that produce repeatable evidence.
3. **RHACS** — Continuous risk visibility and policy across clusters.
4. **Compliance Operator** — Profile-driven scans (e.g. CIS), gaps/remediations; complements ACS; assists auditors, does not replace them.
5. **Signed supply chain** — Image signature verification + Trusted Application Pipeline / Enterprise Contract.
6. **SA takeaway** — Observe → prove → gate the pipeline, on-prem and cloud.
7. **Close** — Soft CTA (non-prod trial / Red Hat conversation).

## Constraints

- Length ~700–900 words
- Accurate to current Red Hat OpenShift / ACS / Compliance Operator documentation
- No secrets, credentials, or customer-identifying detail
- Markdown only; no theme/config changes
- No deep tutorials, screenshots, or YAML dumps
- Push commit to `main` only for the blog post (design/plan docs need not be published on the site)

## Publish path

1. Add Chirpy-compatible post under `_posts/`
2. Commit with a clear message
3. Push to `main` on `thomasphall/thomasphall.github.io`
4. Confirm GitHub Pages / Actions pick up the post

## Out of scope

- Theme customization, comments, analytics
- Multi-post series
- Hands-on lab content
