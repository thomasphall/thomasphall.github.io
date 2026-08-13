# Blog SEO Wiring Design

Date: 2026-08-13  
Status: Approved

## Goal

Improve discoverability for the Chirpy/Jekyll personal blog with Search Console
wiring (placeholders), a reusable post front-matter SEO checklist, and a
focused internal-linking pass for posts missing Related coverage.

## Scope

In scope:

- Placeholder + docs for Google/Bing webmaster verification in `_config.yml`
- README steps to verify the site and submit `/sitemap.xml`
- Authoring checklist for post front matter and internal links
- Lightwell post Related section + reciprocal link from the supply-chain hub
- Spot-check: Windows client remains without a forced Related section

Out of scope:

- Committing real Search Console / Bing verification tokens
- Site-wide title/description rewrites
- Custom per-post Open Graph images
- Analytics setup

## Approach

1. **Search Console wiring** — Keep Chirpy’s `webmaster_verifications` keys;
   document how to paste the meta-tag content token and submit the sitemap.
2. **SEO checklist** — Single markdown checklist linked from the README for
   every new post.
3. **Internal linking** — Older posts already cross-linked (2026-08-07 pass).
   Close the Lightwell gap only; do not force links on the Windows client post.

## Success criteria

- README documents verification + sitemap submission
- Checklist covers title, description, permalink, taxonomy, optional image,
  inline links, and Related posts
- Lightwell has Related posts; supply-chain hub links to Lightwell
- No real secrets or verification tokens committed
