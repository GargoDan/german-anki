"""Step 5: generate German audio for all words and sentences with edge-tts.

Voice: de-DE-KatjaNeural (consistent across the whole dataset).
Nouns are spoken with their article ("die Gesellschaft"); other words and
sentences verbatim. Resumable: existing non-empty mp3 files are skipped.

Usage: python 05_audio.py [--words-only|--sentences-only] [--limit N]
"""
import asyncio
import re
import sys
from pathlib import Path

import edge_tts

sys.path.insert(0, str(Path(__file__).parent))
from lib import MEDIA, SENTENCES_CSV, WORDS_CSV, read_csv

VOICE = "de-DE-KatjaNeural"
CONCURRENCY = 8


def spoken_text(word: dict) -> str:
    if word["pos"] == "noun" and word["display"].startswith(("der ", "die ", "das ")):
        return re.split(r"[,(]", word["display"])[0].strip()
    if word["pos"] == "phrase":
        return word["lemma"]
    return word["lemma"]


async def synth(sem: asyncio.Semaphore, text: str, path: Path, stats: dict):
    if path.exists() and path.stat().st_size > 1000:
        stats["skipped"] += 1
        return
    async with sem:
        for attempt in range(3):
            try:
                # edge-tts can hang on a dead websocket; without a timeout one
                # stuck call permanently occupies a semaphore slot
                await asyncio.wait_for(
                    edge_tts.Communicate(text, VOICE).save(str(path)), timeout=60)
                stats["done"] += 1
                return
            except Exception as e:
                if attempt == 2:
                    stats["failed"] += 1
                    print(f"FAILED {path.name}: {e}")
                else:
                    await asyncio.sleep(2 * (attempt + 1))


async def main():
    args = sys.argv[1:]
    limit = None
    if "--limit" in args:
        limit = int(args[args.index("--limit") + 1])
    MEDIA.mkdir(exist_ok=True)
    jobs = []
    if "--sentences-only" not in args:
        for w in read_csv(WORDS_CSV):
            if w["status"] in ("rejected",):
                continue
            jobs.append((spoken_text(w), MEDIA / w["audio"]))
    if "--words-only" not in args and SENTENCES_CSV.exists():
        for s in read_csv(SENTENCES_CSV):
            jobs.append((s["de"], MEDIA / s["audio"]))
    if limit:
        jobs = jobs[:limit]
    sem = asyncio.Semaphore(CONCURRENCY)
    stats = {"done": 0, "skipped": 0, "failed": 0}
    total = len(jobs)
    tasks = [synth(sem, t, p, stats) for t, p in jobs]
    for i in range(0, len(tasks), 200):
        await asyncio.gather(*tasks[i:i + 200])
        print(f"progress {min(i + 200, total)}/{total}  {stats}")
    print("final:", stats)


if __name__ == "__main__":
    asyncio.run(main())
