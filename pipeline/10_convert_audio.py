"""Step 10: convert media/*.mp3 to HE-AAC .m4a for the iOS app bundle.

Halves the audio payload (~371 MB MP3 -> ~180 MB HE-AAC mono 24 kbps) with
no perceptible loss for 24 kHz TTS speech. Output layout expected by the app:

    data/app/audio/words/word_<id>.m4a
    data/app/audio/sentences/sent_<id>.m4a

Resumable: skips destinations that exist and are newer than the source.

Usage: python 10_convert_audio.py [--check] [--limit N] [--workers N]
"""
import argparse
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from lib import MEDIA, ROOT

APP_AUDIO = ROOT / "data" / "app" / "audio"


def dest_for(src: Path) -> Path:
    sub = "words" if src.name.startswith("word_") else "sentences"
    return APP_AUDIO / sub / (src.stem + ".m4a")


def convert(src: Path) -> tuple[Path, str | None]:
    dst = dest_for(src)
    if dst.exists() and dst.stat().st_size > 0 and dst.stat().st_mtime >= src.stat().st_mtime:
        return src, "skipped"
    proc = subprocess.run(
        ["afconvert", "-f", "m4af", "-d", "aach", "-b", "24000", "-q", "127",
         str(src), str(dst)],
        capture_output=True, text=True,
    )
    if proc.returncode != 0:
        dst.unlink(missing_ok=True)
        return src, proc.stderr.strip() or f"afconvert exit {proc.returncode}"
    return src, None


def check() -> int:
    srcs = sorted(MEDIA.glob("*.mp3"))
    missing = [s.name for s in srcs if not dest_for(s).exists()]
    n_words = len(list((APP_AUDIO / "words").glob("*.m4a")))
    n_sents = len(list((APP_AUDIO / "sentences").glob("*.m4a")))
    print(f"sources: {len(srcs)} mp3 | converted: {n_words} words + {n_sents} sentences")
    if missing:
        print(f"MISSING {len(missing)}: {missing[:10]}{' ...' if len(missing) > 10 else ''}")
        return 1
    print("OK: all sources converted")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="verify count parity, no conversion")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--workers", type=int, default=8)
    args = ap.parse_args()

    if args.check:
        return check()

    (APP_AUDIO / "words").mkdir(parents=True, exist_ok=True)
    (APP_AUDIO / "sentences").mkdir(parents=True, exist_ok=True)

    srcs = sorted(MEDIA.glob("*.mp3"))
    if args.limit:
        srcs = srcs[: args.limit]
    stats = {"done": 0, "skipped": 0, "failed": 0}
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        futures = [ex.submit(convert, s) for s in srcs]
        for i, fut in enumerate(as_completed(futures), 1):
            src, err = fut.result()
            if err == "skipped":
                stats["skipped"] += 1
            elif err is None:
                stats["done"] += 1
            else:
                stats["failed"] += 1
                print(f"FAIL {src.name}: {err}")
            if i % 1000 == 0:
                print(f"{i}/{len(srcs)} ({stats})")
    print(f"converted {stats['done']}, skipped {stats['skipped']}, failed {stats['failed']}")
    return 1 if stats["failed"] else 0


if __name__ == "__main__":
    sys.exit(main())
