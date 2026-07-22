"""Step 4: cross-check LLM translations against the Wiktionary lexicon (free, no LLM).

For every enriched word that exists in the lexicon, compare the LLM's EN/RU
translations with Wiktionary glosses/translations using loose token overlap.
Disagreements are marked status=qa_flagged (input to the QA batch, step 07)
and written to data/processed/crosscheck_report.csv for eyeballing.
"""
import csv
import gzip
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from lib import PROCESSED, WORD_FIELDS, WORDS_CSV, read_csv, write_csv

WORD_RE = re.compile(r"[a-zа-яё]+", re.IGNORECASE)

EN_STOP = {"to", "a", "an", "the", "of", "in", "on", "for", "be", "sth", "sb",
           "something", "somebody", "someone", "oneself", "one", "or", "and", "with"}


def tokens(text: str, stop=frozenset()) -> set[str]:
    return {t.lower() for t in WORD_RE.findall(text) if t.lower() not in stop and len(t) > 1}


def main():
    with gzip.open(PROCESSED / "lexicon.json.gz", "rt", encoding="utf-8") as f:
        lexicon = json.load(f)
    words = read_csv(WORDS_CSV)
    report = []
    n_checked = n_flagged = 0
    for w in words:
        if w["status"] != "enriched":
            continue
        entry = lexicon.get(w["lemma"]) or lexicon.get(w["lemma"].capitalize())
        if not entry:
            continue
        flags = []
        wikt_en = tokens(" ".join(entry["en"]), EN_STOP)
        if wikt_en and w["en"]:
            if not (tokens(w["en"], EN_STOP) & wikt_en):
                flags.append("en_mismatch")
        # RU: compare on 5-char stems to survive inflection differences
        wikt_ru = {t[:5] for t in tokens(" ".join(entry["ru"]))}
        ours_ru = {t[:5] for t in tokens(w["ru"])}
        if wikt_ru and ours_ru and not (ours_ru & wikt_ru):
            flags.append("ru_mismatch")
        n_checked += 1
        if flags:
            n_flagged += 1
            w["status"] = "qa_flagged"
            report.append({
                "word_id": w["word_id"], "display": w["display"], "flags": ";".join(flags),
                "our_en": w["en"], "wikt_en": " | ".join(entry["en"][:3]),
                "our_ru": w["ru"], "wikt_ru": " | ".join(entry["ru"][:3]),
            })

    write_csv(WORDS_CSV, words, WORD_FIELDS)
    rpath = PROCESSED / "crosscheck_report.csv"
    with open(rpath, "w", newline="", encoding="utf-8") as f:
        wr = csv.DictWriter(f, fieldnames=["word_id", "display", "flags", "our_en",
                                           "wikt_en", "our_ru", "wikt_ru"])
        wr.writeheader()
        wr.writerows(report)
    print(f"checked {n_checked} words against lexicon; flagged {n_flagged} -> {rpath}")


if __name__ == "__main__":
    main()
