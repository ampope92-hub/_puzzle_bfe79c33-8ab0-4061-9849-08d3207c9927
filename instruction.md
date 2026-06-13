Hey, I've got a fun internal project for you. We want to build a little terminal-based puzzle game that teaches people FFmpeg filtergraphs by having them solve progressively harder media transformation challenges.

Here's what I'm thinking: a Python script at `/app/ffpuzzle.py` that runs a series of levels. Each level generates a small synthetic input (video or audio) using FFmpeg's lavfi sources — no external media files needed — describes a goal transformation, and asks the player to type in a filtergraph expression that achieves it. The game runs their filtergraph through FFmpeg, then checks the output with ffprobe to see if it meets the level's requirements (dimensions, pixel format, duration, etc.).

We need exactly 5 levels:

1. Scale a 640x480 video down to 320x240
2. Convert a video to grayscale (output pixel format must be `gray`) — use `.avi` container with rawvideo codec for this one so the pix_fmt is preserved exactly
3. Trim a 10-second audio clip to exactly 3 seconds
4. Crop the center 200x200 region from a 640x480 video
5. A multi-step challenge — take a 640x480 video, scale it to 320x240, AND apply a horizontal flip. One catch for this level: use nearest-neighbor scaling rather than the default scaler, so the pixels come out exactly reproducible. Our CI re-derives this level's frames the same way and compares frame hashes, so the scaler choice has to match — the default bicubic scaler will not pass even though the dimensions look right

For file naming, follow this convention strictly:
- Inputs go in `/app/assets/`: `level1_input.mp4`, `level2_input.avi`, `level3_input.wav`, `level4_input.mp4`, `level5_input.mp4`
- Outputs go in `/app/output/`: `level1_output.mp4`, `level2_output.avi`, `level3_output.wav`, `level4_output.mp4`, `level5_output.mp4`

The important part: the game needs a noninteractive auto-solve mode (triggered by `python ffpuzzle.py --auto-solve`) that runs through all levels with the known correct solutions. This mode should:
- Print each level as "Level N: <name>" as it runs
- Print "PASS" or "FAIL" for each level (indented with two spaces)
- Print a final score line in exactly this format: `Score: X/Y` (where X is points earned, Y is total possible — each level is worth 10 points)
- Generate all output artifacts in `/app/output/`
- Write a JSON manifest to `/app/manifest.json`

The manifest must be a JSON array (not an object) — each entry is an object with exactly these keys:
- `"level"`: the level number (integer)
- `"filename"`: the output filename (string)
- `"passed"`: whether validation passed (boolean)

So it looks like:
```json
[
  {"level": 1, "filename": "level1_output.mp4", "passed": true},
  ...
]
```

For interactive mode (just `python ffpuzzle.py`), show the level description, accept user input, validate, and show results. The player types a filtergraph at the prompt; also let them type `skip` to bypass the current level and move straight on to the next one without running FFmpeg (a skipped level just counts as not passed). But honestly the auto-solve mode is what matters most for our CI pipeline — make sure that path is rock solid and deterministic.

Each level's validation should use ffprobe's JSON output to check the relevant stream properties. Be strict about it: if the level says 320x240, check that width==320 and height==240 exactly. For the audio trim, check the duration is between 2.9 and 3.1 seconds.

One thing on the video levels (1, 4, and 5): encode the MP4 outputs with plain libx264 — just `-c:v libx264 -pix_fmt yuv420p`, no `-crf` or `-preset` tweaks. Our CI re-derives the expected frames the exact same way and compares them, so sticking to the defaults is what keeps the outputs reproducible.

Both `/app/assets/` and `/app/output/` directories should be created automatically by the script if they don't exist.

Oh — one more thing. Don't store the level solutions as plaintext strings in the source code. It's a puzzle game, we don't want someone to just open ffpuzzle.py and read all the answers. Base64-encode them, reverse the strings, ROT13, whatever you want — just make sure the actual filtergraph solutions aren't sitting there in the clear. This applies to the whole source file, not just the obvious solution variable: don't leave the literal answer filtergraph in a hint string, a comment, or anywhere else a player could read it directly.

FFmpeg and ffprobe are already installed in the environment. Let me know if you have questions.
