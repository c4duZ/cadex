"""Writes the Windows app icon, apps/windows/app/Cadex.ico, from the same
docs/cadex-icon.png the Mac's AppIcon.icns comes from (plan 13, fase B):

    python3 -I tools/icons/windows_ico.py

Each size is resized by macOS's sips and stored as PNG inside the ICO
(Windows Vista and later read PNG entries), so no image library is needed.
"""
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
SOURCE = ROOT / "docs/cadex-icon.png"
TARGET = ROOT / "apps/windows/app/Cadex.ico"
SIZES = [16, 20, 24, 32, 40, 48, 64, 128, 256]


def main():
    images = []
    with tempfile.TemporaryDirectory() as tmp:
        for size in SIZES:
            out = Path(tmp) / f"{size}.png"
            subprocess.run(["sips", "-z", str(size), str(size), str(SOURCE), "--out", str(out)],
                           check=True, capture_output=True)
            images.append((size, out.read_bytes()))
    header = struct.pack("<HHH", 0, 1, len(images))
    offset = 6 + 16 * len(images)
    entries, data = b"", b""
    for size, png in images:
        # 256 is written as 0 in the one-byte width and height fields.
        dim = 0 if size >= 256 else size
        entries += struct.pack("<BBBBHHII", dim, dim, 0, 0, 1, 32, len(png), offset + len(data))
        data += png
    TARGET.write_bytes(header + entries + data)
    print(f"{TARGET.relative_to(ROOT)}: {len(images)} tamanhos, {TARGET.stat().st_size // 1024} KB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
