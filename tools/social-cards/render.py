#!/usr/bin/env python3
"""Render Jekyll's social-card jobs from JSON on stdin; return a JSON manifest."""

from functools import lru_cache
import hashlib
import json
from pathlib import Path
import re
import sys

from PIL import Image, ImageDraw, ImageFont, __version__ as pillow_version

WIDTH, HEIGHT, SCALE = 1200, 630, 2
FONT_PATH = Path(__file__).parent / "fonts" / "Inter.ttf"
BACKGROUND = "#101c2e"
FOREGROUND = "#f7f9fc"
MUTED = "#abbcd0"
ACCENTS = {"Security": "#ffad91", "Homelab": "#8de0c4"}


@lru_cache(maxsize=64)
def font(size, weight=750):
    face = ImageFont.truetype(str(FONT_PATH), size * SCALE)
    # Inter's optical-size and weight axes; no machine-local font dependency.
    face.set_variation_by_axes([32, weight])
    return face


def wrap(text, face, width):
    lines = []
    for paragraph in text.splitlines():
        words = paragraph.split()
        if not words:
            continue

        @lru_cache(maxsize=None)
        def balanced(start, remaining):
            if start == len(words):
                return (0, []) if remaining == 0 else None
            if remaining == 0:
                return None
            best = None
            for end in range(start + 1, len(words) + 1):
                line = " ".join(words[start:end])
                length = face.getlength(line) / SCALE
                if length > width:
                    break
                tail = balanced(end, remaining - 1)
                if tail is not None:
                    score = (width - length) ** 2 + tail[0]
                    if best is None or score < best[0]:
                        best = (score, [line, *tail[1]])
            return best

        for count in range(1, 4):
            result = balanced(0, count)
            if result is not None:
                lines.extend(result[1])
                break
        else:
            return []
    return lines


def title_layout(title):
    for size in range(108, 55, -2):
        face = font(size)
        lines = wrap(title, face, 1072)
        line_height = round(size * 1.12)
        if (lines and len(lines) <= 3 and len(lines) * line_height <= 290
                and all(face.getlength(line) <= 1072 * SCALE for line in lines)):
            return face, lines, line_height
    raise ValueError(f"Social title is too long; add a shorter social_title: {title!r}")


def draw_text(draw, xy, text, face, fill):
    draw.text(tuple(v * SCALE for v in xy), text, font=face, fill=fill, anchor="lt")


def render(job, destination):
    title = str(job["title"]).strip()
    label = str(job["label"]).strip().upper()
    subtitle = str(job.get("subtitle", "")).strip()
    accent = ACCENTS.get(job.get("category"), "#82b4ff")
    image = Image.new("RGB", (WIDTH * SCALE, HEIGHT * SCALE), BACKGROUND)
    draw = ImageDraw.Draw(image)

    def rectangle(box, fill):
        draw.rectangle(tuple(v * SCALE for v in box), fill=fill)

    # A restrained grid mark and a wide color band survive small link thumbnails.
    rectangle((0, 0, WIDTH, 12), accent)
    for x, y in [(1080, 60), (1107, 60), (1080, 87), (1107, 87)]:
        rectangle((x, y, x + 17, y + 17), accent if x == 1107 and y == 60 else "#314864")

    label_font = font(25, 650)
    if label_font.getlength(label) > 940 * SCALE:
        raise ValueError(f"Social label is too long: {label!r}")
    draw_text(draw, (64, 65), label, label_font, accent)

    face, lines, line_height = title_layout(title)
    start_y = 155 + (290 - len(lines) * line_height) // 2
    for index, line in enumerate(lines):
        color = accent if len(lines) > 1 and index == len(lines) - 1 else FOREGROUND
        draw_text(draw, (64, start_y + index * line_height), line, face, color)

    if subtitle:
        subtitle_font = font(28, 450)
        if subtitle_font.getlength(subtitle) > 1072 * SCALE:
            raise ValueError(f"Social subtitle is too long: {subtitle!r}")
        draw_text(draw, (64, 461), subtitle, subtitle_font, MUTED)

    rectangle((64, 527, 1136, 529), "#30435a")
    rectangle((64, 551, 104, 591), accent)
    draw_text(draw, (71, 561), "TH", font(17, 800), BACKGROUND)
    draw_text(draw, (122, 553), job["author"], font(29, 650), FOREGROUND)
    domain_font = font(22, 450)
    domain = job["domain"]
    domain_width = domain_font.getlength(domain) / SCALE
    if domain_width > 520:
        raise ValueError("Site hostname is too long for the social-card footer")
    draw_text(draw, (1136 - domain_width, 560), domain, domain_font, MUTED)

    image = image.resize((WIDTH, HEIGHT), Image.Resampling.LANCZOS)
    image.save(destination, optimize=True)


def main():
    request = json.load(sys.stdin)
    output = Path(request["output_dir"])
    output.mkdir(parents=True, exist_ok=True)
    renderer = hashlib.sha256(Path(__file__).read_bytes() + FONT_PATH.read_bytes()).hexdigest()
    manifest = {}
    for job in request["jobs"]:
        slug = re.sub(r"[^a-zA-Z0-9_-]", "-", job["slug"]).strip("-")
        if not slug:
            raise ValueError("A social-card job needs a nonempty slug")
        fingerprint = json.dumps([renderer, pillow_version, job], sort_keys=True).encode()
        filename = f"{slug}-{hashlib.sha256(fingerprint).hexdigest()[:12]}.png"
        destination = output / filename
        if not destination.exists():
            render(job, destination)
        manifest[job["id"]] = {
            "filename": filename,
            "width": WIDTH,
            "height": HEIGHT,
            "alt": f"{' '.join(job['title'].split())} — {job['author']}",
        }
    json.dump(manifest, sys.stdout)


if __name__ == "__main__":
    main()
