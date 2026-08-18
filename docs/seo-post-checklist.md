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
- [ ] `categories` — 1–2 stable pillars (e.g. Security, OpenShift)
- [ ] `tags` — **2–6** from the reusable set below. Do not mint a one-off tag
      unless you expect more posts on that term (product names that *are* the
      post topic are fine: `lightwell`, `tesla`, `dell-unity`).
- [ ] `permalink` — `/posts/<stable-slug>/` (do not change after publish)

Reusable tags in use today: `openshift`, `openshift-virtualization`,
`security`, `storage`, `gitops`, `homelab`, `automation`, `synology`,
`acs`, `acm`, `supply-chain`, `networking`, `csi`, `sno`, `edge`, `secrets`,
`migration`, `vmware`, `bare-metal`, `ansible`, `windows`,
`hosted-control-planes`, `confidential-computing`, `trustee`, `lightwell`,
`pure-storage`, `dell-unity`, `blink`, `tesla`, `vsan`.

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
      the Windows client how-to)
- [ ] Reciprocal link from at least one hub/peer post in the same cluster

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

## After publish

- [ ] Confirm the live URL matches `permalink`
- [ ] Share with a descriptive LinkedIn blurb (title + one-sentence hook)
- [ ] If Search Console is verified, check Coverage / Performance for the URL
  after a few days

## Topic clusters (for linking)

| Cluster | Hub / peers |
| ------- | ----------- |
| Security / supply chain | Platform supply-chain, ACS + Virt, External Secrets, Confidential AI, Lightwell, network policies |
| Virtualization | 4.22 features, hardening, networking, hosted vs VCP, MTV offload, OVE vSAN-like storage, network policies, ACM fleet virt |
| Storage / edge | OVE vSAN-like storage, Pure NVMe/TCP, Dell Unity iSCSI, edge architectures, PoC boot tip |
| Homelab / automation | Blink Synology archive, Tesla Sentry Synology archive |

See also: [blog SEO wiring design](superpowers/specs/2026-08-13-blog-seo-wiring-design.md).
