#!/usr/bin/env python3
# shop_ocr.py - Detect merchant name + find buyable items via OCR
#
# Usage:
#   python3 shop_ocr.py <screenshot.png> <buy_y> [item1] [item2] ...
#
# buy_y  — Y of the Purchase button; item tabs are scanned from buy_y
#          down to the bottom of the screen (tabs sit below the button)
#
# Output (stdout):
#   MERCHANT:<name>        — if Mari / Jester / Rin found in shop title
#   <Item Name>|<cx>|<cy>  — one line per matched item tab

import sys
import os
import cv2
import subprocess
import shutil


def ocr_region(img, psm=11, min_conf=20):
    """Run Tesseract on img and return list of word dicts with text/cx/cy."""
    if not shutil.which('tesseract'):
        print("ERROR: tesseract not found", file=sys.stderr)
        return []

    tmp = '/tmp/_shop_ocr.png'
    cv2.imwrite(tmp, img)

    try:
        result = subprocess.run(
            ['tesseract', tmp, 'stdout', '--psm', str(psm), 'tsv'],
            capture_output=True, text=True, timeout=15
        )
    except subprocess.TimeoutExpired:
        return []
    finally:
        try:
            os.unlink(tmp)
        except OSError:
            pass

    words = []
    for line in result.stdout.strip().split('\n')[1:]:
        cols = line.split('\t')
        if len(cols) < 12:
            continue
        text = cols[11].strip()
        if not text:
            continue
        try:
            conf = float(cols[10])
        except ValueError:
            continue
        if conf < min_conf:
            continue
        try:
            x, y, w, h = int(cols[6]), int(cols[7]), int(cols[8]), int(cols[9])
        except ValueError:
            continue
        words.append({'text': text, 'cx': x + w // 2, 'cy': y + h // 2})

    return words


def detect_merchant(words):
    """Return 'Mari', 'Jester', 'Rin', or None from a list of OCR words.

    Handles possessive forms ('Mari's Shop', 'Jester's Shop', "Rin's Shop")
    by also checking a cleaned version with punctuation stripped.
    """
    full_text = ' '.join(w['text'] for w in words).lower()
    clean_text = ''.join(c if c.isalpha() or c == ' ' else ' ' for c in full_text)

    for name in ('mari', 'jester', 'rin'):
        if name in full_text or name in clean_text:
            return name.capitalize()
    return None


def match_items(words, items_to_find):
    """Match item names against OCR words.

    Uses two strategies:
      1. Exact consecutive word match  (e.g. ["lucky", "potion"])
      2. Full-text substring match     (handles OCR joining words or slight misreads)
    Returns list of (item_name, cx, cy).
    """
    # Build a flat string of all words for substring matching
    all_text = ' '.join(w['text'].lower() for w in words)

    found = []
    for item in items_to_find:
        item_lower = item.lower()
        parts = item_lower.split()
        n = len(parts)
        matched = False

        # Strategy 1: exact consecutive word match
        for i in range(len(words) - n + 1):
            if all(words[i + j]['text'].lower() == parts[j] for j in range(n)):
                cx = sum(words[i + j]['cx'] for j in range(n)) // n
                cy = sum(words[i + j]['cy'] for j in range(n)) // n
                found.append((item, cx, cy))
                matched = True
                break

        if matched:
            continue

        # Strategy 2: substring match in joined text, then find approx position
        if item_lower in all_text:
            # Locate the first word of the item to get coordinates
            for i, w in enumerate(words):
                if w['text'].lower() == parts[0]:
                    end = min(i + n, len(words))
                    cx = sum(words[k]['cx'] for k in range(i, end)) // (end - i)
                    cy = sum(words[k]['cy'] for k in range(i, end)) // (end - i)
                    found.append((item, cx, cy))
                    break

    return found


def main():
    if len(sys.argv) < 3:
        print("Usage: shop_ocr.py <screenshot> <buy_y> [items...]", file=sys.stderr)
        sys.exit(1)

    shot_path     = sys.argv[1]
    buy_y         = int(sys.argv[2])
    items_to_find = sys.argv[3:]

    img = cv2.imread(shot_path)
    if img is None:
        print(f"ERROR: cannot read screenshot: {shot_path}", file=sys.stderr)
        sys.exit(1)

    h, w_img = img.shape[0], img.shape[1]

    # ── Merchant name: scan full image with PSM 11 (sparse text) ────────
    top_words = ocr_region(img, psm=11, min_conf=20)
    merchant = detect_merchant(top_words)
    if merchant:
        print(f"MERCHANT:{merchant}")

    # ── Item tabs: scan from buy_y down, PSM 6 (uniform block) ──────────
    # Colored tab labels read better with PSM 6 than sparse PSM 11.
    # Also run PSM 11 and merge — takes two passes but catches more text.
    y1 = max(0, buy_y)
    strip = img[y1:h, :]

    words_6  = ocr_region(strip, psm=6,  min_conf=20)
    words_11 = ocr_region(strip, psm=11, min_conf=20)

    # Merge: add PSM-11 words that aren't already covered by PSM-6
    seen = {(w['cx'], w['cy']) for w in words_6}
    for w in words_11:
        if (w['cx'], w['cy']) not in seen:
            words_6.append(w)
            seen.add((w['cx'], w['cy']))

    words = words_6

    # Shift Y back to absolute screen coordinates
    for word in words:
        word['cy'] += y1

    if not items_to_find:
        for word in words:
            print(f"{word['text']}|{word['cx']}|{word['cy']}")
        return

    matched = match_items(words, items_to_find)
    for name, cx, cy in matched:
        print(f"{name}|{cx}|{cy}")


if __name__ == '__main__':
    main()
