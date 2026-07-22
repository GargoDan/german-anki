"""Step 0: condense the two kaikki Wiktionary extracts into one compact lexicon.

Inputs (downloaded by 01_ingest / manually):
  data/raw/kaikki_en_de.jsonl.gz      -- German words described in English Wiktionary
  data/raw/kaikki_dewikt_de.jsonl.gz  -- German words from German Wiktionary (has RU/EN translations)

Output: data/processed/lexicon.json.gz
  { word: {"pos": [...], "lemma_pos": [...], "en": [...], "ru": [...], "article": "" } }

Used for (a) gating frequency-list candidates to real dictionary lemmas,
(b) cross-checking LLM translations in step 04.
"""
import gzip
import json
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from lib import PROCESSED, RAW

LEXICON = PROCESSED / "lexicon.json.gz"

REAL_POS = {"noun", "verb", "adj", "adv", "prep", "conj", "pron", "num",
            "particle", "intj", "det", "article", "phrase", "prep_phrase"}


def main():
    lex: dict = defaultdict(lambda: {"pos": set(), "lemma_pos": set(), "en": [], "ru": [], "article": ""})

    with gzip.open(RAW / "kaikki_en_de.jsonl.gz", "rt", encoding="utf-8") as f:
        for line in f:
            e = json.loads(line)
            word, pos = e.get("word", ""), e.get("pos", "")
            if not word:
                continue
            entry = lex[word]
            entry["pos"].add(pos)
            senses = e.get("senses", [])
            is_lemma = not any("form-of" in s.get("tags", []) or "alt-of" in s.get("tags", [])
                               for s in senses[:1])
            if pos in REAL_POS and is_lemma:
                entry["lemma_pos"].add(pos)
                for s in senses:
                    if "form-of" in s.get("tags", []):
                        continue
                    for g in s.get("glosses", [])[:1]:
                        if g not in entry["en"] and len(entry["en"]) < 4:
                            entry["en"].append(g)

    with gzip.open(RAW / "kaikki_dewikt_de.jsonl.gz", "rt", encoding="utf-8") as f:
        for line in f:
            e = json.loads(line)
            word, pos = e.get("word", ""), e.get("pos", "")
            if not word or "form-of" in e.get("tags", []):
                continue
            entry = lex[word]
            entry["pos"].add(pos)
            if pos in REAL_POS:
                entry["lemma_pos"].add(pos)
            for t in e.get("translations", []):
                w = t.get("word")
                if not w:
                    continue
                if t.get("lang_code") == "ru" and w not in entry["ru"] and len(entry["ru"]) < 5:
                    entry["ru"].append(w)
                elif t.get("lang_code") == "en" and w not in entry["en"] and len(entry["en"]) < 6:
                    entry["en"].append(w)
            if not entry["article"]:
                for fo in e.get("forms", []):
                    if fo.get("article") and "nominative" in fo.get("tags", []) and "singular" in fo.get("tags", []):
                        entry["article"] = fo["article"]
                        break

    out = {w: {"pos": sorted(v["pos"]), "lemma_pos": sorted(v["lemma_pos"]),
               "en": v["en"], "ru": v["ru"], "article": v["article"]}
           for w, v in lex.items()}
    PROCESSED.mkdir(parents=True, exist_ok=True)
    with gzip.open(LEXICON, "wt", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False)
    n_ru = sum(1 for v in out.values() if v["ru"])
    print(f"lexicon entries: {len(out)}, with RU translations: {n_ru}")


if __name__ == "__main__":
    main()
