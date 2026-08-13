# Cybertruck Sentry → Synology Blog Implementation Plan

> **For agentic workers:** Execute inline in this session (user requested “write it”). Checkbox steps track progress.

**Goal:** Ship a Chirpy blog post on Cybertruck + Pi 4 + Sentry-USB-Rusty → Synology SMB archival, with Blink reciprocal links and SEO checklist Homelab cluster update.

**Architecture:** Mirror the Blink Homelab post: disclaimer, constraints, stack table, ASCII architecture, practical checklist, four lessons, risks/takeaways, Related posts.

**Tech Stack:** Jekyll Chirpy Markdown under `_posts/`; SEO checklist in `docs/`.

## Global Constraints

- Length ~1,100–1,400 words; Blink voice
- Lessons only: power/cable, home Wi‑Fi sync, truck sleep/Keep Awake, dedicated Synology SMB user
- No secrets/hostnames/passwords; name Sentry-USB-Rusty; link upstream docs
- Mention disable Encrypt Dashcam Recordings if vehicle offers it (2026.20+)
- Permalink `/posts/cybertruck-sentry-synology-archive/`; date after Blink `14:00:00 -0500`

---

### Task 1: Write the post

**Files:**
- Create: `_posts/2026-08-13-cybertruck-sentry-synology-archive.md`

- [x] **Step 1: Draft full Chirpy post per approved design**
- [x] **Step 2: Word-count / SEO front-matter sanity check** (~1,155 words; description ~150 chars)

### Task 2: Reciprocal Homelab wiring

**Files:**
- Modify: `_posts/2026-08-13-blink-camera-synology-archive.md` (Related posts + inline)
- Modify: `docs/seo-post-checklist.md` (Homelab cluster row)

- [x] **Step 1: Add Related posts + inline link on Blink post**
- [x] **Step 2: Add Homelab cluster to SEO checklist**

### Task 3: Commit (only if user asks)

- [ ] Do not commit unless user requests
