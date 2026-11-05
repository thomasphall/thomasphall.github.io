# Social preview cards

Every post without an explicit `og_image:` or `image:` gets a PNG card when
Jekyll builds. The renderer uses a bundled Inter font, large type, and a
consistent dark background. Security and Homelab categories use distinct
accent colors. The card is 1200×630 with generous margins for thumbnail display.

## Customize a post

The article title and categories work without extra front matter. For a
shorter sharing headline, use:

```yaml
social_title: |-
  Benchmark VMs
  before you migrate
social_label: OpenShift Virtualization
social_subtitle: FIO · Latency · Concurrent VM load
```

These fields affect only the image. Keep the headline to roughly 4–9 words
when possible. The renderer wraps and fits up to three lines, and rejects
text that would overflow. A subtitle is optional; do not repeat the full
meta description. `og_image:` overrides generation for bespoke artwork.
Chirpy's `image:` remains an article cover and also skips generation.

## Build and inspect

Install the local dependency as described in the README, then run the usual
`bundle exec jekyll build`. Alternatively, set `SOCIAL_IMAGE_PYTHON` to a
Python executable with the pinned Pillow version installed.

Cards appear in `assets/img/og/generated/` and are copied into `_site/`.
Generated files are ignored by Git; GitHub Actions recreates them. Image
filenames contain a hash of the design, font, Pillow version, and card inputs,
so changing a headline or design produces a new image URL. Old generated
files are not removed during local builds; deployment starts from a clean
checkout.

Inspect both the full card and a roughly 256-pixel-wide thumbnail. Keep the
main subject readable without relying on the subtitle. Check the built
article's `og:image`, dimensions, alt text, Twitter image, and JSON-LD image.
The card is metadata only and does not add a cover to the article.

## Refresh LinkedIn after deployment

LinkedIn reads the page's Open Graph metadata, and may cache an earlier
preview. Paste the article URL into
[LinkedIn Post Inspector](https://www.linkedin.com/post-inspector/) after
deployment, then re-add the URL to a new LinkedIn draft. LinkedIn says this
refresh affects new shares; existing posts keep their original preview.
See [LinkedIn's refresh guidance](https://www.linkedin.com/help/linkedin/answer/a6269011).

The design remains readable in a compact link card. LinkedIn controls the
final preview layout; an image's dimensions alone do not guarantee a large
feed card. The generated PNG can also be uploaded as a native image when a
larger visual is desired, with the article link in the post text.

## Implementation

`_plugins/social-cards.rb` collects post metadata and calls
`tools/social-cards/render.py` once per build. `_plugins/og-image.rb` sets
Open Graph, Twitter, and JSON-LD image metadata in the rendered head.
Fonts and the renderer are local; no image API, browser, or external service
is needed during image generation.
