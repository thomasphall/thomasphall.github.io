# Design: ACM as Fleet Control Plane for OpenShift Virtualization

**Date:** 2026-08-18  
**Target repo:** `thomasphall/thomasphall.github.io`  
**Theme:** Jekyll Chirpy  
**Status:** Drafted at `_posts/2026-08-18-acm-openshift-virtualization.md`; branch `blog/acm-openshift-virtualization`

## Goal

Produce a solution-architect digest (~1,200–1,600 words) on why
[Red Hat Advanced Cluster Management for Kubernetes (RHACM) 2.16](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/2.16/)
is the fleet control plane once
[OpenShift Virtualization](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/index)
spans more than one cluster. Cover inventory and VM actions, Observability and
right-sizing, policy-driven OADP backup, GA cross-cluster live migration, and
fine-grained VM RBAC. One-paragraph ACM for Virtualization SKU callout. Minimal
YAML; no install runbook.

## Audience & voice

- Red Hat Staff Solution Architect / OpenShift specialist
- Customer-facing, practical, confident — no hype
- Outcome-focused talking points for CNV + fleet conversations
- Match `_posts/2026-08-04-acs-openshift-virtualization.md` and
  `_posts/2026-08-17-openshift-network-policies.md`

## Approach

**Fleet-outcomes field guide** (selected over a 2.16 changelog digest and a
short room-script). Thesis first; 2.16 capabilities as evidence. Procedures
live in official docs, not in the post.

## Angle

Once OpenShift Virtualization spans more than one cluster, the OpenShift
console is the wrong control plane. VMs are still Kubernetes resources
(`VirtualMachine`, virt-launcher pods), so a hub can inventory, act, observe,
back up, and migrate them. RHACM 2.16 is that hub—with RBAC so those actions
are not cluster-admin for everyone.

## Front matter (locked)

| Item | Value |
| ---- | ----- |
| Path | `_posts/2026-08-18-acm-openshift-virtualization.md` |
| Title | ACM as the Fleet Control Plane for OpenShift VMs |
| Description | Why RHACM 2.16 is the fleet hub for OpenShift Virtualization across clusters: inventory, Observability, policy-driven backup, live migration, and VM RBAC. |
| Permalink | `/posts/acm-openshift-virtualization/` |
| Categories | `[OpenShift, Virtualization]` |
| Tags | `[acm, openshift, openshift-virtualization]` |
| Date | `2026-08-18` America/Chicago (`-0500`); time in the past at build |
| Disclaimer | Standard personal-site prompt used on other Red Hat product posts |

Title is ~51 characters. Description is ~153 characters. Tag `acm` is the post
topic (allowed one-off that we expect to reuse).

## Versions (locked)

- RHACM **2.16** (current GA line; hub supported on OpenShift **4.22**)
- OpenShift Container Platform **4.22** (this site’s latest stable)
- OpenShift Virtualization **4.20.1 or later** for ACM Virtualization
  features; 4.22 satisfies that floor
- Do not write ACM 2.15-only caveats as if they still block 2.16 + 4.22

Authoritative product pages:

- [ACM 2.16 Virtualization](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/2.16/html/virtualization/acm-virt)
- [ACM 2.16 release notes](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/2.16/html/release_notes/acm-release-notes)
- [ACM 2.16 support matrix](https://access.redhat.com/articles/7136928)

## Content outline

1. **Hook** — Cluster-local virt UI does not scale. VMs remain Kubernetes
   resources, so a hub can operate them. Point at ACM Virtualization docs.
2. **Inventory and actions** — Search across managed clusters; Fleet
   Virtualization console. Actions: start, stop, restart, pause, unpause,
   snapshot. Day-2 is inventory plus control, not YAML per cluster.
3. **Observability and right-sizing** — Observability service → Grafana VM
   dashboards from the Virtual Machine page. `RightSizingRecommendation` is
   **GA in 2.16**; namespace and virtualization right-sizing are enabled by
   default once Observability is on. Capacity talk, not a Grafana tutorial.
4. **Policy-driven backup** — OADP via ACM virtualization policies. Supported:
   CSI backups and CSI with DataMover. **Not** supported: file-system backup,
   volume-snapshot backup. Mechanism: label `ManagedCluster` with
   `acm-virt-config`; label `VirtualMachine` with
   `cluster.open-cluster-management.io/backup-vm: <schedule>`. This is
   backup/restore, **not** Metro/Regional DR.
5. **Cross-cluster live migration** — **GA in 2.16**. Hub enables
   `cnv-mtv-integrations`; source/target clusters labeled
   `acm/cnv-operator-install: "true"`; MTV on the hub. Use: maintenance and
   load, not backup. Note the operational implication: enabling migration can
   install OpenShift Virtualization on labeled managed clusters.
6. **Fine-grained RBAC** — **GA in 2.16**. `MultiClusterRoleAssignment` on the
   hub. Roles to name: `acm-vm-fleet:view` / `acm-vm-fleet:admin` (Fleet
   console; admin required for cluster-to-cluster live migration),
   `acm-vm-extended:view` / `acm-vm-extended:admin`,
   `acm-vm-cluster-migration:view`. Point: VM admins are not cluster-admins.
7. **SKU callout (one paragraph)** — ACM for Virtualization is the same
   ACM codebase, entitled only for OpenShift Virtualization Engine clusters
   and VMs. Mixed container + VM fleets stay on ACM for Kubernetes (Platform
   Plus / full ACM). Do not turn this into a licensing essay.
8. **SA takeaway + related posts** — Numbered outcomes; soft CTA; Related
   posts; optional short official-docs list.

## Accuracy guardrails

State only what ACM 2.16 docs and the 2.16 Red Hat product blog support:

| Claim | Status | Do not say |
| ----- | ------ | ---------- |
| Search + VM actions (start/stop/restart/pause/unpause/snapshot) | Documented | Invent extra actions (live migrate from Search as a sixth button unless docs show it) |
| Observability Grafana VM dashboards | Documented | Invent metric names |
| Right-sizing recommendations | **GA** in 2.16 (Observability) | Call it Technology Preview |
| OADP policy backup for VMs | Documented; CSI / CSI+DataMover | Call it ODF Metro/Regional DR; claim filesystem or volume-snapshot backup |
| Cross-cluster live migration | **GA** in 2.16 | Call it TP; treat it as disaster recovery |
| Fine-grained VM RBAC / `MultiClusterRoleAssignment` | **GA** in 2.16 | Invent extra role names |
| ACM for Virtualization SKU | OVE-only entitlement | Claim it manages arbitrary OpenShift or non-OVE clusters |

Optional YAML (at most **one** short snippet): either the `ManagedCluster`
`acm-virt-config` label or the `VirtualMachine`
`cluster.open-cluster-management.io/backup-vm` label. No OADP ConfigMap
dumps, no `MultiClusterHub` full specs, no `MultiClusterRoleAssignment`
manifests.

## Cross-links

Inline plus `## Related posts` (use exact titles):

- [OpenShift Edge Architectures: Form Factor, Then Fleet](/posts/openshift-edge-architectures/) — RHACM as fleet multiplier
- [What's New in OpenShift Virtualization 4.22](/posts/openshift-virtualization-4-22-features/) — cluster-local virt ops vs hub
- [Hosted vs Virtualized Control Planes on OpenShift 4.22](/posts/hosted-vs-virtualized-control-planes/) — densify control planes, ACM still the hub
- [RHACS for OpenShift Virtualization Workloads](/posts/acs-openshift-virtualization/) — complementary security plane

PoC (further reading, not a dump of the nav):

- [Advanced Cluster Management (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/fleet-management/acm-install/)
- [OpenShift Virtualization (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/post-installation/virtualization/)

**Reciprocal:** add this post to Related posts (and a one-sentence inline
pointer if natural) on `_posts/2026-08-04-openshift-edge-architectures.md`.

**SEO checklist:** add `acm` to reusable tags; add this permalink to the
Virtualization topic-cluster row in `docs/seo-post-checklist.md`.

## Constraints

- Length ~1,200–1,600 words
- Accurate to Red Hat docs; do not invent ACM capabilities
- Label GA vs caveats honestly (backup storage types; migration ≠ DR)
- Personal-site disclaimer immediately after front matter
- No secrets, credentials, or customer-identifying detail
- Markdown only; YAML filenames `.yaml` if mentioned
- Minimal CLI (zero preferred; at most one `oc` pointer in prose, not a lab)
- Follow `docs/seo-post-checklist.md`

## Out of scope

- ACM install, hub sizing, or MCE-only cluster lifecycle how-to
- ACM for Virtualization licensing deep-dive (one paragraph only)
- ODF Metro/Regional DR for VMs
- Guest OS hardening (existing virt-hardening post)
- MTV from VMware (existing offload post)
- Ansible Event-Driven ACM integrations
- AI-enabled search / MCP (Technology Preview in 2.16; not this thesis)
- Full GitOps Application lifecycle for VM CRs
- Generating an AI prompt instead of the post

## Deliverables

1. Design spec (this file)
2. Implementation plan
3. Chirpy post + edge-post reciprocal link + SEO checklist tag/cluster update

## Publish path

1. Feature branch from `main`
2. Add post under `_posts/` plus the reciprocal and SEO checklist edits
3. Commit, push, open PR with `gh`
