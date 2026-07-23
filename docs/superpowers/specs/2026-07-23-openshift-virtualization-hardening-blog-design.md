# Design: OpenShift Virtualization Hardening Priorities Blog

**Date:** 2026-07-23  
**Target repo:** `thomasphall/thomasphall.github.io`  
**Theme:** Jekyll Chirpy  
**Status:** Approved in conversation; awaiting final review before implementation plan

## Goal

Publish a solution-architect digest (~1,100–1,400 words) of the most important security controls from the December 2025 *Red Hat OpenShift Virtualization hardening guide*, organized by attack surface. Outcome-focused like the existing ACS/platform security post—not a full CIS-style audit script. Deliver via feature branch and pull request into `main`.

## Audience & voice

- Red Hat Staff Solution Architect / OpenShift specialist
- Customer-facing, practical, confident — no hype
- Emphasize blast-radius reduction and least privilege over CLI walkthroughs
- Useful for VMware migration and day-2 CNV conversations without being framed as a migration narrative

## Source material

- Local PDF: `rh-openshift-virtualization-hardening-guide-detail-202512-en.pdf` (Dec 2025)
- Scope notes from the guide that must appear in the post:
  - Harden OpenShift / RHCOS first (Compliance Operator profiles)
  - Guest OS hardening is out of scope / separate
  - Guide follows CIS formatting conventions but is not affiliated with CIS; Red Hat is formalizing an OpenShift Virtualization CIS benchmark

## Approach

**Attack-surface themes** (selected over day-1 sequence and risk-tier scoring): group Level 1/2 controls into who can touch the platform, what can leave the host into a VM, how disks move data, how networks isolate tenants, and brief host posture.

## Deliverable

| Item | Value |
| ---- | ----- |
| Path | `_posts/2026-07-23-openshift-virtualization-hardening-priorities.md` |
| Title | Hardening OpenShift Virtualization: Security Priorities That Matter First |
| Description | The highest-impact controls from the OpenShift Virtualization hardening guide—RBAC, device pass-through, storage isolation, and network segmentation—for platform teams. |
| Categories | `[OpenShift, Virtualization, Security]` |
| Tags | `[openshift-virtualization, hardening, security, rbac, networking]` |
| Permalink | `/posts/openshift-virtualization-hardening-priorities/` |
| Timezone | America/Chicago (`-0500`) |

## Content outline

1. **Hook** — Virtualization on OpenShift inherits platform hardening, but OpenShift Virtualization adds its own blast radius (devices, disks, consoles, migrations).
2. **Prerequisite** — Harden OpenShift/RHCOS first (Compliance Operator); guest OS hardening is separate; CIS-format disclaimer.
3. **Who can touch the platform (RBAC)**  
   - Restrict live migration / MigrationPolicy create  
   - Restrict `oc exec` and VNC/token generate  
   - Lock down cluster instance types / preferences and CDI CR updates
4. **What can leave the host into a VM (devices & features)**  
   - Permit only approved GPU/USB/host devices  
   - Keep privileged feature gates closed (`persistentReservation`, `downwardMetrics`; note `nonRoot` default from 4.18+)
5. **How disks move and share data (storage)**  
   - No unintended cross-namespace DataVolume cloning  
   - Avoid shareable disks and `errorPolicy: ignore` unless required
6. **How networks isolate tenants**  
   - Dedicated VLANs / secondary networks  
   - MAC spoof filtering  
   - MultiNetworkPolicy microsegmentation (OVN localnet)
7. **Host posture (short)** — Nested virtualization off unless needed; confirm CPU vulnerability mitigations.
8. **SA takeaway** — Least privilege → least device surface → least data sharing → network segmentation; configure via HyperConverged/GitOps, not ad-hoc JSON patches on underlying components.
9. **Close** — Point readers to the official hardening guide; soft CTA for a Red Hat / architecture conversation.

## Priority controls (must cover)

These eight themes are in scope for the body (may share subsections):

1. Migration and MigrationPolicy RBAC
2. Exec / VNC console access
3. Cluster instance types, preferences, and CDI update rights
4. Host device / GPU / USB pass-through allowlists
5. Feature gates: persistent reservations, downward metrics (nonRoot note)
6. Cross-namespace DataVolume cloning and shareable disks / errorPolicy
7. VLAN segmentation, MAC spoof filtering, MultiNetworkPolicy
8. Nested virtualization and CPU vulnerability mitigations (brief)

## Constraints

- Length ~1,100–1,400 words
- Accurate to the Dec 2025 hardening guide; do not invent controls or claim CIS certification
- Include personal-site disclaimer prompt used on other posts
- No secrets, credentials, or customer-identifying detail
- Markdown only; no theme/config changes
- Outcome-focused: minimal audit commands, no YAML dumps or full remediation scripts
- May lightly cross-link the existing platform/supply-chain security post and the OpenShift Virtualization 4.22 features post if already published
- Design/plan docs live under `docs/superpowers/` and need not ship on the site

## Publish path

1. Create feature branch from `main` (for example `feature/openshift-virt-hardening-blog`)
2. Add Chirpy-compatible post under `_posts/`
3. Commit with a clear message
4. Push branch and open PR to `main` with `gh`
5. After merge, confirm GitHub Pages / Actions pick up the post at  
   `https://thomasphall.github.io/posts/openshift-virtualization-hardening-priorities/`

## Out of scope

- Full reproduction of every guide check (file permissions, KSM, Intel TXT, HCO annotation patch audits, vCPU metrics kernel arg)
- Hands-on lab content, screenshots, or Ansible automation in this post
- Theme customization, comments, analytics
- Claiming the guide is an official CIS benchmark
