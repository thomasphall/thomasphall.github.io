# frozen_string_literal: true

# Chirpy treats `image:` as a post cover (rendered above the byline). The
# 1200×630 files in assets/img/og/ are social-preview cards, not article
# photos. Use `og_image:` instead and rewrite og/twitter/JSON-LD image URLs
# after render so LinkedIn still gets a unique card.

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
            "#{base}#{path.start_with?('/') ? path : "/#{path}"}"
          end

    doc.output.gsub!(/property="og:image" content="[^"]*"/, "property=\"og:image\" content=\"#{abs}\"")
    doc.output.gsub!(/property="twitter:image" content="[^"]*"/, "property=\"twitter:image\" content=\"#{abs}\"")
    doc.output.gsub!(/"image":"https:[^"]+"/, "\"image\":\"#{abs}\"")
  end
end

Jekyll::Hooks.register :documents, :post_render do |doc|
  OgImage.apply(doc)
end

Jekyll::Hooks.register :pages, :post_render do |page|
  OgImage.apply(page)
end
