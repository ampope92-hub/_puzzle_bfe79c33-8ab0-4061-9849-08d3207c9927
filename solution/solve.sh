#!/usr/bin/env bash
set -euo pipefail

mkdir -p /app/assets /app/output

cat > /app/ffpuzzle.py << 'PYEOF'
#!/usr/bin/env python3
"""FFmpeg Filtergraph Terminal Puzzle Game."""

import argparse
import base64
import json
import subprocess
import sys
from pathlib import Path

ASSETS_DIR = Path("/app/assets")
OUTPUT_DIR = Path("/app/output")
MANIFEST_PATH = Path("/app/manifest.json")


def _d(s):
    return base64.b64decode(s).decode()


LEVELS = [
    {
        "id": 1,
        "name": "Scale Down",
        "description": (
            "The input is a 640x480 video. Scale it down to 320x240.\n"
            "Hint: the 'scale' filter takes width:height."
        ),
        "gen_args": [
            "-f", "lavfi", "-i", "testsrc2=size=640x480:rate=25:duration=1",
            "-pix_fmt", "yuv420p", "-c:v", "libx264", "-t", "1",
        ],
        "input_file": "level1_input.mp4",
        "output_file": "level1_output.mp4",
        "output_args": ["-c:v", "libx264", "-pix_fmt", "yuv420p"],
        "solution": _d("c2NhbGU9MzIwOjI0MA=="),
        "checks": {"width": 320, "height": 240},
        "stream_type": "video",
        "points": 10,
    },
    {
        "id": 2,
        "name": "Grayscale",
        "description": (
            "Convert the input video to grayscale.\n"
            "The output pixel format should be 'gray'."
        ),
        "gen_args": [
            "-f", "lavfi", "-i", "testsrc2=size=320x240:rate=25:duration=1",
            "-pix_fmt", "rgb24", "-c:v", "rawvideo",
        ],
        "input_file": "level2_input.avi",
        "output_file": "level2_output.avi",
        "output_args": ["-c:v", "rawvideo"],
        "solution": _d("Zm9ybWF0PWdyYXk="),
        "checks": {"pix_fmt": "gray"},
        "stream_type": "video",
        "points": 10,
    },
    {
        "id": 3,
        "name": "Trim Audio",
        "description": (
            "The input is a 10-second audio tone. Trim it to exactly 3 seconds.\n"
            "Hint: look at the 'atrim' filter."
        ),
        "gen_args": [
            "-f", "lavfi", "-i", "sine=frequency=440:duration=10",
            "-c:a", "pcm_s16le",
        ],
        "input_file": "level3_input.wav",
        "output_file": "level3_output.wav",
        "output_args": ["-c:a", "pcm_s16le"],
        "solution": _d("YXRyaW09ZHVyYXRpb249Mw=="),
        "checks": {"duration_min": 2.9, "duration_max": 3.1},
        "stream_type": "audio",
        "points": 10,
    },
    {
        "id": 4,
        "name": "Center Crop",
        "description": (
            "Crop the center 200x200 region from a 640x480 video.\n"
            "Hint: the 'crop' filter takes w:h:x:y."
        ),
        "gen_args": [
            "-f", "lavfi", "-i", "testsrc2=size=640x480:rate=25:duration=1",
            "-pix_fmt", "yuv420p", "-c:v", "libx264", "-t", "1",
        ],
        "input_file": "level4_input.mp4",
        "output_file": "level4_output.mp4",
        "output_args": ["-c:v", "libx264", "-pix_fmt", "yuv420p"],
        "solution": _d("Y3JvcD0yMDA6MjAwOihpdy0yMDApLzI6KGloLTIwMCkvMg=="),
        "checks": {"width": 200, "height": 200},
        "stream_type": "video",
        "points": 10,
    },
    {
        "id": 5,
        "name": "Scale and Flip",
        "description": (
            "Take the 640x480 input video, scale it to 320x240 using\n"
            "nearest-neighbor scaling, AND flip it horizontally.\n"
            "Chain two filters together with a comma."
        ),
        "gen_args": [
            "-f", "lavfi", "-i", "testsrc2=size=640x480:rate=25:duration=1",
            "-pix_fmt", "yuv420p", "-c:v", "libx264", "-t", "1",
        ],
        "input_file": "level5_input.mp4",
        "output_file": "level5_output.mp4",
        "output_args": ["-c:v", "libx264", "-pix_fmt", "yuv420p"],
        "solution": _d("c2NhbGU9MzIwOjI0MDpmbGFncz1uZWlnaGJvcixoZmxpcA=="),
        "checks": {"width": 320, "height": 240, "hflip": True},
        "stream_type": "video",
        "points": 10,
    },
]


def run_cmd(cmd, capture=True):
    result = subprocess.run(cmd, capture_output=capture, text=True)
    return result.returncode, result.stdout, result.stderr


def generate_input(level):
    ASSETS_DIR.mkdir(parents=True, exist_ok=True)
    input_path = ASSETS_DIR / level["input_file"]
    if input_path.exists():
        return input_path
    cmd = ["ffmpeg", "-y"] + level["gen_args"] + [str(input_path)]
    rc, _, stderr = run_cmd(cmd)
    if rc != 0:
        print(f"Error generating input for level {level['id']}: {stderr}", file=sys.stderr)
        sys.exit(1)
    return input_path


def probe_stream(filepath, stream_type):
    select = "v:0" if stream_type == "video" else "a:0"
    cmd = [
        "ffprobe", "-v", "quiet", "-print_format", "json",
        "-select_streams", select, "-show_streams", str(filepath),
    ]
    rc, stdout, _ = run_cmd(cmd)
    if rc != 0:
        return None
    data = json.loads(stdout)
    streams = data.get("streams", [])
    return streams[0] if streams else None


def probe_format(filepath):
    cmd = [
        "ffprobe", "-v", "quiet", "-print_format", "json",
        "-show_format", str(filepath),
    ]
    rc, stdout, _ = run_cmd(cmd)
    if rc != 0:
        return None
    data = json.loads(stdout)
    return data.get("format", {})


def compute_frame_hash(filepath):
    cmd = ["ffmpeg", "-i", str(filepath), "-f", "hash", "-hash", "md5", "-"]
    rc, stdout, _ = run_cmd(cmd)
    if rc != 0:
        return None
    for line in stdout.strip().split("\n"):
        if line.startswith("MD5="):
            return line.strip()
    return None


def run_filtergraph(level, filtergraph):
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    input_path = ASSETS_DIR / level["input_file"]
    output_path = OUTPUT_DIR / level["output_file"]
    flag = "-vf" if level["stream_type"] == "video" else "-af"
    cmd = ["ffmpeg", "-y", "-i", str(input_path), flag, filtergraph] + level["output_args"] + [str(output_path)]
    rc, _, stderr = run_cmd(cmd)
    if rc != 0:
        return None, stderr
    return output_path, None


def validate_output(level, output_path):
    if output_path is None or not output_path.exists():
        return False, "Output file not found"

    checks = level["checks"]
    details = []

    if level["stream_type"] == "video":
        info = probe_stream(output_path, "video")
        if info is None:
            return False, "Could not probe video stream"
        if "width" in checks:
            actual = int(info.get("width", 0))
            if actual != checks["width"]:
                details.append(f"width: expected {checks['width']}, got {actual}")
        if "height" in checks:
            actual = int(info.get("height", 0))
            if actual != checks["height"]:
                details.append(f"height: expected {checks['height']}, got {actual}")
        if "pix_fmt" in checks:
            actual = info.get("pix_fmt", "")
            if actual != checks["pix_fmt"]:
                details.append(f"pix_fmt: expected {checks['pix_fmt']}, got {actual}")
        if checks.get("hflip"):
            ref_hash = compute_frame_hash(ASSETS_DIR / level["input_file"])
            out_hash = compute_frame_hash(output_path)
            if ref_hash and out_hash and ref_hash == out_hash:
                details.append("frames unchanged — hflip not applied")

    elif level["stream_type"] == "audio":
        fmt = probe_format(output_path)
        if fmt is None:
            return False, "Could not probe audio format"
        if "duration_min" in checks or "duration_max" in checks:
            duration = float(fmt.get("duration", 0))
            dmin = checks.get("duration_min", 0)
            dmax = checks.get("duration_max", float("inf"))
            if not (dmin <= duration <= dmax):
                details.append(f"duration: expected {dmin}-{dmax}s, got {duration:.2f}s")

    if details:
        return False, "; ".join(details)
    return True, "OK"


def interactive_mode():
    print("=" * 50)
    print("  FFmpeg Filtergraph Puzzle Game")
    print("=" * 50)
    print()

    total_points = 0
    earned_points = 0
    manifest = []

    for level in LEVELS:
        total_points += level["points"]
        print(f"--- Level {level['id']}: {level['name']} ---")
        print(level["description"])
        print()
        generate_input(level)
        print(f"Input: {ASSETS_DIR / level['input_file']}")
        print()

        while True:
            try:
                fg = input("Enter filtergraph (or 'skip' to skip): ").strip()
            except (EOFError, KeyboardInterrupt):
                print("\nExiting.")
                sys.exit(0)
            if fg.lower() == "skip":
                print("Skipped.\n")
                manifest.append({"level": level["id"], "filename": level["output_file"], "passed": False})
                break
            output_path, err = run_filtergraph(level, fg)
            if err:
                print(f"FFmpeg error: {err}")
                print("Try again.\n")
                continue
            passed, detail = validate_output(level, output_path)
            if passed:
                print(f"PASS — {detail}")
                earned_points += level["points"]
                manifest.append({"level": level["id"], "filename": level["output_file"], "passed": True})
                break
            else:
                print(f"FAIL — {detail}")
                print("Try again.\n")
        print()

    print(f"Score: {earned_points}/{total_points}")
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Manifest written to {MANIFEST_PATH}")


def auto_solve_mode():
    total_points = 0
    earned_points = 0
    manifest = []

    for level in LEVELS:
        total_points += level["points"]
        print(f"Level {level['id']}: {level['name']}")
        generate_input(level)
        output_path, err = run_filtergraph(level, level["solution"])

        if err:
            print("  FAIL (ffmpeg error)")
            manifest.append({"level": level["id"], "filename": level["output_file"], "passed": False})
            continue

        passed, detail = validate_output(level, output_path)
        if passed:
            print("  PASS")
            earned_points += level["points"]
        else:
            print(f"  FAIL ({detail})")
        manifest.append({"level": level["id"], "filename": level["output_file"], "passed": passed})

    print(f"Score: {earned_points}/{total_points}")
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Manifest written to {MANIFEST_PATH}")


def main():
    parser = argparse.ArgumentParser(description="FFmpeg Filtergraph Puzzle Game")
    parser.add_argument("--auto-solve", action="store_true",
                        help="Run all levels with known solutions (noninteractive)")
    args = parser.parse_args()
    ASSETS_DIR.mkdir(parents=True, exist_ok=True)
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    if args.auto_solve:
        auto_solve_mode()
    else:
        interactive_mode()


if __name__ == "__main__":
    main()
PYEOF

chmod +x /app/ffpuzzle.py
