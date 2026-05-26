import json
import subprocess
from pathlib import Path


GAME_SCRIPT = Path("/app/ffpuzzle.py")
ASSETS_DIR = Path("/app/assets")
OUTPUT_DIR = Path("/app/output")
MANIFEST_PATH = Path("/app/manifest.json")


def run_auto_solve():
    """Run the game in auto-solve mode, return (stdout, stderr, returncode)."""
    result = subprocess.run(
        ["python", str(GAME_SCRIPT), "--auto-solve"],
        capture_output=True,
        text=True,
        timeout=120,
    )
    return result.stdout, result.stderr, result.returncode


def ffprobe_stream(filepath, stream_type="video"):
    """Probe a stream and return its info dict."""
    select = "v:0" if stream_type == "video" else "a:0"
    result = subprocess.run(
        [
            "ffprobe", "-v", "quiet", "-print_format", "json",
            "-select_streams", select, "-show_streams", str(filepath),
        ],
        capture_output=True,
        text=True,
    )
    data = json.loads(result.stdout)
    streams = data.get("streams", [])
    return streams[0] if streams else {}


def ffprobe_format(filepath):
    """Probe format-level info and return it."""
    result = subprocess.run(
        [
            "ffprobe", "-v", "quiet", "-print_format", "json",
            "-show_format", str(filepath),
        ],
        capture_output=True,
        text=True,
    )
    data = json.loads(result.stdout)
    return data.get("format", {})


class TestGameScriptExists:
    def test_script_exists(self):
        """The main game script must exist."""
        assert GAME_SCRIPT.exists(), f"{GAME_SCRIPT} not found"

    def test_script_is_python(self):
        """The game script should be valid Python (importable without errors)."""
        result = subprocess.run(
            ["python", "-c", f"import py_compile; py_compile.compile('{GAME_SCRIPT}', doraise=True)"],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, f"Syntax error in {GAME_SCRIPT}: {result.stderr}"


class TestAutoSolveMode:
    def test_auto_solve_flag_accepted(self):
        """The game must accept --auto-solve flag and exit cleanly."""
        stdout, stderr, rc = run_auto_solve()
        assert rc == 0, f"Auto-solve exited with code {rc}.\nstdout: {stdout}\nstderr: {stderr}"

    def test_score_line_present(self):
        """Auto-solve output must contain a 'Score: X/Y' line."""
        stdout, _, _ = run_auto_solve()
        lines = stdout.strip().split("\n")
        score_lines = [line for line in lines if line.startswith("Score:")]
        assert len(score_lines) == 1, f"Expected exactly one Score line, got: {score_lines}"

    def test_perfect_score(self):
        """All levels must pass with known solutions — score should be 50/50."""
        stdout, _, _ = run_auto_solve()
        lines = stdout.strip().split("\n")
        score_lines = [line for line in lines if line.startswith("Score:")]
        assert len(score_lines) == 1
        score_line = score_lines[0]
        parts = score_line.replace("Score:", "").strip().split("/")
        earned = int(parts[0])
        total = int(parts[1])
        assert earned == total, f"Not a perfect score: {score_line}"
        assert total >= 50, f"Expected at least 50 total points (5 levels × 10), got {total}"

    def test_all_levels_printed(self):
        """Auto-solve should print each level name."""
        stdout, _, _ = run_auto_solve()
        for level_id in range(1, 6):
            assert f"Level {level_id}:" in stdout, f"Level {level_id} not mentioned in output"


class TestAssetGeneration:
    def test_assets_directory_exists(self):
        """Assets directory should be created after auto-solve."""
        run_auto_solve()
        assert ASSETS_DIR.is_dir(), f"{ASSETS_DIR} not found"

    def test_input_files_generated(self):
        """Each level should produce an input file in assets/."""
        run_auto_solve()
        expected = [
            "level1_input.mp4",
            "level2_input.avi",
            "level3_input.wav",
            "level4_input.mp4",
            "level5_input.mp4",
        ]
        for fname in expected:
            path = ASSETS_DIR / fname
            assert path.exists(), f"Missing input asset: {path}"
            assert path.stat().st_size > 0, f"Empty input asset: {path}"


class TestOutputArtifacts:
    def test_output_directory_exists(self):
        """Output directory should be created after auto-solve."""
        run_auto_solve()
        assert OUTPUT_DIR.is_dir(), f"{OUTPUT_DIR} not found"

    def test_output_files_generated(self):
        """Each level should produce an output file in output/."""
        run_auto_solve()
        expected = [
            "level1_output.mp4",
            "level2_output.avi",
            "level3_output.wav",
            "level4_output.mp4",
            "level5_output.mp4",
        ]
        for fname in expected:
            path = OUTPUT_DIR / fname
            assert path.exists(), f"Missing output artifact: {path}"
            assert path.stat().st_size > 0, f"Empty output artifact: {path}"


class TestLevel1ScaleDown:
    def test_output_dimensions(self):
        """Level 1 output must be exactly 320x240."""
        run_auto_solve()
        info = ffprobe_stream(OUTPUT_DIR / "level1_output.mp4", "video")
        assert int(info["width"]) == 320, f"Expected width 320, got {info['width']}"
        assert int(info["height"]) == 240, f"Expected height 240, got {info['height']}"


class TestLevel2Grayscale:
    def test_pixel_format(self):
        """Level 2 output must have gray pixel format."""
        run_auto_solve()
        info = ffprobe_stream(OUTPUT_DIR / "level2_output.avi", "video")
        assert info["pix_fmt"] == "gray", f"Expected pix_fmt 'gray', got '{info['pix_fmt']}'"


class TestLevel3TrimAudio:
    def test_audio_duration(self):
        """Level 3 output audio must be approximately 3 seconds."""
        run_auto_solve()
        fmt = ffprobe_format(OUTPUT_DIR / "level3_output.wav")
        duration = float(fmt["duration"])
        assert 2.9 <= duration <= 3.1, f"Expected ~3s duration, got {duration:.3f}s"


class TestLevel4CenterCrop:
    def test_cropped_dimensions(self):
        """Level 4 output must be exactly 200x200."""
        run_auto_solve()
        info = ffprobe_stream(OUTPUT_DIR / "level4_output.mp4", "video")
        assert int(info["width"]) == 200, f"Expected width 200, got {info['width']}"
        assert int(info["height"]) == 200, f"Expected height 200, got {info['height']}"


class TestLevel5ScaleAndFlip:
    def test_output_dimensions(self):
        """Level 5 output must be 320x240 (scaled down)."""
        run_auto_solve()
        info = ffprobe_stream(OUTPUT_DIR / "level5_output.mp4", "video")
        assert int(info["width"]) == 320, f"Expected width 320, got {info['width']}"
        assert int(info["height"]) == 240, f"Expected height 240, got {info['height']}"

    def test_hflip_applied(self):
        """Level 5 output frames must differ from a scale-only version (hflip applied)."""
        run_auto_solve()
        input_path = ASSETS_DIR / "level5_input.mp4"
        output_path = OUTPUT_DIR / "level5_output.mp4"
        ref_path = OUTPUT_DIR / "level5_ref_nohflip.mp4"
        subprocess.run(
            [
                "ffmpeg", "-y", "-i", str(input_path),
                "-vf", "scale=320:240",
                "-c:v", "libx264", "-pix_fmt", "yuv420p",
                str(ref_path),
            ],
            capture_output=True,
        )

        def frame_hash(path):
            r = subprocess.run(
                ["ffmpeg", "-i", str(path), "-f", "hash", "-hash", "md5", "-"],
                capture_output=True, text=True,
            )
            for line in r.stdout.strip().split("\n"):
                if line.startswith("MD5="):
                    return line.strip()
            return None

        ref_hash = frame_hash(ref_path)
        out_hash = frame_hash(output_path)
        assert ref_hash is not None and out_hash is not None, "Could not compute frame hashes"
        assert ref_hash != out_hash, "Output frames match scale-only reference — hflip not applied"


class TestManifest:
    def test_manifest_exists(self):
        """manifest.json must be created after auto-solve."""
        run_auto_solve()
        assert MANIFEST_PATH.exists(), f"{MANIFEST_PATH} not found"

    def test_manifest_is_valid_json(self):
        """manifest.json must be parseable JSON."""
        run_auto_solve()
        text = MANIFEST_PATH.read_text()
        data = json.loads(text)
        assert isinstance(data, list), "Manifest should be a JSON array"

    def test_manifest_has_all_levels(self):
        """Manifest should have an entry for each of the 5 levels."""
        run_auto_solve()
        data = json.loads(MANIFEST_PATH.read_text())
        level_ids = {entry["level"] for entry in data}
        for lvl in range(1, 6):
            assert lvl in level_ids, f"Level {lvl} missing from manifest"

    def test_manifest_entries_have_required_fields(self):
        """Each manifest entry must have level, filename, and passed fields."""
        run_auto_solve()
        data = json.loads(MANIFEST_PATH.read_text())
        for entry in data:
            assert "level" in entry, f"Missing 'level' in manifest entry: {entry}"
            assert "filename" in entry, f"Missing 'filename' in manifest entry: {entry}"
            assert "passed" in entry, f"Missing 'passed' in manifest entry: {entry}"

    def test_manifest_all_passed(self):
        """In auto-solve mode all manifest entries should show passed=true."""
        run_auto_solve()
        data = json.loads(MANIFEST_PATH.read_text())
        for entry in data:
            assert entry["passed"] is True, (
                f"Level {entry['level']} not marked as passed in manifest"
            )


class TestInteractiveMode:
    def test_auto_solve_documented(self):
        """The --auto-solve flag should be discoverable via --help or visible in the source."""
        source = GAME_SCRIPT.read_text()
        assert "auto-solve" in source or "auto_solve" in source, (
            "Neither 'auto-solve' nor 'auto_solve' found in game source"
        )


class TestSolutionObfuscation:
    def test_solutions_not_plaintext(self):
        """Level solutions must not appear as readable plaintext in the source."""
        source = GAME_SCRIPT.read_text()
        plaintext_solutions = [
            "atrim=duration=3",
            "crop=200:200:(iw-200)/2:(ih-200)/2",
            "scale=320:240,hflip",
            "format=gray",
        ]
        for sol in plaintext_solutions:
            assert sol not in source, (
                f"Plaintext solution '{sol}' found in source — "
                "solutions must be obfuscated (base64, reversed, etc.)"
            )


class TestDeterminism:
    def test_score_deterministic(self):
        """Running auto-solve twice should produce the same score line."""
        stdout1, _, _ = run_auto_solve()
        stdout2, _, _ = run_auto_solve()
        score1 = [line for line in stdout1.split("\n") if line.startswith("Score:")][0]
        score2 = [line for line in stdout2.split("\n") if line.startswith("Score:")][0]
        assert score1 == score2, f"Non-deterministic scores: '{score1}' vs '{score2}'"
