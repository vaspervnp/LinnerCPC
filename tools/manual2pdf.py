#!/usr/bin/env python3
"""Turn a Markdown manual into a PDF (make manuals).

    tools/manual2pdf.py docs/manual_en.md docs/manual_en.pdf [--html out.html]

The Markdown becomes one self-contained HTML page (the screenshots embedded
as data URIs, an A4 print style sheet) that headless Chrome/Chromium prints
to PDF. Chrome is looked up in $CHROME, then on the PATH, then (under WSL)
in the usual Windows install folders.
"""
import argparse
import base64
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import markdown

CSS = """
@page { size: A4; margin: 18mm 17mm 18mm 17mm; }
:root { --ink: #1d1d1f; --muted: #5b5b66; --green: #1f8a3a; --rule: #d6d6dc; }
html { font-family: "Segoe UI", "Noto Sans", "DejaVu Sans", Arial, sans-serif;
       font-size: 10.5pt; color: var(--ink); line-height: 1.45; }
body { margin: 0; }
h1 { font-size: 26pt; letter-spacing: 0.06em; margin: 0 0 4pt;
     border-bottom: 3pt solid var(--green); padding-bottom: 4pt; }
h1 + p { color: var(--muted); margin-top: 6pt; }
h2 { font-size: 15pt; color: var(--green); margin: 18pt 0 6pt;
     border-bottom: 0.75pt solid var(--rule); padding-bottom: 2pt;
     break-after: avoid; }
p, li { orphans: 3; widows: 3; }
ul { padding-left: 16pt; }
li { margin: 2pt 0; }
code, pre { font-family: Consolas, "DejaVu Sans Mono", monospace; }
pre { background: #f2f2f5; padding: 6pt 10pt; border-radius: 3pt;
      font-size: 11pt; break-inside: avoid; }
table { border-collapse: collapse; margin: 8pt 0; break-inside: avoid; }
th, td { border-bottom: 0.75pt solid var(--rule); padding: 3pt 8pt;
         text-align: left; vertical-align: top; }
th { background: #eef5ef; }
img { display: block; margin: 8pt auto; width: 62%;
      image-rendering: pixelated; border: 0.75pt solid #000;
      break-inside: avoid; }
td img { width: 100%; margin: 0; }
table:has(img) td, table:has(img) th { border: none; background: none;
      text-align: center; width: 50%; }
table:has(img) { width: 100%; }
p:has(> img:only-child) { break-inside: avoid; }
em { color: var(--muted); }
p:has(+ pre), p:has(+ ul), p:has(+ table) { break-after: avoid; }
"""


def embed_images(html, base):
    def repl(m):
        path = (base / m.group(1)).resolve()
        data = base64.b64encode(path.read_bytes()).decode()
        return f'src="data:image/png;base64,{data}"'
    return re.sub(r'src="([^"]+\.png)"', repl, html)


def find_chrome():
    if os.environ.get("CHROME"):
        return os.environ["CHROME"]
    for name in ("chromium", "chromium-browser", "google-chrome", "google-chrome-stable"):
        p = shutil.which(name)
        if p:
            return p
    for p in ("/mnt/c/Program Files/Google/Chrome/Application/chrome.exe",
              "/mnt/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"):
        if os.path.exists(p):
            return p
    sys.exit("manual2pdf: no Chrome/Chromium found (set CHROME)")


def host_path(chrome, path):
    """Windows Chrome under WSL needs Windows paths."""
    if chrome.endswith(".exe"):
        return subprocess.check_output(["wslpath", "-w", str(path)], text=True).strip()
    return str(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("md")
    ap.add_argument("pdf")
    ap.add_argument("--html", help="also keep the HTML page here")
    args = ap.parse_args()

    src = Path(args.md)
    text = src.read_text(encoding="utf-8")
    lang = "el" if src.stem.endswith("_el") else "en"
    title = text.splitlines()[0].lstrip("# ").strip()
    body = markdown.markdown(text, extensions=["tables", "fenced_code"])
    body = embed_images(body, src.parent)
    page = (f'<!doctype html><html lang="{lang}"><head><meta charset="utf-8">'
            f"<title>{title}</title><style>{CSS}</style></head>"
            f"<body>{body}</body></html>")

    out = Path(args.pdf).resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=out.parent) as tmp:
        html = Path(tmp) / "manual.html"
        html.write_text(page, encoding="utf-8")
        if args.html:
            shutil.copy(html, args.html)
        chrome = find_chrome()
        pdf_tmp = Path(tmp) / "manual.pdf"
        subprocess.run([chrome, "--headless=new", "--disable-gpu",
                        "--no-pdf-header-footer", "--print-to-pdf-no-header",
                        "--print-to-pdf=" + host_path(chrome, pdf_tmp),
                        host_path(chrome, html)],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                       timeout=120)
        if not pdf_tmp.exists():
            sys.exit("manual2pdf: Chrome wrote no PDF")
        shutil.move(pdf_tmp, out)
    print(f"{args.md} -> {args.pdf}")


if __name__ == "__main__":
    main()
