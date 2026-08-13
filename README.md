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

## Search Console

Chirpy renders verification meta tags from `_config.yml` →
`webmaster_verifications`. Tokens stay as placeholders until you paste real
values (do not commit secrets you treat as sensitive ops data if your policy
requires it—these tokens are public once the site is live).

### Google Search Console

1. Open [Google Search Console](https://search.google.com/search-console) and
   add a **URL prefix** property for `https://thomasphall.github.io`.
2. Choose **HTML tag** verification. Copy only the `content="..."` value
   (not the full `<meta>` element).
3. Set it in `_config.yml`:

   ```yaml
   webmaster_verifications:
     google: PASTE_TOKEN_HERE
   ```

4. Commit, push, wait for GitHub Pages to deploy, then click **Verify** in
   Search Console.
5. Submit the sitemap: `https://thomasphall.github.io/sitemap.xml`.

### Bing Webmaster Tools

1. Import the Google property or add the site in
   [Bing Webmaster Tools](https://www.bing.com/webmasters).
2. If verifying with an HTML meta tag, paste the content token into
   `webmaster_verifications.bing` the same way as Google.
3. Submit the same sitemap URL.
