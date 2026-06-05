# DIY AI Desktop Pet 🐾

A tiny macOS desktop pet that **reacts to your Claude Code / Codex sessions** — it thinks while your agent thinks and celebrates when a task finishes. The twist: **it ships with zero characters.** You generate your pet's art yourself with AI (bring your own Gemini API key) from a text profile, so you can make *any* character you want.

> No bundled sprites by design — pick/design your own character, keep it copyright-clean, and the fun part (the AI art pipeline) is the whole point.

*(Add a demo GIF here once you've generated a character.)*

## Features

- **Lives on your desktop** — idle breathing, blinking, calm wandering (it only shuffles around near its spot, so it won't march across your input box), auto-sleep when you're away.
- **Reacts to your AI agent** — via local HTTP hooks: enters a "thinking" state while your agent works, celebrates on finish, and shows a hover **task list** of active sessions you can click to jump back to.
- **Click-through except the character** — the window only intercepts clicks/hovers on the pet's actual pixels (per-pixel alpha hit-testing), so the transparent space around it never blocks the app underneath.
- **Edge dock (mini mode)** — drag it to a screen edge and it peeks around the corner (head + face stay visible, not just a sliver); hover to peek out, and the task list slides out to the **side that faces the screen interior** rather than over its head.
- **Fishbowl quick-launcher** — click the pet (or `⌘⌥M`) to open a "slack off" menu of sites in an **isolated Chrome profile**, so your fun browsing never pollutes your work tabs/logins. Sites are editable in-app.
- **EN / ZH** — UI auto-adapts to your system language, with a manual toggle in the menu.

## Requirements

- macOS 13+ and the [Swift toolchain](https://www.swift.org/install/macos/) (Xcode or Command Line Tools)
- A free **Gemini API key** → https://aistudio.google.com/apikey (for generating character art)
- Python 3 + deps for the art pipeline: `pip3 install google-genai pillow rembg onnxruntime`
- *(Optional)* Google Chrome — only needed for the fishbowl launcher

## Quick start

```bash
git clone <your-repo-url> diy-ai-desktop-pet
cd diy-ai-desktop-pet
swift run            # launches the pet (shows a "no character yet" placeholder)
```

You'll see a placeholder because no character ships with the repo. Generate one:

```bash
export GEMINI_API_KEY=...                       # from aistudio.google.com/apikey
pip3 install google-genai pillow rembg onnxruntime

python3 tools/character_frames.py example       # generates the bundled "Blobby" example profile
./tools/install_character.sh example            # installs it for the app
```

Restart `swift run`, then open the menu-bar **🔥 → Character** and pick your pet.

## Make your own character

The pipeline turns a short **text profile** into a full animated sprite set (idle, walk, blink, think, celebrate, edge-peek) — all consistent, background removed automatically.

1. Copy `tools/profiles/example.json` to `tools/profiles/<your-slug>.json` and describe your character (appearance, signature pose/effects). See **`PROMPT_TEMPLATE.md`** for how each field maps to a frame.
2. Generate + install:
   ```bash
   python3 tools/character_frames.py <your-slug>
   ./tools/install_character.sh <your-slug>
   ```
3. Restart and switch to it from the menu.

Notes:
- Light/low-saturation hair gets eaten by the default background remover — set `"strip_model": "birefnet-general"` in that character's profile.
- `tools/regen_peek.sh <slug>` regenerates just the edge-dock "peek" frames.
- Cost: Gemini 2.5 Flash Image is ~free-tier friendly; a full character is a handful of images.

⚠️ You're responsible for what you generate. Don't publish art of copyrighted/trademarked characters.

## Hook it to your AI agent

The pet listens on `http://127.0.0.1:7777`. Point your Claude Code / Codex lifecycle hooks at it to drive thinking/done states and the task list. See **`HOOKS.md`** for the endpoint spec and ready-made hook wiring.

```bash
# quick smoke test (pet must be running)
curl http://localhost:7777/health
curl -X POST localhost:7777/state -d '{"state":"thinking"}'
```

## Build a double-clickable .app

```bash
./tools/build_app.sh        # produces DeskPet.app (unsigned, local use)
```

## Config

- **Fishbowl sites:** edit in-app (menu → Edit) or `~/.config/deskpet/fishbowl.json`
- **Language:** menu-bar 🔥 → Language (Follow system / 中文 / English)

## License

MIT — see [LICENSE](LICENSE).
