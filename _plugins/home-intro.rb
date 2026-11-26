# frozen_string_literal: true

# Chirpy's home layout renders the paginated feed but skips the index page body.
Jekyll::Hooks.register :site, :post_read do |site|
  home = site.layouts.fetch('home')
  home.content = "{% if paginator.page == 1 %}{{ content }}{% endif %}\n" + home.content
end
