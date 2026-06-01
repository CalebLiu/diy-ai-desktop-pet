#!/usr/bin/env python3
"""通用角色 sprite 生成 pipeline(LLM-driven prompts)。

profile 在 tools/profiles/<slug>.json,定义角色专属字段。
本脚本读 profile,调 Gemini 文本模型为每帧写 anatomy-aware prompt,
再调 nano banana(gemini-2.5-flash-image) 出 13 帧,自动 rembg 扣背景。

用法:
  export GEMINI_API_KEY=...

  python3 tools/character_frames.py example            # 生成示例角色到 preview/example/
  python3 tools/character_frames.py example            # 生成到 preview/example/
  python3 tools/character_frames.py <slug> --dry-run   # 只打印 prompts,不调图像 API(仍调文本)
  python3 tools/character_frames.py <slug> --output-dir /path  # 自定义输出路径

加新角色:
  1. 在 tools/profiles/ 写 <slug>.json(模仿 example.json)
  2. python3 tools/character_frames.py <slug>
  3. ./tools/install_character.sh <slug>
"""
import argparse
import json
import os
import sys
import time
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOOLS = ROOT / "tools"
PROFILES_DIR = TOOLS / "profiles"

# 让 import llm_prompts 工作
sys.path.insert(0, str(TOOLS))
from llm_prompts import generate_frame_prompts, FRAME_SPECS  # noqa: E402


# ─────────────────────────────────────────────────────────
# Profile 加载
# ─────────────────────────────────────────────────────────

REQUIRED_FIELDS = [
    "slug", "full_name", "appearance", "quick_visual",
    "idle_pose", "expression_default",
    "signature_pose", "signature_power_small",
    "signature_power_medium", "signature_power_full",
    "done_celebration_pose", "done_celebration_effect",
]


def load_profile(slug: str) -> dict:
    path = PROFILES_DIR / f"{slug}.json"
    if not path.exists():
        available = sorted(p.stem for p in PROFILES_DIR.glob("*.json"))
        sys.exit(f"找不到 profile: {path}\n可用 slug: {available}")
    profile = json.loads(path.read_text(encoding="utf-8"))
    missing = [f for f in REQUIRED_FIELDS if f not in profile]
    if missing:
        sys.exit(f"profile {path.name} 缺字段: {missing}")
    return profile


# ─────────────────────────────────────────────────────────
# idle prompt(唯一的硬编码模板:无 reference,需要锁定 style)
# ─────────────────────────────────────────────────────────

def build_idle_prompt(p: dict) -> str:
    appearance = "\n".join(f"- {item}" for item in p["appearance"])
    return f"""Generate a chibi Q-version full body portrait of {p["full_name"]}.

Character details (be precise, this anchors the visual style for all subsequent frames):
{appearance}

Style:
- Clean anime cel-shading with smooth, consistent line work
- True chibi Q-version proportions: head-to-body ratio approximately 1:2 (large head, small body)
- Full body visible from head to feet, centered in frame
- Character facing camera directly, no perspective tilt
- Bright saturated colors

Pose: Standing relaxed with {p["idle_pose"]}, peaceful idle pose.

Background (CRITICAL):
- TRUE transparent PNG background with alpha channel = 0
- DO NOT draw a checkerboard pattern
- DO NOT use a white background
- NO scenery, NO environment, NO decorations
- Character completely isolated, every pixel outside the character must be fully transparent

Output: high resolution, no text, no watermark, no signature, no border.
"""


def build_common_prefix(p: dict) -> str:
    short_name = p["full_name"].split(" from ")[0].split(" - ")[0]
    return (
        f"Same character as the reference image (chibi Q-version {short_name}, "
        f"{p['quick_visual']}). "
        "Transparent PNG background, no scenery, no checkerboard, isolated character only.\n\n"
    )


# ─────────────────────────────────────────────────────────
# 调外部脚本生成 + 扣背景
# ─────────────────────────────────────────────────────────

def run_generate(prompt, ref, out_path):
    cmd = [sys.executable, str(TOOLS / "generate.py"), prompt, "--out", str(out_path)]
    if ref:
        cmd.extend(["--ref", str(ref)])
    subprocess.run(cmd, check=True)


def run_strip(out_path, model=None):
    cmd = [sys.executable, str(TOOLS / "strip_bg.py"), str(out_path)]
    if model:
        cmd.extend(["--model", model])
    subprocess.run(cmd, check=True)


# ─────────────────────────────────────────────────────────
# 主流程
# ─────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("slug", help="character slug (looks up tools/profiles/<slug>.json)")
    parser.add_argument("--dry-run", action="store_true", help="只打印 prompts,不调图像 API(仍调文本模型)")
    parser.add_argument("--output-dir", default=None, help="覆盖默认输出 (默认 preview/<slug>/)")
    args = parser.parse_args()

    profile = load_profile(args.slug)
    slug = profile["slug"]
    # 浅发角色在 profile 里写 "strip_model": "birefnet-general";默认 isnet-anime
    strip_model = profile.get("strip_model")

    output_dir = Path(args.output_dir) if args.output_dir else ROOT / "preview" / slug
    if not args.dry_run:
        output_dir.mkdir(parents=True, exist_ok=True)

    total = len(FRAME_SPECS) + 1   # +1 for idle
    print(f"角色: {profile.get('display_name', slug)} ({slug})")
    print(f"输出: {output_dir}")
    print()

    if not os.environ.get("GEMINI_API_KEY"):
        sys.exit("ERROR: 先 export GEMINI_API_KEY=...")

    # Step 0: 调文本模型,拿到 12 个 anatomy-aware frame prompt
    print("→ 调 Gemini 2.5 Flash 文本模型,为该角色写 12 帧 prompt ...")
    frame_prompts = generate_frame_prompts(profile)
    print(f"  ✓ 拿到 {len(frame_prompts)} 个 prompt\n")

    # Step 1: idle(无 reference,用硬编码模板锁定 style)
    idle_prompt = build_idle_prompt(profile)
    idle_path = output_dir / f"{slug}_idle.png"

    if args.dry_run:
        print("=" * 60)
        print(f"[1/{total}] {idle_path.name}  (no reference, hardcoded template)")
        print("=" * 60)
        print(idle_prompt)
    elif idle_path.exists():
        print(f"[1/{total}] ⏭  {idle_path.name} 已存在,跳过")
    else:
        print(f"[1/{total}] → {idle_path.name} (no reference)")
        run_generate(idle_prompt, None, idle_path)
        run_strip(idle_path, strip_model)
        time.sleep(1)

    # Step 2: 其他帧用 idle 作 reference + LLM-written prompts
    common = build_common_prefix(profile)
    for i, (suffix, _) in enumerate(FRAME_SPECS, start=2):
        action = frame_prompts[suffix]
        full_prompt = common + action
        out_path = output_dir / f"{slug}_{suffix}.png"

        if args.dry_run:
            print()
            print("=" * 60)
            print(f"[{i}/{total}] {out_path.name}  (LLM-written prompt)")
            print("=" * 60)
            print(full_prompt)
            continue

        if out_path.exists():
            print(f"[{i}/{total}] ⏭  {out_path.name} 已存在,跳过")
            continue

        print(f"[{i}/{total}] → {out_path.name}")
        run_generate(full_prompt, idle_path, out_path)
        run_strip(out_path, strip_model)
        time.sleep(1)

    # peek_left = peek_right 的水平镜像(引擎在 mini mode 不翻转,需预烘两张)
    if not args.dry_run:
        peek_right = output_dir / f"{slug}_peek_right.png"
        peek_left = output_dir / f"{slug}_peek_left.png"
        if peek_right.exists() and not peek_left.exists():
            from PIL import Image as _Image
            _Image.open(peek_right).transpose(_Image.FLIP_LEFT_RIGHT).save(peek_left)
            print(f"  ✓ 镜像生成 {peek_left.name}(peek_right 水平翻转)")

    if not args.dry_run:
        print(f"\n✓ 全部完成: {output_dir}")
        print(f"  下一步: ./tools/install_character.sh {slug}")


if __name__ == "__main__":
    main()
