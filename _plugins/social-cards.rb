# frozen_string_literal: true

require 'json'
require 'open3'
require 'uri'

# Generate cards before rendering so every new post gets its own preview.
# Explicit og_image and article-cover image values remain editorial overrides.
class SocialCards < Jekyll::Generator
  safe true
  priority :low

  def generate(site)
    posts = site.posts.docs.select do |post|
      post.data['og_image'].to_s.empty? && !post.data['image']
    end
    return if posts.empty?

    jobs = posts.map do |post|
      categories = Array(post.data['categories'])
      {
        id: post.relative_path,
        slug: post.data['slug'],
        title: post.data['social_title'] || post.data['title'],
        label: post.data['social_label'] || categories.join(' / '),
        subtitle: post.data['social_subtitle'] || '',
        category: categories.include?('Security') ? 'Security' : categories.first,
        author: site.config.dig('social', 'name') || site.config['title'],
        domain: URI.parse(site.config.fetch('url')).host
      }
    end

    directory = 'assets/img/og/generated'
    local_python = File.join(site.source, '.venv-social', 'bin', 'python')
    python = ENV.fetch('SOCIAL_IMAGE_PYTHON') { File.executable?(local_python) ? local_python : 'python3' }
    output, errors, status = Open3.capture3(
      python, File.join(site.source, 'tools/social-cards/render.py'),
      stdin_data: JSON.generate(output_dir: File.join(site.source, directory), jobs: jobs)
    )
    unless status.success?
      raise Jekyll::Errors::FatalException,
            "Social cards failed. Install tools/social-cards/requirements.txt.\n#{errors}"
    end

    manifest = JSON.parse(output)
    posts.each do |post|
      card = manifest.fetch(post.relative_path)
      path = "/#{directory}/#{card.fetch('filename')}"
      post.data['og_image'] = path
      post.data['og_image_width'] = card.fetch('width')
      post.data['og_image_height'] = card.fetch('height')
      post.data['og_image_alt'] = card.fetch('alt')
      unless site.static_files.any? { |file| file.relative_path == path }
        site.static_files << Jekyll::StaticFile.new(site, site.source, directory, card.fetch('filename'))
      end
    end
    Jekyll.logger.info 'Social cards:', "#{posts.length} post previews ready"
  rescue Errno::ENOENT => e
    raise Jekyll::Errors::FatalException, "Social cards need Python and Pillow: #{e.message}"
  end
end
