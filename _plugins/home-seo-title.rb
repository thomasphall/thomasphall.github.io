# frozen_string_literal: true

# Chirpy renders `{% seo title=false %}` and then emits
# `<title>{{ site.title }}</title>` for every `layout: home` page, including
# paginator URLs like /page2/. That makes the homepage and later pages share
# one SERP title. Rewrite the document title, og:title, and twitter:title
# after render so:
#   /        → "{{ site.title }} | {{ site.tagline }}"
#   /pageN/  → "Page N | {{ site.title }}"

Jekyll::Hooks.register :pages, :post_render do |page|
  next unless page.data['layout'] == 'home'
  next unless page.output&.include?('<title>')

  site_title = page.site.config['title'].to_s
  tagline = page.site.config['tagline'].to_s
  pager = page.pager

  new_title = if pager && pager.page > 1
                "Page #{pager.page} | #{site_title}"
              elsif !tagline.empty?
                "#{site_title} | #{tagline}"
              else
                site_title
              end

  page.output.sub!(%r{<title>\s*.*?\s*</title>}m, "<title>#{new_title}</title>")
  page.output.gsub!(/property="og:title" content="[^"]*"/, "property=\"og:title\" content=\"#{new_title}\"")
  page.output.gsub!(/name="twitter:title" content="[^"]*"/, "name=\"twitter:title\" content=\"#{new_title}\"")
end
