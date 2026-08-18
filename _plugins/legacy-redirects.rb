# frozen_string_literal: true

require 'cgi'

# Emit static HTML at historical URLs listed in `_data/legacy-redirects.yaml`.
# Chirpy no longer ships jekyll-redirect-from; this keeps LinkedIn and sitemap
# URLs working without changing published post permalinks.
#
# GitHub Pages cannot send HTTP 301 from a static site, so these pages use a
# canonical + meta refresh + JS replace (same approach as jekyll-redirect-from).

module LegacyRedirects
  class Page < Jekyll::PageWithoutAFile
    def initialize(site, from_path, to_path, title)
      dir = from_path.delete_prefix('/').delete_suffix('/')
      super(site, site.source, dir, 'index.html')

      dest = to_path.start_with?('/') ? to_path : "/#{to_path}"
      canonical = "#{site.config['url'].to_s.chomp('/')}#{site.baseurl}#{dest}"
      heading = title.to_s.empty? ? dest : title
      og_title = CGI.escapeHTML(heading)

      self.data = {
        'layout' => nil,
        'permalink' => from_path.end_with?('/') ? from_path : "#{from_path}/",
        'sitemap' => false
      }

      self.content = <<~HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <title>#{og_title}</title>
          <link rel="canonical" href="#{canonical}">
          <meta http-equiv="refresh" content="0; url=#{dest}">
          <meta property="og:title" content="#{og_title}">
          <meta property="og:url" content="#{canonical}">
          <script>location.replace(#{dest.dump});</script>
        </head>
        <body>
          <p>This page has moved to <a href="#{dest}">#{og_title}</a>.</p>
        </body>
        </html>
      HTML
    end
  end

  class Generator < Jekyll::Generator
    safe true
    # Run before jekyll-sitemap (:low) so sitemap: false is honored.
    priority :normal

    def generate(site)
      Array(site.data['legacy-redirects']).each do |entry|
        from_path = entry['from'].to_s
        to_path = entry['to'].to_s
        next if from_path.empty? || to_path.empty?

        site.pages << Page.new(site, from_path, to_path, entry['title'].to_s)
      end
    end
  end
end
