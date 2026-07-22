"""Shared helpers for the german-anki data pipeline."""
import csv
import json
import re
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "data" / "raw"
PROCESSED = ROOT / "data" / "processed"
MEDIA = ROOT / "media"
DECKS = ROOT / "decks"

WORDS_CSV = PROCESSED / "words.csv"
SENTENCES_CSV = PROCESSED / "sentences.csv"
WORD_SENTENCE_CSV = PROCESSED / "word_sentence.csv"
TOPICS_JSON = PROCESSED / "topics.json"

WORD_FIELDS = [
    "word_id", "lemma", "display", "pos", "gender", "plural", "verb_forms",
    "level", "topic", "en", "ru", "freq_rank", "source", "audio", "status",
]
SENTENCE_FIELDS = [
    "sent_id", "de", "en", "ru", "level", "source", "audio", "tatoeba_audio_license",
]
WS_FIELDS = ["word_id", "sent_id", "is_primary"]

LEVELS = ["A1", "A2", "B1", "B2"]

_UMLAUT = {"ä": "ae", "ö": "oe", "ü": "ue", "ß": "ss", "Ä": "ae", "Ö": "oe", "Ü": "ue"}


def slugify(text: str) -> str:
    for k, v in _UMLAUT.items():
        text = text.replace(k, v)
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()
    text = re.sub(r"[^a-zA-Z0-9]+", "-", text.lower()).strip("-")
    return text or "x"


def read_csv(path: Path) -> list[dict]:
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def write_csv(path: Path, rows: list[dict], fields: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k, "") for k in fields})


def load_topics() -> dict:
    with open(TOPICS_JSON, encoding="utf-8") as f:
        return json.load(f)
