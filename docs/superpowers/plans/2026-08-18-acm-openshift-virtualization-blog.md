# ACM OpenShift Virtualization Blog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans in this session (user asked to push). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a Chirpy SA digest on RHACM 2.16 as the fleet control plane for OpenShift Virtualization, with edge-post reciprocal link and SEO checklist updates.

**Architecture:** Match ACS + virt and network-policies posts: disclaimer, thesis hook, five capability sections, one SKU paragraph, numbered takeaway, Related posts. Procedures stay in official docs.

**Tech Stack:** Jekyll Chirpy Markdown under `_posts/`; SEO checklist in `docs/`; GitHub Pages via `gh` PR.

## Global Constraints

- Length ~1,200–1,600 words
- RHACM **2.16**, OpenShift **4.22**, OpenShift Virtualization **4.20.1+**
- Permalink `/posts/acm-openshift-virtualization/`
- Date `2026-08-18 06:00:00 -0500` (must be in the past at Jekyll build)
- Tags `[acm, openshift, openshift-virtualization]`
- At most one YAML snippet (VM `backup-vm` label); no install runbooks
- Do not invent ACM actions or call live migration / right-sizing Technology Preview
- Backup ≠ Metro/Regional DR; migration ≠ backup
- ACM for Virtualization SKU: one paragraph only

---

### Task 1: Write the post

**Files:**
- Create: `_posts/2026-08-18-acm-openshift-virtualization.md`

- [x] **Step 1: Draft full Chirpy post per** `docs/superpowers/specs/2026-08-18-acm-openshift-virtualization-blog-design.md`
- [x] **Step 2: Word-count and SEO front-matter check** (title ~55 chars, description 150–160, 1,200–1,600 words)

### Task 2: Reciprocal and SEO wiring

**Files:**
- Modify: `_posts/2026-08-04-openshift-edge-architectures.md` (Related posts + one inline sentence)
- Modify: `docs/seo-post-checklist.md` (add `acm` tag; Virtualization cluster row)

- [x] **Step 1: Reciprocal link on the edge post**
- [x] **Step 2: SEO checklist tag + cluster row**

### Task 3: Publish

**Files:** feature branch `blog/acm-openshift-virtualization`

- [ ] **Step 1: Commit spec, plan, post, and wiring**
- [ ] **Step 2: Push and open PR with `gh`**
