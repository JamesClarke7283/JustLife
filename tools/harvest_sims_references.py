"""Harvest Sims 4 gameplay reference images for art study.

Research material only: downloads land in ``research/sims4/`` which is
git-ignored. No reference pixel ever enters the shipped game assets.

Usage:
    python tools/harvest_sims_references.py            # harvest every seed
    python tools/harvest_sims_references.py --list     # list seed groups
    python tools/harvest_sims_references.py --only ui  # one seed group
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "research" / "sims4"
MANIFEST = OUT / "harvest_manifest.json"

UA = (
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
)

# Several reference hosts (Carl's guide in particular) answer 403 to a bare
# user agent, so send a complete navigation header set.
HEADERS = {
    "User-Agent": UA,
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,"
    "image/avif,image/webp,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
    "Connection": "keep-alive",
    "Upgrade-Insecure-Requests": "1",
    "Sec-Fetch-Dest": "document",
    "Sec-Fetch-Mode": "navigate",
    "Sec-Fetch-Site": "none",
    "Sec-Fetch-User": "?1",
}

# Seed groups. Each entry is (group, [page urls], [url substrings to keep]).
SEEDS: dict[str, tuple[list[str], list[str]]] = {
    "ui": (
        [f"https://interfaceingame.com/games/the-sims-4/page/{n}/" for n in range(1, 6)]
        + ["https://interfaceingame.com/games/the-sims-4/"],
        ["/the-sims-4/"],
    ),
    "creator": (
        [
            "https://www.carls-sims-4-guide.com/tutorials/how-to/make-a-sim.php",
        ],
        ["/tutorials/", "/cas-", "/make-a-sim"],
    ),
    "emotions_needs": (
        [
            "https://www.carls-sims-4-guide.com/sims/emotions.php",
            "https://www.carls-sims-4-guide.com/sims/needs.php",
            "https://www.carls-sims-4-guide.com/sims/traits.php",
        ],
        ["/sims/"],
    ),
    "build": (
        [
            "https://www.carls-sims-4-guide.com/tutorials/building/houses.php",
            "https://www.carls-sims-4-guide.com/tutorials/building/roofs.php",
            "https://www.carls-sims-4-guide.com/tutorials/building/stairs-basements.php",
            "https://www.carls-sims-4-guide.com/tutorials/decorating/landscaping.php",
        ],
        ["/tutorials/", "/building/", "/decorating/"],
    ),
    "cooking_meals": (
        [
            "https://www.carls-sims-4-guide.com/skills/cooking/",
            "https://www.carls-sims-4-guide.com/skills/gourmetcooking/",
        ],
        ["/skills/"],
    ),
    "relationships": (
        [
            "https://www.carls-sims-4-guide.com/relationships/",
            "https://www.carls-sims-4-guide.com/relationships/romance.php",
        ],
        ["/relationships/"],
    ),
    "children_family": (
        [
            "https://www.carls-sims-4-guide.com/parenting/children.php",
            "https://www.carls-sims-4-guide.com/parenting/toddlers.php",
        ],
        ["/parenting/", "/children/"],
    ),
    "careers": (
        [
            "https://www.carls-sims-4-guide.com/careers/",
            "https://www.carls-sims-4-guide.com/careers/tips.php",
        ],
        ["/careers/"],
    ),
    "infants": (
        [
            "https://simscommunity.info/2023/03/15/sims-4-infant-care-guide/",
        ],
        ["simscommunity.info/wp-content/uploads/", "/infant"],
    ),
    "hair_clothing_ea": (
        [
            "https://www.ea.com/games/the-sims/the-sims-4/news/"
            "the-sims-new-hair-and-size-inclusive-looks",
            "https://www.ea.com/games/the-sims/the-sims-4/news/"
            "sims-4-cas-starter-sims-cultural-representation",
        ],
        ["/the-sims/news/", "ea.com/"],
    ),
    "gardening_official": (
        [
            "https://help.ea.com/en/articles/the-sims/the-sims-4/gardening-guide/",
            "https://help.ea.com/en/articles/the-sims/the-sims-4/cooking-skill/",
            "https://help.ea.com/en/articles/the-sims/the-sims-4/skills/",
            "https://help.ea.com/en/articles/the-sims/the-sims-4/child-skills/",
        ],
        ["help.ea.com/", "ea.com/", "/articles/"],
    ),
    "gallery_packs": (
        [
            "https://www.carls-sims-4-guide.com/gamepictures/",
            "https://www.carls-sims-4-guide.com/sims/",
        ],
        ["/gamepictures/", "/sims/"],
    ),
}

IMG_ATTR = re.compile(
    r"""(?:data-src|data-lazy-src|data-original|src|data-bg|content)\s*=\s*["']([^"']+\.(?:png|jpe?g|webp|avif|gif))["']""",
    re.I,
)
SRCSET_ATTR = re.compile(r"""srcset\s*=\s*["']([^"']+)["']""", re.I)
SKIP = re.compile(r"(logo|avatar|favicon|sprite|icon-\d|placeholder|advert|/ads/)", re.I)


def fetch(url: str, timeout: int = 30) -> bytes | None:
    headers = dict(HEADERS)
    if not url.endswith((".html", ".php", "/")):
        headers["Sec-Fetch-Dest"] = "image"
        headers["Sec-Fetch-Mode"] = "no-cors"
        headers["Accept"] = "image/avif,image/webp,image/png,image/*,*/*;q=0.8"
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.read()
    except (urllib.error.URLError, OSError, ValueError):
        return None


def absolutize(base: str, url: str) -> str:
    if url.startswith("data:"):
        return ""
    return urllib.parse.urljoin(base, url.strip())


def strip_size_suffix(url: str) -> str:
    """WordPress serves resized copies; prefer the original."""
    return re.sub(r"-\d+x\d+(?=\.\w+$)", "", url)


def collect_image_urls(page_url: str, html: str, keep: list[str]) -> set[str]:
    found: set[str] = set()
    for m in IMG_ATTR.finditer(html):
        found.add(m.group(1))
    for m in SRCSET_ATTR.finditer(html):
        for part in m.group(1).split(","):
            candidate = part.strip().split(" ")[0]
            if candidate:
                found.add(candidate)

    urls: set[str] = set()
    for raw in found:
        full = absolutize(page_url, raw)
        if not full or SKIP.search(full):
            continue
        if keep and not any(k in full for k in keep):
            continue
        urls.add(strip_size_suffix(full))
        urls.add(full)
    return urls


def load_manifest() -> dict:
    if MANIFEST.exists():
        return json.loads(MANIFEST.read_text())
    return {"images": {}}


def save_manifest(manifest: dict) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    MANIFEST.write_text(json.dumps(manifest, indent=1, sort_keys=True))


def harvest_group(group: str, pages: list[str], keep: list[str], manifest: dict) -> tuple[int, int]:
    """Return (considered, newly stored)."""
    considered = 0
    stored = 0
    seen_urls: set[str] = set()

    for page_url in pages:
        body = fetch(page_url)
        if body is None:
            print(f"  ! unreachable: {page_url}")
            continue
        html = body.decode("utf-8", "replace")
        for url in sorted(collect_image_urls(page_url, html, keep)):
            if url in seen_urls:
                continue
            seen_urls.add(url)
            considered += 1

            data = fetch(url, timeout=45)
            if not data or len(data) < 12_000:
                continue  # thumbnails and error pages are not studied

            digest = hashlib.sha256(data).hexdigest()
            if digest in manifest["images"]:
                continue

            name = Path(urllib.parse.urlparse(url).path).name
            target = OUT / group / name
            target.parent.mkdir(parents=True, exist_ok=True)
            if target.exists():
                target = target.with_name(f"{target.stem}_{digest[:8]}{target.suffix}")
            target.write_bytes(data)

            manifest["images"][digest] = {
                "group": group,
                "path": str(target.relative_to(ROOT)),
                "url": url,
                "source_page": page_url,
                "bytes": len(data),
            }
            stored += 1
            print(f"  + [{group}] {name} ({len(data)//1024} KiB)")

        save_manifest(manifest)

    return considered, stored


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--only", action="append", default=None, help="seed group to harvest")
    parser.add_argument("--list", action="store_true", help="list seed groups and exit")
    args = parser.parse_args()

    if args.list:
        for name, (pages, _) in SEEDS.items():
            print(f"{name:18s} {len(pages)} page(s)")
        return 0

    groups = args.only or list(SEEDS)
    unknown = [g for g in groups if g not in SEEDS]
    if unknown:
        print(f"unknown group(s): {', '.join(unknown)}", file=sys.stderr)
        return 2

    manifest = load_manifest()
    before = len(manifest["images"])
    total_considered = 0
    total_stored = 0

    for group in groups:
        pages, keep = SEEDS[group]
        print(f"== {group} ({len(pages)} page(s))")
        considered, stored = harvest_group(group, pages, keep, manifest)
        total_considered += considered
        total_stored += stored
        print(f"   considered {considered}, stored {stored}")

    save_manifest(manifest)
    print(
        f"\narchive now holds {len(manifest['images'])} unique images "
        f"({before} before, {total_stored} new from {total_considered} candidates)"
    )
    print(f"manifest: {MANIFEST.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
