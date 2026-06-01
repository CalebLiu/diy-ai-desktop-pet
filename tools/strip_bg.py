#!/usr/bin/env python3
"""rembg 把指定 PNG 的背景扣干净(原地覆盖)

用法:
  python strip_bg.py path/to/image.png
  python strip_bg.py *.png
  python strip_bg.py --model birefnet-general path/to/image.png

模型选择:
  isnet-anime      默认。深色/高饱和动漫角色效果最好(深色饱和发色)。
  birefnet-general 浅色/低饱和头发的角色用这个(Rick 浅蓝尖发会被 isnet-anime 当背景吃掉)。
  u2net / isnet-general-use  备选,一般更差(易留白墙/把发变白)。
角色专属可在 tools/profiles/<slug>.json 里写 "strip_model": "...",
pipeline 会自动读取并传进来。
"""
import argparse
import io
from pathlib import Path

from rembg import remove, new_session
from PIL import Image


def strip(paths, model: str = "isnet-anime") -> None:
    session = new_session(model)
    for path in paths:
        p = Path(path)
        if not p.exists():
            print(f"  ⚠ 跳过(找不到): {path}")
            continue
        with open(p, "rb") as f:
            data = f.read()
        out = remove(data, session=session)
        Image.open(io.BytesIO(out)).save(p)
        print(f"  ✓ stripped {path} (model={model})")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("paths", nargs="+", help="要扣背景的 PNG 路径(原地覆盖)")
    ap.add_argument("--model", default="isnet-anime",
                    help="rembg 模型,默认 isnet-anime;浅发角色用 birefnet-general")
    args = ap.parse_args()
    strip(args.paths, args.model)
