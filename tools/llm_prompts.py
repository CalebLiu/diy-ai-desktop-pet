#!/usr/bin/env python3
"""LLM-driven per-frame prompt generator.

所有角色(人形、生物、拟人化物体)都走这条路径。文本模型读 profile,
针对该角色的真实形态 + 签名特征,给每帧写 anatomy-aware prompt。

用法:
  from llm_prompts import generate_frame_prompts
  prompts = generate_frame_prompts(profile_dict)  # → {"walk_a": "...", ...}
"""
import json
import os
import sys
from typing import Dict

from google import genai


# (frame_suffix, 语义描述给 LLM 看)
FRAME_SPECS = [
    ("blink",        "Idle pose, eyes peacefully closed for one frame of blinking. Body identical to idle reference."),
    ("resting",      "Standing calmly with eyes peacefully closed, slightly relaxed/tired vibe, meditating posture."),
    ("walk_a",       "First frame of walking animation. Character in clear 3/4 SIDE VIEW facing RIGHT (NOT head-on front view — chest/head angled 30-45° toward right side of frame). Use the character's ACTUAL gait — bipedal stride for humans, bipedal hop for a small round creature, four-legged trot for quadrupeds, etc. Body in DOWN phase of bounce (lower than idle). One foot leads forward (right side of frame), other foot trails behind (left side of frame, lifted heel). DUST PUFF + speed lines on the SCREEN-LEFT side of the character (the trailing/rear side)."),
    ("walk_mid",     "Middle frame of walking animation. Same 3/4 side view facing RIGHT. Transition / passing pose. Body CLEARLY LIFTED UP — highest point of the walking bounce, visibly higher than walk_a and walk_b. Limbs in neutral passing position. NO dust puff."),
    ("walk_b",       "Third frame of walking animation. Same 3/4 side view facing RIGHT as walk_a (NOT mirrored facing). REVERSED FOOT POSITIONS from walk_a: the foot that was trailing is now leading forward (right side of frame), and the foot that was leading is now trailing (left side of frame, lifted heel). DUST PUFF + speed lines on the SCREEN-LEFT side (SAME side as walk_a — never on opposite side). Body in DOWN phase, same height as walk_a."),
    ("thinking_a",   "Signature power buildup — SMALLEST intensity. Character entering signature stance, subtle signature effect just beginning (use signature_power_small from profile)."),
    ("thinking_ab",  "Signature power buildup — between small and medium. Effect slightly stronger than thinking_a but not yet medium."),
    ("thinking_b",   "Signature power — MEDIUM intensity (use signature_power_medium from profile). Effect clearly visible around character. Face must remain fully visible."),
    ("thinking_bc",  "Signature power — between medium and full. Effect extending outward, partial aura forming."),
    ("thinking_c",   "Signature power — FULL POWER (use signature_power_full from profile). Maximum effect, character at peak focus. Face MUST remain visible through the effect."),
    ("done_a",       "Celebration mid-gesture. Body starting to raise into celebration pose, smile beginning to form, energy starting to gather."),
    ("done_b",       "Full celebration pose with effects (use done_celebration_pose and done_celebration_effect from profile)."),
    ("peek_right",   "Mini-mode EDGE-CLING pose for the RIGHT screen edge. The character is clinging to a vertical edge on the character's RIGHT and peeking out toward the LEFT (into the screen). Composition: character lives in the LEFT portion of the frame — head, face, one shoulder and the GRIPPING HAND(S) are on the screen-LEFT side and fully visible; the lower body/legs curve away toward the RIGHT side of the frame (they will be clipped off-screen by the app). At least one hand visibly GRIPS a vertical ledge to the character's right, fingers curled over it as if holding on and pulling the body around the corner. Head and eyes turned LEFT with a curious, playful peeking expression. This is a HALF-HIDDEN peek-around-the-corner cling, NOT an upright standing pose. The peek_left frame is produced automatically by horizontally mirroring this one, so draw ONLY the right-edge version."),
]


SYSTEM_INSTRUCTION = """You are designing an animated sprite sheet for a desktop pet companion.

The character is provided as a chibi Q-version reference image (idle pose). For each frame in the spec, you write an image-edit prompt that will be sent to Gemini's image model with the idle image as reference.

# UNIVERSAL CONSTRAINTS (apply to every prompt you write)

1. **EDIT THE REFERENCE framing**: every prompt must START with: "EDIT THE REFERENCE IMAGE. Keep face, head shape, eyes, mouth, body proportions, signature features (NAME THEM EXPLICITLY) and outfit/color palette IDENTICAL. ONLY change pose and effects below." Do not let the model freelance the character.

2. **Signature visual features reinforced EVERY frame**: extract the 3-5 most iconic visual signatures from the profile (e.g. for a small electric creature: "BLACK-TIPPED ears, two RED cheek circles, YELLOW LIGHTNING-BOLT tail with brown base"; for a flame-themed swordsman: "yellow-red flame hair, white cape with red flame hem, golden eyes"). Repeat them by name in every prompt — image models drop details if not repeated.

2a. **COLOR ANCHOR RULE**: when a color word (BLACK, RED, etc.) appears in a signature feature, the prompt MUST also explicitly say what color the OTHER body parts are. Otherwise image models bleed the color across the character. Example: if you say "BLACK-TIPPED ears", ALWAYS pair it with "the rest of the body (face, torso, limbs, tail) is YELLOW; ONLY the ear tips are black". Never let a color word stand alone — always specify scope.

3. **Camera / framing identical across frames**: same chibi proportions, same camera distance, same 3/4-to-front angle. Full body visible, character centered.

4. **Background**: every prompt must include "transparent PNG background, no scenery, no checkerboard pattern, character isolated".

5. **No text, no watermark, no signature, no border** — every prompt must say this.

# ANATOMY AWARENESS (critical for non-human characters)

- Humans / humanoids: bipedal stride. walk_a = LEFT foot forward, walk_b = RIGHT foot forward. Alternation is via foot position.
- Bipedal cartoon creatures (small round, short-legged): short-legged HOPPING walk. walk_a = leans one way + that leg leads, walk_b = leans the other way. Alternation is via lean direction.
- Quadrupeds: diagonal pair gait (e.g., walk_a = front-left + back-right forward, walk_b = front-right + back-left forward).
- Serpentine / slithering: alternate the direction of the body S-curve.
- Flying / floating: alternate slight body tilt + wing position.

If a profile suggests the character is unusual (winged, tailed, four-legged, etc.) PICK THE RIGHT GAIT for that anatomy. Never impose human walking on non-humans.

# WALK FRAMES — CRITICAL DIRECTION + DUST RULES

The animation engine FLIPS the sprite horizontally when the character moves LEFT (and shows the original when moving RIGHT). This means:
1. **Every walk frame must be drawn with the character FACING RIGHT — clearly side-leaning, not head-on front view.**
2. **Dust puff position must be CONSISTENT across walk_a and walk_b** — both on the SCREEN-LEFT side (which is "behind" the rightward-facing character). The engine's flip will move dust to screen-right automatically when moving left. If walk_a and walk_b have dust on OPPOSITE sides, the result is moonwalk in one of the two states.

## Facing direction (mandatory wording)
For walk_a, walk_mid, walk_b, every prompt MUST include language like:
"The character is shown in a clear 3/4 side view, body angled so the character's CHEST AND HEAD ARE ORIENTED TOWARD THE RIGHT SIDE OF THE FRAME (approximately 30-45 degrees off head-on). This is NOT a head-on front view — there is a visible lean and clear side-profile elements (e.g., one ear, one cheek, one shoulder are foreground; the other side is partially behind/further from camera). The character is mid-stride moving RIGHTWARD."

## Foot alternation (the only thing that changes between a and b)
- walk_a: ONE specific foot (pick by anatomy, e.g. "the LEFT foot if character is humanoid") is stepped FORWARD (more to the right side of the frame), the OTHER foot is TRAILING (lifted heel, behind on the screen-LEFT side).
- walk_b: REVERSED — the OTHER foot is now forward (more to the right), the FIRST foot is now trailing on screen-LEFT.

## Dust puff (MUST be on screen-LEFT in BOTH walk_a and walk_b)
- walk_a: "Small white/gray dust puff cloud + speed lines on the SCREEN-LEFT side of the character (rear/trailing side), behind the trailing foot."
- walk_b: "Small white/gray dust puff cloud + speed lines on the SCREEN-LEFT side of the character (rear/trailing side), SAME side as walk_a. The dust never moves to the right — the engine handles left-motion via horizontal flip."
- walk_mid: NO dust puff. Both limbs in mid-air passing pose, body lifted to highest point.

## Why same-side dust (do not get clever)
If walk_a has dust on screen-LEFT and walk_b has dust on screen-RIGHT, the result is:
- Moving right: walk_b's right-side dust appears in FRONT of motion → moonwalk.
- Moving left (flipped): walk_a's now-right-side dust appears in FRONT → moonwalk.
By keeping dust on the same side (always screen-LEFT in source), the flip places it correctly behind motion in both directions.

# THINKING (signature power) PROGRESSION

The 5 thinking frames are a progressive power-buildup loop. Each step's effect intensity comes from the profile fields:
- thinking_a → signature_power_small
- thinking_b → signature_power_medium
- thinking_c → signature_power_full
- thinking_ab is BETWEEN a and b
- thinking_bc is BETWEEN b and c

Use the profile's signature_pose for the body stance across all 5 frames. Only effect intensity changes.

# REMBG SILHOUETTE RULE (critical for thinking_b, thinking_bc, thinking_c, done_b)

These frames have visual effects (auras, glows, particles) around the character. An automated background-removal step (rembg) runs AFTER image generation. If the effect fully envelops the character body in a continuous glow, rembg will mistake the aura for the character and strip the character along with it.

EVERY prompt that includes signature effects MUST therefore say:
- "The character's body must be drawn FULLY OPAQUE with a CLEAR SHARP SILHOUETTE — the body must be visibly distinguishable from the aura/effect."
- "The aura/effect MUST be drawn as DISCRETE PARTICLES, ARCS, ELECTRIC BOLTS, or A HALO RING WITH VISIBLE GAPS — NOT as a solid continuous glow filling the space between body and aura edge."
- "There must be visible negative space (transparent gaps) between the character body and the aura particles."

This is non-negotiable for thinking_b/bc/c and done_b.

# DONE (celebration) FRAMES

- done_a: mid-gesture, arm raising / energy gathering, smile starting
- done_b: full celebration pose from profile.done_celebration_pose + profile.done_celebration_effect

# PEEK (mini-mode edge-cling) FRAME

peek_right is the sprite shown when the pet is docked at a screen edge in mini mode. The app slides most of the window off-screen and only the inner ~100px stays visible, so the character must read as "peeking around a corner", clinging to the edge.

- The character CLINGS to a vertical edge on the character's RIGHT and PEEKS toward the LEFT (into the screen).
- Composition is asymmetric on purpose: put the HEAD, face, near shoulder and the GRIPPING HAND(S) in the LEFT portion of the frame; let the lower body / legs curve away toward the RIGHT side (the app clips that part off-screen).
- At least one hand must VISIBLY GRIP a vertical edge — fingers curled over an implied ledge to the character's right. DO NOT draw an actual wall, ledge object, or shelf — the grip pose alone implies the edge; everything outside the character stays transparent.
- Head and eyes turned LEFT, curious/playful peeking expression. Keep the character's signature features (name them) and outfit IDENTICAL to the reference.
- This is a HALF-HIDDEN cling, NOT an upright standing pose.
- The engine does NOT flip sprites in mini mode; the left-edge sprite (peek_left) is generated by horizontally mirroring peek_right, so you only write the right-edge version.
- Body must stay FULLY OPAQUE with a CLEAR SHARP SILHOUETTE (rembg runs afterward).

# OUTPUT FORMAT

Output STRICT JSON only. No markdown code fences, no commentary, no preamble. Schema:

{
  "blink": "...",
  "resting": "...",
  "walk_a": "...",
  "walk_mid": "...",
  "walk_b": "...",
  "thinking_a": "...",
  "thinking_ab": "...",
  "thinking_b": "...",
  "thinking_bc": "...",
  "thinking_c": "...",
  "done_a": "...",
  "done_b": "...",
  "peek_right": "..."
}

Each prompt: 3-6 sentences. Be concrete about pose direction, effect details, and signature features by name."""


def _build_user_message(profile: dict) -> str:
    frames_text = "\n".join(f"- {name}: {desc}" for name, desc in FRAME_SPECS)
    return f"""Character profile (the AUTHORITATIVE source for all visual + signature details):

```json
{json.dumps(profile, ensure_ascii=False, indent=2)}
```

Frames to write prompts for (in order):
{frames_text}

Now generate the JSON object with one prompt per frame. Remember:
- EDIT THE REFERENCE IMAGE framing on every prompt
- Reinforce this character's signature visual features by name in EVERY frame
- Anatomy-appropriate gait
- Dust puff alternating between walk_a and walk_b
- Transparent PNG background, no scenery, no text
- 3-6 sentences per prompt"""


def generate_frame_prompts(profile: dict) -> Dict[str, str]:
    """读 profile,返回 12 帧 prompt(不含 idle)。

    idle 由 character_frames.build_idle_prompt 单独处理(它无 reference,需要锁定 style)。
    """
    import time as _time
    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        sys.exit("ERROR: 先 export GEMINI_API_KEY=...")

    client = genai.Client(api_key=api_key)
    user_msg = _build_user_message(profile)

    # 503 临时过载是常态,简单 retry
    last_err = None
    for attempt in range(5):
        try:
            response = client.models.generate_content(
                model="gemini-2.5-flash",
                contents=[SYSTEM_INSTRUCTION, user_msg],
            )
            break
        except Exception as e:
            last_err = e
            msg = str(e)
            if "503" in msg or "UNAVAILABLE" in msg or "overloaded" in msg.lower():
                wait = 5 * (attempt + 1)
                print(f"  ⚠ 503 过载, {wait}s 后重试 (attempt {attempt+1}/5)...", file=sys.stderr)
                _time.sleep(wait)
                continue
            raise
    else:
        sys.exit(f"重试 5 次仍失败: {last_err}")

    text = (response.text or "").strip()
    # strip markdown fences if model added them despite instruction
    if text.startswith("```"):
        text = text.strip("`")
        if text.startswith("json"):
            text = text[4:]
        text = text.strip()
        if text.endswith("```"):
            text = text[:-3].strip()

    try:
        prompts = json.loads(text)
    except json.JSONDecodeError as e:
        sys.exit(f"LLM 没返回有效 JSON:\n{text}\n\n错误: {e}")

    expected = {name for name, _ in FRAME_SPECS}
    got = set(prompts.keys())
    missing = expected - got
    if missing:
        sys.exit(f"LLM 输出缺帧: {missing}\n收到的: {sorted(got)}")

    return prompts


# 兼容旧名(过渡期):
generate_creature_prompts = generate_frame_prompts


if __name__ == "__main__":
    # CLI smoke test: python tools/llm_prompts.py example
    import argparse
    from pathlib import Path

    ap = argparse.ArgumentParser()
    ap.add_argument("slug")
    args = ap.parse_args()

    profile_path = Path(__file__).resolve().parent / "profiles" / f"{args.slug}.json"
    profile = json.loads(profile_path.read_text(encoding="utf-8"))
    prompts = generate_frame_prompts(profile)
    print(json.dumps(prompts, ensure_ascii=False, indent=2))
