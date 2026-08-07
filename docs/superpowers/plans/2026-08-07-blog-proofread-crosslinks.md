# Blog Proofread + Cross-Links Implementation Plan

> **For agentic workers:** Implement task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Light-proofread all `_posts/` and add inline + Related posts cross-links per the approved spec.

**Architecture:** Edit each markdown post in place. Keep voice/structure. Add 1–3 inline links where natural; add `## Related posts` before tip/references/closing. Skip forced Related section on the Windows client post.

**Tech Stack:** Jekyll markdown posts under `_posts/`; internal permalinks `/posts/<slug>/`.

## Global Constraints

- Light pass only — no rewrites of voice or architecture
- Related titles must match front-matter `title`
- Windows client: proofread only; no forced Related section
- Spec: `docs/superpowers/specs/2026-08-07-blog-proofread-crosslinks-design.md`

---

## Task 1: Security + secrets cluster

**Files:**
- `_posts/2026-07-22-openshift-security-platform-supply-chain.md`
- `_posts/2026-08-03-external-secrets-vs-secrets-store-csi.md`
- `_posts/2026-08-04-acs-openshift-virtualization.md`
- `_posts/2026-08-07-confidential-ai-openshift-trustee-nras.md`

- [x] Light proofread each file
- [x] Add missing inline links + Related posts per map

## Task 2: Virtualization cluster

**Files:**
- `_posts/2026-07-22-openshift-virtualization-4-22-features.md`
- `_posts/2026-07-23-openshift-virtualization-hardening-priorities.md`
- `_posts/2026-07-27-hosted-vs-virtualized-control-planes.md`
- `_posts/2026-07-27-openshift-virtualization-networking.md`
- `_posts/2026-07-30-mtv-storage-copy-offload-vmware.md`

- [x] Light proofread each file
- [x] Add missing inline links + Related posts per map

## Task 3: Storage + edge + PoC + Windows

**Files:**
- `_posts/2026-07-29-pure-flasharray-sno-nvme-tcp.md`
- `_posts/2026-07-30-openshift-virt-dell-unity-iscsi.md`
- `_posts/2026-08-04-openshift-edge-architectures.md`
- `_posts/2026-07-31-poc-faster-bare-metal-boot-disable-memory-check.md`
- `_posts/2026-07-28-openshift-from-windows-client.md`

- [x] Light proofread each file
- [x] Add Related posts (except Windows)
- [x] Spot-check permalinks resolve to existing posts

## Verification

- [x] Grep `/posts/` links in `_posts/` and confirm all slugs exist
- [x] Confirm Related sections use exact front-matter titles
