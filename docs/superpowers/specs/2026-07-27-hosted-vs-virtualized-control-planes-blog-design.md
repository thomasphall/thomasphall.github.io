# Design: Hosted vs Virtualized Control Planes Blog

**Date:** 2026-07-27  
**Target repo:** `thomasphall/thomasphall.github.io`  
**Theme:** Jekyll Chirpy  
**Status:** Approved in conversation; awaiting final review before implementation plan

## Goal

Publish a solution-architect brief (~1,500–1,800 words) comparing **hosted control planes (HCP)** and **virtualized control planes (VCP)** for OpenShift Container Platform 4.22. Densification is the main thread; OpenShift Virtualization is the hosting substrate. Decision-first structure so platform and virtualization readers can choose an architecture quickly, then understand day-2 differences.

## Audience & voice

- Primary: platform / OpenShift architects **and** virtualization / VMware-migration teams
- Red Hat Staff Solution Architect / OpenShift specialist tone
- Customer-facing, practical, confident — no hype
- Emphasize isolation model, ops model, and when-to-choose guidance over install walkthroughs

## Source material

- [Virtualized control planes overview (OCP 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualized_control_planes/vcp-overview)
- [Hosted control planes overview (OKD/OCP 4.22)](https://docs.okd.io/4.22/hosted_control_planes/index.html)
- Related Red Hat docs on HCP networking / isolation models where needed for accuracy
- Existing site posts for voice and Chirpy front matter patterns:
  - `_posts/2026-07-22-openshift-virtualization-4-22-features.md`
  - `_posts/2026-07-23-openshift-virtualization-hardening-priorities.md`

## Approach

**Decision-first** (selected over architecture-first and scenario-first): open with densification, define both models, call out Technology Preview once, present a comparison table, expand into ops differences, clarify OpenShift Virtualization as host for both, close with when-to-choose guidance.

## Deliverable

| Item | Value |
| ---- | ----- |
| Path | `_posts/2026-07-27-hosted-vs-virtualized-control-planes.md` |
| Title | Hosted vs Virtualized Control Planes on OpenShift 4.22 |
| Description | How hosted and virtualized control planes differ on OpenShift 4.22—isolation, densification, and day-2 operations—when OpenShift Virtualization is the hosting substrate. |
| Categories | `[OpenShift, Virtualization]` |
| Tags | `[hosted-control-planes, virtualized-control-planes, openshift-virtualization, "4.22", hypershift]` |
| Permalink | `/posts/hosted-vs-virtualized-control-planes/` |
| Timezone | America/Chicago (`-0500`) |

## Content outline

1. **Hook** — Multi-cluster densification: fewer dedicated control-plane machines, more clusters. OpenShift Virtualization is often the hosting substrate; the real choice is isolation model and ops model.
2. **Definitions (short)**  
   - **HCP:** control plane as pods on a management cluster (HyperShift / multicluster engine); workers via `NodePool`; container-level isolation by default.  
   - **VCP:** control plane nodes as VMs on a hosting cluster with OpenShift Virtualization; target cluster looks like a normal install; hypervisor-level isolation.
3. **TP callout (once)** — VCP via KubeVirt Redfish is Technology Preview in 4.22; not covered by production SLAs. Then compare architectures fairly without dwelling on support status.
4. **Comparison table** — isolation, form factor, install path, management APIs, worker attachment, typical densification shape.
5. **Ops differences (deep section)**  
   - Lifecycle / updates (coupled standalone-style vs control plane + node pools)  
   - etcd / storage posture  
   - Networking (direct vs Konnectivity)  
   - Operators & day-2 surface (`ClusterVersion`/CVO vs `HostedCluster`)  
   - Install familiarity (Agent/ZTP + Redfish-shaped BMCs for VCP vs `HostedCluster`/`NodePool` for HCP)
6. **OpenShift Virtualization as host** — both can sit on CNV; HCP treats virt as a provider platform; VCP treats virt as the place control-plane VMs live. Clarify they are not “HCP vs CNV.”
7. **When to choose which** — decision guidance for densification, regulatory/isolation needs, and preserve-standalone-install workflows.
8. **Close** — links to official 4.22 HCP and VCP docs; soft CTA; personal-site disclaimer. Light cross-link to the existing 4.22 Virtualization features post if natural.

## Must get right

- HCP = pods / container-level isolation; VCP = VMs / hypervisor-level isolation (official distinction)
- VCP KubeVirt Redfish = Technology Preview (stated once early; do not claim production readiness)
- HCP on OpenShift Virtualization is a hosting-platform path; do not conflate “HCP on CNV” with VCP
- Terminology: management/hosting cluster for HCP; hosting cluster + target cluster for VCP
- Accurate ops notes: updates, Konnectivity, `HostedCluster`/`NodePool` vs standalone-style install for VCP

## Constraints

- Length ~1,500–1,800 words
- Accurate to OpenShift Container Platform 4.22 documentation; do not invent GA claims
- Include personal-site disclaimer prompt used on other posts
- No secrets, credentials, or customer-identifying detail
- Markdown only; no theme/config changes
- Outcome-focused: comparison and decision guidance; minimal CLI; no YAML dumps or install runbooks
- May lightly cross-link the existing OpenShift Virtualization 4.22 features post
- Design/plan docs live under `docs/superpowers/` and need not ship on the site

## Publish path

1. Create feature branch from `main` (for example `feature/hosted-vs-virtualized-control-planes-blog`)
2. Add Chirpy-compatible post under `_posts/`
3. Commit with a clear message
4. Push branch and open PR to `main` with `gh`
5. After merge, confirm GitHub Pages / Actions pick up the post at  
   `https://thomasphall.github.io/posts/hosted-vs-virtualized-control-planes/`

## Out of scope

- Step-by-step install procedures
- Full HCP provider matrix (AWS, bare metal, IBM Z, OpenStack, etc.) beyond noting OpenShift Virtualization as one platform
- Cost modeling or sizing calculators
- Deep dive into Redfish API configuration
- Claiming production readiness for Technology Preview features
- Full reproduction of every HCP vs standalone comparison table from the docs
