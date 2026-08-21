# Post front-matter SEO checklist

Use this when drafting or shipping a post under `_posts/`. Chirpy +
`jekyll-seo-tag` already emit titles, meta descriptions, Open Graph, and
canonicals from front matter.

## Site-level titles

Homepage and paginated indexes share Chirpy’s `layout: home`, so they would
otherwise all title as `site.title`. `_plugins/home-seo-title.rb` rewrites
them after render:

| URL        | Title                                      |
| ---------- | ------------------------------------------ |
| `/`        | `{{ site.title }} \| {{ site.tagline }}`   |
| `/pageN/`  | `Page N \| {{ site.title }}`               |

Set `title` and `tagline` in `_config.yml`. Do not put the topic into
`site.title` — that string is the suffix on every post (`Post | Thomas Hall`).

## Required front matter

- [ ] `title` — clear, query-shaped (what someone would search), not only clever.
      Keep the visible title around **55 characters** so Google does not
      truncate the useful keywords (`Post | Thomas Hall` also consumes SERP
      space).
- [ ] `description` — 1–2 sentences (**150–160 characters**) that answer the
      query; used as the meta description / OG blurb
- [ ] `date` — with timezone offset (site is `America/Chicago`). Must be in
      the past at build time; Jekyll skips future-dated posts, htmlproofer
      then fails on reciprocal links, and GitHub Pages never publishes.
- [ ] `categories` — 1–2 of `OpenShift`, `Virtualization`, `Security`,
      `Homelab`, `Automation`. Do not mint one-off pillars (`Platform`,
      `Bare Metal`, `Networking`, `Supply Chain`, `Migration`); those are tags.
- [ ] `tags` — **2–6** from the reusable set below. Do not mint a one-off tag
      unless you expect more posts on that term (product names that *are* the
      post topic are fine: `lightwell`, `tesla`, `dell-unity`). Virt posts
      always include `openshift-virtualization` and `openshift`. Add `gitops`
      when GitOps is a design recommendation, not only when it is the title.
- [ ] `permalink` — `/posts/<stable-slug>/` (do not change after publish).
      If an already-public URL must move, add a row to
      `_data/legacy-redirects.yaml` instead of editing `permalink`.

Reusable tags in use today: `openshift`, `openshift-virtualization`,
`security`, `storage`, `gitops`, `homelab`, `automation`, `synology`,
`acs`, `acm`, `supply-chain`, `networking`, `csi`, `sno`, `edge`, `secrets`,
`migration`, `vmware`, `bare-metal`, `ansible`, `windows`,
`hosted-control-planes`, `confidential-computing`, `trustee`, `lightwell`,
`pure-storage`, `dell-unity`, `blink`, `tesla`, `vsan`, `karpenter`, `rosa`.

Example:

```yaml
---
title: "External Secrets vs Secrets Store CSI on OpenShift"
description: >-
  How External Secrets Operator and the Secrets Store CSI Driver differ on
  OpenShift: sync into Kubernetes Secrets versus mount at runtime for
  platform teams.
date: 2026-08-03 08:00:00 -0500
categories: [OpenShift, Security]
tags: [openshift, security, secrets, gitops]
permalink: /posts/external-secrets-vs-secrets-store-csi/
---
```

## Strongly recommended

- [ ] Personal-site disclaimer prompt near the top when Red Hat products are discussed
- [ ] 2–3 **inline** links to related posts where the topic already appears
- [ ] `## Related posts` with 2–4 bullets using exact target `title` text and
      `/posts/<slug>/` permalinks (skip only for weakly related posts, e.g.
      the Windows client how-to; two-post clusters such as homelab may use 1)
- [ ] Reciprocal link from at least one hub/peer post in the same cluster
- [ ] Closing H2: `## The SA takeaway` on decision posts, `## Wrap-up` on lab
      runbooks, `## Takeaways` on homelab
- [ ] Official docs under `## Further reading` (not `## References` or
      `### References`)
- [ ] Decision posts: one `Want help…` CTA (`prompt-tip`). Skip Windows and
      homelab. Lab runbooks may skip it.
- [ ] First mention: full product name plus short form, then the short form
      only. `Red Hat Advanced Cluster Security for Kubernetes (RHACS)` →
      `RHACS`. `Red Hat Advanced Cluster Management for Kubernetes (RHACM)` →
      `RHACM`. Do not bounce to `ACS`/`ACM` in the same post unless the
      sentence is a label, CR, SKU (`ACM for Virtualization`), or a post title.
- [ ] Single Node OpenShift (no hyphen) in titles and body.

## Optional

- [ ] `og_image: /assets/img/og/<slug>.png` — per-post 1200×630 social
      preview (LinkedIn/Twitter). Do **not** use Chirpy’s `image:` for these
      cards; `image:` is rendered as a cover photo at the top of the post.
      Default fallback is `assets/img/og/site.png`.
- [ ] External “Further reading” for official docs (does not replace Related posts).
      When a post overlaps an OpenShift PoC topic, link the matching page on
      [openshift-ssa.github.io/openshift-poc](https://openshift-ssa.github.io/openshift-poc/home/)
      (home plus the specific install/day-2 page—not a generic dump of the
      whole nav).

## URL stability

Published post permalinks are inbound links (LinkedIn, Search Console). Never
rename `/posts/<slug>/` after the first successful deploy. Title changes are
safe; they do not affect the URL.

When an old public path would 404 (slug rename, dropped category archive), add
it to `_data/legacy-redirects.yaml`. `_plugins/legacy-redirects.rb` writes a
stub page at `from` that canonicalizes and meta-refreshes to `to`. GitHub Pages
cannot send HTTP 301, so the stub responds 200.

Keep the house-style category set; do not restore dropped categories on posts
just to preserve `/categories/<old>/` — redirect those archives instead.

## After publish

- [ ] Confirm the live URL matches `permalink`
- [ ] Share with a descriptive LinkedIn blurb (title + one-sentence hook)
- [ ] If Search Console is verified, check Coverage / Performance for the URL
  after a few days

## Topic clusters (for linking)

| Cluster | Hub / peers |
| ------- | ----------- |
| Security / supply chain | Platform supply-chain, RHACS + Virt, External Secrets, Confidential AI, Lightwell, network policies, Network Observability |
| Virtualization | 4.22 features, hardening, networking, hosted vs VCP, MTV offload, VDDK portal / MTV, AI agents for MTV, OVE vSAN-like storage, network policies, ACM fleet virt, Network Observability |
| GitOps / ACM fleet | ACM fleet virt, GitOps should manage ACM, edge architectures, network policies GitOps split, External Secrets, getting started |
| ROSA / autoscaling | Karpenter vs machine pools, hosted vs VCP |
| Storage / edge | OVE vSAN-like storage, storage performance (disks/IOPS), Pure NVMe/TCP, Dell Unity iSCSI, edge architectures, PoC boot tip |
| PoC / on-prem install | Getting started with an OpenShift PoC, PoC boot tip, edge architectures, hosted vs VCP, GitOps should manage ACM, Network Observability |
| Homelab / automation | Blink Synology archive, Tesla Sentry Synology archive |
