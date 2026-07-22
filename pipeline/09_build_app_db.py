"""Step 9: build the read-only SQLite content database for the iOS app.

Reads data/processed/{words,sentences,word_sentence}.csv + topics.json and
writes data/app/content.sqlite. The app bundles this file as-is; all mutable
SRS state lives in a separate on-device database.

Validates that every word has exactly 3 linked sentences with exactly one
primary. ord=0 is the primary sentence, then 1,2 in stable sent_id order.

Usage: python 09_build_app_db.py [--audio-format m4a|mp3] [--verify-audio]
"""
import argparse
import json
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from lib import (LEVELS, ROOT, SENTENCES_CSV, WORD_SENTENCE_CSV, WORDS_CSV,
                 load_topics, read_csv)

APP_DIR = ROOT / "data" / "app"
DB_PATH = APP_DIR / "content.sqlite"
APP_AUDIO = APP_DIR / "audio"

SCHEMA = """
CREATE TABLE word (
  word_id     TEXT PRIMARY KEY,
  lemma       TEXT NOT NULL,
  display     TEXT NOT NULL,
  pos         TEXT NOT NULL,
  gender      TEXT,
  plural      TEXT,
  verb_forms  TEXT,
  level       TEXT NOT NULL,
  topic       TEXT NOT NULL,
  en          TEXT NOT NULL,
  ru          TEXT NOT NULL,
  freq_rank   INTEGER,
  audio       TEXT NOT NULL,
  qa_flagged  INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX idx_word_level_topic ON word(level, topic);
CREATE INDEX idx_word_level_freq ON word(level, freq_rank);

CREATE TABLE sentence (
  sent_id TEXT PRIMARY KEY,
  de TEXT NOT NULL,
  en TEXT NOT NULL,
  ru TEXT NOT NULL,
  audio TEXT
);

CREATE TABLE word_sentence (
  word_id TEXT NOT NULL REFERENCES word(word_id),
  sent_id TEXT NOT NULL REFERENCES sentence(sent_id),
  ord     INTEGER NOT NULL,
  PRIMARY KEY (word_id, ord)
);

CREATE TABLE topic (
  level TEXT NOT NULL,
  slug  TEXT NOT NULL,
  de    TEXT NOT NULL,
  en    TEXT NOT NULL,
  ord   INTEGER NOT NULL,
  PRIMARY KEY (level, slug)
);

CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);
"""


def audio_name(name: str, fmt: str) -> str:
    return name[: -len(".mp3")] + f".{fmt}" if fmt == "m4a" and name.endswith(".mp3") else name


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--audio-format", choices=["m4a", "mp3"], default="m4a")
    ap.add_argument("--verify-audio", action="store_true")
    args = ap.parse_args()

    words = read_csv(WORDS_CSV)
    sentences = read_csv(SENTENCES_CSV)
    links = read_csv(WORD_SENTENCE_CSV)
    topics = load_topics()

    by_word: dict[str, list[dict]] = {}
    for ln in links:
        by_word.setdefault(ln["word_id"], []).append(ln)
    bad = {w: ls for w, ls in by_word.items()
           if len(ls) != 3 or sum(int(l["is_primary"]) for l in ls) != 1}
    if bad or len(by_word) != len(words):
        print(f"FATAL: {len(bad)} words with bad sentence links, "
              f"{len(words) - len(by_word)} words without links")
        for w in list(bad)[:5]:
            print(f"  {w}: {bad[w]}")
        return 1

    APP_DIR.mkdir(parents=True, exist_ok=True)
    DB_PATH.unlink(missing_ok=True)
    db = sqlite3.connect(DB_PATH)
    db.executescript("PRAGMA journal_mode=DELETE; PRAGMA page_size=4096;")
    db.executescript(SCHEMA)

    db.executemany(
        "INSERT INTO word VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
        [(w["word_id"], w["lemma"], w["display"], w["pos"],
          w["gender"] or None, w["plural"] or None, w["verb_forms"] or None,
          w["level"], w["topic"], w["en"], w["ru"],
          int(w["freq_rank"]) if w["freq_rank"] else None,
          audio_name(w["audio"], args.audio_format),
          1 if w["status"] == "qa_flagged" else 0)
         for w in words])

    db.executemany(
        "INSERT INTO sentence VALUES (?,?,?,?,?)",
        [(s["sent_id"], s["de"], s["en"], s["ru"],
          audio_name(s["audio"], args.audio_format) if s["audio"] else None)
         for s in sentences])

    ws_rows = []
    for word_id, ls in by_word.items():
        primary = next(l for l in ls if int(l["is_primary"]) == 1)
        rest = sorted((l for l in ls if l is not primary), key=lambda l: l["sent_id"])
        for ord_, l in enumerate([primary] + rest):
            ws_rows.append((word_id, l["sent_id"], ord_))
    db.executemany("INSERT INTO word_sentence VALUES (?,?,?)", ws_rows)

    topic_rows = []
    for level in LEVELS:
        for i, t in enumerate(topics.get(level, [])):
            topic_rows.append((level, t["slug"], t["de"], t["en"], i))
    db.executemany("INSERT INTO topic VALUES (?,?,?,?,?)", topic_rows)

    db.executemany("INSERT INTO meta VALUES (?,?)", [
        ("schema_version", "1"),
        ("built_at", datetime.now(timezone.utc).strftime("%Y-%m-%d")),
        ("word_count", str(len(words))),
        ("sentence_count", str(len(sentences))),
        ("audio_format", args.audio_format),
    ])
    db.commit()

    if args.verify_audio:
        missing = []
        for (name, sub) in ([(r[12], "words") for r in db.execute(
                "SELECT * FROM word")] +
                [(r[4], "sentences") for r in db.execute(
                    "SELECT * FROM sentence") if r[4]]):
            base = APP_AUDIO / sub if args.audio_format == "m4a" else ROOT / "media"
            if not (base / name).exists():
                missing.append(name)
        if missing:
            print(f"FATAL: {len(missing)} audio files missing: {missing[:10]}")
            return 1

    db.execute("VACUUM")
    db.close()
    counts = {t: sqlite3.connect(DB_PATH).execute(
        f"SELECT count(*) FROM {t}").fetchone()[0]
        for t in ("word", "sentence", "word_sentence", "topic")}
    print(f"wrote {DB_PATH} ({DB_PATH.stat().st_size // 1024} KB): {counts}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
