#!/usr/bin/env python3
"""Check the published image contract against a real Jekyll build."""

from html.parser import HTMLParser
import json
from pathlib import Path
import re
import sys
from urllib.parse import urlparse

from PIL import Image


class Head(HTMLParser):
    def __init__(self):
        super().__init__()
        self.metadata = {}
        self.schemas = []
        self.in_head = False
        self.json_text = None
        self.redirect = False

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "head":
            self.in_head = True
        if tag == "body":
            self.in_head = False
        if not self.in_head:
            return
        if tag == "meta":
            self.redirect = attrs.get("http-equiv", "").lower() == "refresh" or self.redirect
            key = attrs.get("property", attrs.get("name"))
            self.metadata.setdefault(key, []).append(attrs.get("content"))
        if tag == "script" and attrs.get("type") == "application/ld+json":
            self.json_text = ""

    def handle_data(self, data):
        if self.json_text is not None:
            self.json_text += data

    def handle_endtag(self, tag):
        if tag == "script" and self.json_text is not None:
            self.schemas.append(json.loads(self.json_text))
            self.json_text = None
        if tag == "head":
            self.in_head = False


def check(site):
    count = 0
    generated = 0
    for page in sorted((site / "posts").glob("*/index.html")):
        content = page.read_text()
        head = Head()
        head.feed(content)
        if head.redirect:
            continue
        images = head.metadata.get("og:image", [])
        assert len(images) == 1, f"{page}: expected exactly one og:image"
        image_url = images[0]
        assert urlparse(image_url).scheme == "https", f"{page}: image URL must be absolute HTTPS"
        assert head.metadata.get("twitter:image") == images, f"{page}: Twitter image differs"
        assert head.metadata.get("twitter:card") == ["summary_large_image"], page
        if "/assets/img/og/generated/" in image_url:
            generated += 1
            relative = "assets/img/og/generated/" + image_url.rsplit("/", 1)[-1]
            image_path = site / relative
            assert image_path.exists(), f"{page}: missing generated image"
            with Image.open(image_path) as image:
                assert image.format == "PNG" and image.size == (1200, 630), image_path
            assert head.metadata.get("og:image:width") == ["1200"], page
            assert head.metadata.get("og:image:height") == ["630"], page
            assert head.metadata.get("og:image:type") == ["image/png"], page
            assert len(head.metadata.get("og:image:alt", [])) == 1, page
            assert head.metadata["og:image:alt"][0].strip(), page
            assert head.metadata.get("twitter:image:alt") == head.metadata["og:image:alt"], page
            articles = [s for s in head.schemas if s.get("@type") == "BlogPosting"]
            assert articles and all(s.get("image") == image_url for s in articles), page
            assert relative not in re.split(r"<body\b", content, maxsplit=1)[1], f"{page}: social image leaked into body"
        count += 1
    assert count and generated, "No posts or generated images were checked"
    print(f"Verified {count} post previews, including {generated} generated PNG cards.")


if __name__ == "__main__":
    check(Path(sys.argv[1] if len(sys.argv) > 1 else "_site"))
