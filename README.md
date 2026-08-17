# Thomas Hall — personal site

Personal GitHub Pages site built with [Jekyll](https://jekyllrb.com) and the
[Chirpy](https://github.com/cotes2020/jekyll-theme-chirpy) theme.

**Live site:** <https://thomasphall.github.io>

## Disclaimer

This is a personal website. Opinions expressed here are my own and do not
necessarily represent Red Hat or any other organization. This site is not an
official Red Hat property.

## License

| Material | License |
| -------- | ------- |
| Chirpy theme / site scaffolding | [MIT](LICENSE) (Copyright Cotes Chung) |
| Original blog posts and writing by Thomas Hall | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |

See [NOTICE](NOTICE) for trademark attribution and further detail.

## Usage

Theme documentation: [Chirpy wiki](https://github.com/cotes2020/jekyll-theme-chirpy/wiki).

New posts: follow the [post SEO checklist](docs/seo-post-checklist.md).

Site title and tagline live in `_config.yml`. The homepage document title is
`title | tagline`; paginated indexes (`/page2/`, …) are `Page N | title` so
they do not collide with home. See [site-level titles](docs/seo-post-checklist.md#site-level-titles).

Default social preview is `assets/img/og/site.png` (1200×630). Flagship posts
override it with `image:` in front matter.

## Search Console

Chirpy renders verification meta tags from `_config.yml` →
`webmaster_verifications`. The Google HTML-tag token is already set. Bing is
still a placeholder until you paste a token (these values are public once the
site is live).

### Google Search Console

The URL-prefix property `https://thomasphall.github.io` is verified via the
HTML tag in `_config.yml`. After each notable publish wave:

1. Open [Google Search Console](https://search.google.com/search-console).
2. Confirm the sitemap `https://thomasphall.github.io/sitemap.xml` is submitted
   under **Sitemaps**. Submit it if it is missing.
3. After a few days, check **Pages** / **Performance** for new URLs.

To re-verify a new property, copy only the `content="..."` value from the
HTML tag method into `webmaster_verifications.google`.

### Bing Webmaster Tools

1. Import the Google property or add the site in
   [Bing Webmaster Tools](https://www.bing.com/webmasters).
2. If verifying with an HTML meta tag, paste the content token into
   `webmaster_verifications.bing` the same way as Google.
3. Submit the same sitemap URL.
