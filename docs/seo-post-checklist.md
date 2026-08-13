# Post front-matter SEO checklist

Use this when drafting or shipping a post under `_posts/`. Chirpy +
`jekyll-seo-tag` already emit titles, meta descriptions, Open Graph, and
canonicals from front matter.

## Required front matter

- [ ] `title` — clear, query-shaped (what someone would search), not only clever
- [ ] `description` — 1–2 sentences (~150–160 characters) that answer the query;
      used as the meta description / OG blurb
- [ ] `date` — with timezone offset (site is `America/Chicago`)
- [ ] `categories` — 1–2 stable pillars (e.g. Security, Platform)
- [ ] `tags` — specific terms readers/search might use (products, protocols)
- [ ] `permalink` — `/posts/<stable-slug>/` (do not change after publish)

Example:

```yaml
---
title: "External Secrets Operator vs Secrets Store CSI on OpenShift 4.22"
description: >-
  When to use External Secrets Operator versus Secrets Store CSI Driver on
  OpenShift 4.22 for vault-backed secrets without committing them to Git.
date: 2026-08-03 08:00:00 -0500
categories: [Platform, Security]
tags: [external-secrets, secrets-store-csi, vault, openshift]
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

- [ ] `image: /path/or/url` — per-post social preview (overrides site
      `social_preview_image` in `_config.yml`)
- [ ] External “Further reading” for official docs (does not replace Related posts)

## After publish

- [ ] Confirm the live URL matches `permalink`
- [ ] Share with a descriptive LinkedIn blurb (title + one-sentence hook)
- [ ] If Search Console is verified, check Coverage / Performance for the URL
  after a few days

## Topic clusters (for linking)

| Cluster | Hub / peers |
| ------- | ----------- |
| Security / supply chain | Platform supply-chain, ACS + Virt, External Secrets, Confidential AI, Lightwell |
| Virtualization | 4.22 features, hardening, networking, hosted vs VCP, MTV offload |
| Storage / edge | Pure NVMe/TCP, Dell Unity iSCSI, edge architectures, PoC boot tip |
| Homelab / automation | Blink Synology archive, Tesla Sentry Synology archive |

See also: [blog SEO wiring design](superpowers/specs/2026-08-13-blog-seo-wiring-design.md).
