#!/usr/bin/env python3
"""单张生成 - 给 prompt 和可选参考图,出一张图到指定路径

用法:
  export GEMINI_API_KEY=...
  python generate.py "your prompt" --ref idle.png --out walk_a.png
"""
import os
import sys
import argparse
import io
from pathlib import Path
from typing import Optional

from google import genai
from google.genai import types
from PIL import Image


def generate(prompt: str, reference_path: Optional[str], output_path: str) -> str:
    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        sys.exit("ERROR: 先 export GEMINI_API_KEY=...")

    client = genai.Client(api_key=api_key)

    parts: list = [prompt]
    if reference_path and Path(reference_path).exists():
        parts.append(Image.open(reference_path))

    response = client.models.generate_content(
        model="gemini-2.5-flash-image",
        contents=parts,
    )

    for candidate in response.candidates:
        for part in candidate.content.parts:
            if part.inline_data:
                with open(output_path, "wb") as f:
                    f.write(part.inline_data.data)
                print(f"  ✓ saved {output_path}")
                return output_path

    sys.exit(f"ERROR: 响应里没找到图像数据。\n完整响应: {response}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("prompt")
    parser.add_argument("--ref", default=None, help="可选 reference image 路径")
    parser.add_argument("--out", default="output.png")
    args = parser.parse_args()
    generate(args.prompt, args.ref, args.out)
