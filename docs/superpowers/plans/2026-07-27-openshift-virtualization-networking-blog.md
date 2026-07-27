# OpenShift Virtualization Networking Blog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish one Chirpy-compatible SA brief on OpenShift Virtualization networking (pod network → UDN → host/localnet → CUDN YAML → Linux bridge exception) for OpenShift 4.22.

**Architecture:** Single Markdown file under `_posts/` with Chirpy front matter. GitHub Actions `pages-deploy.yml` builds and deploys on merge to `main`. Design/plan under `docs/superpowers/` are repo-only.

**Tech Stack:** Jekyll, jekyll-theme-chirpy, GitHub Pages Actions

## Global Constraints

- Repo: `thomasphall/thomasphall.github.io`
- Branch: `cursor/openshift-virt-networking-post`
- Filename: `_posts/2026-07-27-openshift-virtualization-networking.md`
- Length: ~1,800–2,200 words
- Voice: Red Hat SA; mixed OpenShift + VMware-leaning readers; VMware analogies only where clarifying
- Version: OpenShift 4.22; CUDN/localnet modern path; hand-authored NAD as brief compatibility note
- YAML: field-guide density (dual-bond NNCP + complete localnet CUDN attach)
- Personal-site disclaimer prompt required
- Do not modify `_config.yml`, theme files, or workflows
- Do not commit PPTX or `.tmp-pptx-extract*`
- Do not include unsupported multi-NAD same-segment workarounds

## File structure

| Path | Responsibility |
| ---- | -------------- |
| `_posts/2026-07-27-openshift-virtualization-networking.md` | Published blog post |
| `docs/superpowers/specs/2026-07-27-openshift-virtualization-networking-blog-design.md` | Approved design (on `main`) |
| `docs/superpowers/plans/2026-07-27-openshift-virtualization-networking-blog.md` | This plan |

---

### Task 1: Write Chirpy blog post

**Files:**
- Create: `_posts/2026-07-27-openshift-virtualization-networking.md`

**Interfaces:**
- Consumes: Design spec outline and must-cover list
- Produces: Post at `/posts/openshift-virtualization-networking/` after Pages deploy

- [x] **Step 1: Write post** covering layered outline (hook → CNI/Multus → pod/masquerade → UDN → host arch → dual-bond + CUDN YAML → VM attach → Linux bridge exception → when-to-choose)
- [x] **Step 2: Verify** front matter keys, disclaimer, ~1,800–2,200 words, 4.22 docs links, no PPTX committed
- [ ] **Step 3: Commit** post + plan on feature branch
- [ ] **Step 4: Push and open PR** into `main` when requested

### Task 2: Self-review against design must-cover list

- [x] Masquerade + migration IP behavior
- [x] UDN topologies/roles for VMs (Layer2 primary, localnet secondary)
- [x] CUDN modern VLAN path; auto-generated NADs
- [x] Bridge mapping + dual-bond NNCP YAML
- [x] Complete VM attach for localnet CUDN
- [x] Linux bridge exception for VGT
