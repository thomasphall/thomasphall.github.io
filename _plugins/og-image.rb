# frozen_string_literal: true

# Chirpy treats `image:` as a post cover (rendered above the byline). The
# 1200×630 files in assets/img/og/ are social-preview cards, not article
# photos. Use `og_image:` instead and rewrite og/twitter/JSON-LD image URLs
# after render so LinkedIn still gets a unique card.

require 'cgi'
require 'json'

module OgImage
  module_function

  def apply(doc)
    path = doc.data['og_image']
    return if path.nil? || path.to_s.empty?
    return unless doc.output

    abs = if path.include?('://')
            path
          else
            base = doc.site.config['url'].to_s.chomp('/')
            subpath = doc.site.config['baseurl'].to_s.chomp('/')
            "#{base}#{subpath}#{path.start_with?('/') ? path : "/#{path}"}"
          end

    alt = doc.data['og_image_alt'] || doc.data['title'] || doc.site.config['title']
    tags = {
      'og:image' => abs,
      'og:image:alt' => alt,
      'twitter:image' => abs,
      'twitter:image:alt' => alt
    }
    if doc.data['og_image_width'] && doc.data['og_image_height']
      tags['og:image:width'] = doc.data['og_image_width']
      tags['og:image:height'] = doc.data['og_image_height']
      tags['og:image:type'] = 'image/png'
    end

    # Replace the entire image group so old cover-image dimensions cannot leak
    # into the generated card. Work only in <head>, never article code samples.
    # Chirpy's HTML compressor can omit the optional closing </head> tag.
    doc.output.sub!(/<head\b[^>]*>.*?(?=<\/head>|<body\b)/m) do |head|
      head = head.gsub(/<meta\b(?=[^>]*(?:name|property)=["'](?:og:image(?::[^"']*)?|twitter:image(?::[^"']*)?)["'])[^>]*>/i, '')
      head = head.gsub(/<meta\b(?=[^>]*name=["']twitter:card["'])[^>]*>/i, '')
      image_tags = tags.map do |name, value|
        attribute = name.start_with?('twitter:') ? 'name' : 'property'
        %(<meta #{attribute}="#{name}" content="#{CGI.escapeHTML(value.to_s)}" />)
      end.join
      image_tags += '<meta name="twitter:card" content="summary_large_image" />'

      head = head.gsub(/(<script\b[^>]*type=["']application\/ld\+json["'][^>]*>)(.*?)(<\/script>)/m) do
        opening, body, closing = Regexp.last_match.captures
        schema = JSON.parse(body)
        if schema.is_a?(Hash) && %w[BlogPosting Article WebPage].include?(schema['@type'])
          schema['image'] = abs
        end
        "#{opening}#{JSON.generate(schema).gsub('<', '\\u003c')}#{closing}"
      end
      head + image_tags
    end
  end
end

Jekyll::Hooks.register :documents, :post_render do |doc|
  OgImage.apply(doc)
end

Jekyll::Hooks.register :pages, :post_render do |page|
  OgImage.apply(page)
end
