"""Step 1: build the raw word inventory (~4,000 entries).

Sources:
  - DWDS machine-readable Goethe lists (A1/A2/B1) -> data/raw/goethe_{level}.csv
  - docs/German_B2_Unofficial_Vocabulary_List.docx (via textutil dump) -> B2 words with topic+EN
  - hermitdave FrequencyWords de_50k -> frequency-ranked B2 gap fill

Output: data/processed/words.csv (status=raw)
"""
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

import requests
import simplemma

sys.path.insert(0, str(Path(__file__).parent))
from lib import PROCESSED, RAW, ROOT, WORD_FIELDS, WORDS_CSV, read_csv, slugify, write_csv

TARGET_TOTAL = 4900

POS_MAP = {
    "Substantiv": "noun", "Verb": "verb", "Adjektiv": "adj", "Adverb": "adv",
    "Präposition": "prep", "Konjunktion": "conj", "Pronomen": "pron",
    "Numerale": "num", "Partikel": "particle", "Interjektion": "interj",
    "Artikel": "article", "Mehrwortausdruck": "phrase",
}

DOCX_TOPIC = {
    1: "gesellschaft-politik", 2: "arbeit-beruf", 3: "bildung-lernen",
    4: "umwelt-nachhaltigkeit", 5: "gesundheit-ernaehrung", 6: "medien-technologie",
    7: "wirtschaft-konsum", 8: "reisen-mobilitaet", 9: "gefuehle-beziehungen",
    10: "redemittel",
}

SKIP_LINES = {"Nouns", "Verbs", "Adjectives & other useful words", "Adjectives",
              "German", "English", "Adjectives & useful words"}


def ensure_downloads():
    RAW.mkdir(parents=True, exist_ok=True)
    for level in ("A1", "A2", "B1"):
        p = RAW / f"goethe_{level}.csv"
        if not p.exists() or p.stat().st_size < 1000:
            r = requests.get(f"https://www.dwds.de/api/lemma/goethe/{level}.csv", timeout=60)
            r.raise_for_status()
            p.write_bytes(r.content)
    freq = RAW / "de_50k.txt"
    if not freq.exists() or freq.stat().st_size < 10000:
        url = "https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/de/de_50k.txt"
        r = requests.get(url, timeout=120)
        r.raise_for_status()
        freq.write_bytes(r.content)
    docx_txt = RAW / "b2_docx.txt"
    if not docx_txt.exists():
        out = subprocess.check_output(
            ["textutil", "-stdout", "-convert", "txt",
             str(ROOT / "docs" / "German_B2_Unofficial_Vocabulary_List.docx")])
        docx_txt.write_bytes(out)


def load_dwds() -> list[dict]:
    rows, seen = [], {}
    for level in ("A1", "A2", "B1"):
        for r in read_csv(RAW / f"goethe_{level}.csv"):
            lemma = r["Lemma"].strip()
            if not re.search(r"[A-Za-zÄÖÜäöüß]", lemma):
                continue
            pos = POS_MAP.get(r["Wortart"], "other")
            if r["Wortart"] == "Symbol":
                continue
            key = (lemma.lower(), pos)
            if key in seen:
                continue
            seen[key] = True
            article = r["Artikel"].split(",")[0].strip()
            display = f"{article} {lemma}" if pos == "noun" and article else lemma
            if r.get("nur_im_Plural") == "1":
                display = f"die {lemma} (Pl.)"
            rows.append({
                "lemma": lemma, "display": display, "pos": pos,
                "gender": r["Genus"].split(",")[0].strip(),
                "plural": "", "verb_forms": "", "level": level,
                "topic": "", "en": "", "ru": "", "freq_rank": "",
                "source": "dwds", "status": "raw",
            })
    return rows


def parse_docx() -> list[dict]:
    lines = [l.strip() for l in (RAW / "b2_docx.txt").read_text(encoding="utf-8").splitlines()]
    entries, topic_num = [], None
    pending_de = None
    for line in lines:
        m = re.match(r"^(\d+)\. ", line)
        if m:
            topic_num = int(m.group(1))
            pending_de = None
            continue
        if topic_num is None or not line or line in SKIP_LINES or line.startswith("Tip:"):
            pending_de = None if (not line or line in SKIP_LINES) else pending_de
            if line.startswith("Tip:"):
                break
            continue
        if pending_de is None:
            pending_de = line
        else:
            entries.append((topic_num, pending_de, line))
            pending_de = None

    rows = []
    for topic_num, de, en in entries:
        topic = DOCX_TOPIC[topic_num]
        display, gender, plural, verb_forms, pos = de, "", "", "", ""
        lemma = de
        noun_m = re.match(r"^(der|die|das)\s+([A-ZÄÖÜa-zäöüß\-]+)(?:,\s*(.+))?$", de)
        verb_m = re.match(r"^(sich\s+)?([a-zäöüß]+(?:\s+[a-zäöüß]+)?)\s*\((.+)\)$", de)
        if topic_num == 10:
            pos, lemma = "phrase", de.replace("…", "").strip(" .")
        elif noun_m:
            pos = "noun"
            gender = {"der": "mask.", "die": "fem.", "das": "neutr."}[noun_m.group(1)]
            lemma = noun_m.group(2)
            plural = (noun_m.group(3) or "").strip()
        elif verb_m and "," in verb_m.group(3):
            pos = "verb"
            lemma = ((verb_m.group(1) or "") + verb_m.group(2)).strip()
            verb_forms = verb_m.group(3)
        elif " " not in de or "/" in de:
            pos = "adj"
            lemma = re.split(r"\s*/\s*", de)[0].strip()
        else:
            pos = "phrase"
            lemma = de.replace("…", "").strip(" .")
        rows.append({
            "lemma": lemma, "display": display, "pos": pos, "gender": gender,
            "plural": plural, "verb_forms": verb_forms, "level": "B2",
            "topic": topic, "en": en, "ru": "", "freq_rank": "",
            "source": "docx", "status": "raw",
        })
    return rows


CONTENT_POS = {"noun", "verb", "adj", "adv"}
ARTICLE_GENDER = {"der": "mask.", "die": "fem.", "das": "neutr."}


def load_lexicon() -> dict:
    import gzip
    import json
    with gzip.open(PROCESSED / "lexicon.json.gz", "rt", encoding="utf-8") as f:
        return json.load(f)


def freq_fill(existing_lemmas: set[str], n_needed: int) -> list[dict]:
    """Frequency-ranked B2 gap fill, gated against the Wiktionary lexicon.

    The OpenSubtitles corpus is lowercased, so noun capitalization/gender is
    recovered from the lexicon. Forms whose capitalized reading lemmatizes to
    an already-covered word (e.g. "tagen" -> Tagen -> Tag) are skipped to avoid
    homograph mislemmatization.
    """
    lexicon = load_lexicon()
    counts: Counter = Counter()
    for line in (RAW / "de_50k.txt").read_text(encoding="utf-8").splitlines():
        parts = line.split()
        if len(parts) != 2:
            continue
        form, cnt = parts[0], int(parts[1])
        if not re.fullmatch(r"[a-zäöüß]{3,}", form):
            continue
        cap_lemma = simplemma.lemmatize(form.capitalize(), lang="de")
        if cap_lemma.lower() in existing_lemmas and cap_lemma[0].isupper():
            continue  # dative-plural homograph of a covered noun
        lemma = simplemma.lemmatize(form, lang="de")
        counts[lemma] += cnt

    rows, rank = [], 0
    for lemma, cnt in counts.most_common():
        rank += 1
        if len(rows) >= n_needed:
            break
        if len(lemma) < 3 or not re.fullmatch(r"[A-Za-zÄÖÜäöüß\-]+", lemma):
            continue
        # resolve against lexicon; prefer lowercase (verb/adj/adv), else noun
        chosen, entry = None, None
        for variant in (lemma, lemma.capitalize()):
            e = lexicon.get(variant)
            if e and set(e["lemma_pos"]) & CONTENT_POS:
                chosen, entry = variant, e
                break
        if not chosen or chosen.lower() in existing_lemmas:
            continue
        if set(entry["pos"]) == {"name"}:
            continue
        # first names / places: dewiktionary lists them as nouns but the EN
        # edition knows them only as names -> no English gloss collected
        if "name" in entry["pos"] and not entry["en"]:
            continue
        # candidate must itself be a lemma (drops participles like "gefunden")
        if simplemma.lemmatize(chosen, lang="de") != chosen:
            continue
        pos_set = set(entry["lemma_pos"]) & CONTENT_POS
        if chosen[0].isupper():
            pos = "noun"
        else:
            pos = next((p for p in ("verb", "adj", "adv") if p in pos_set), sorted(pos_set)[0])
        article = entry.get("article", "")
        display = f"{article} {chosen}" if pos == "noun" and article else chosen
        rows.append({
            "lemma": chosen, "display": display, "pos": pos,
            "gender": ARTICLE_GENDER.get(article, ""),
            "plural": "", "verb_forms": "", "level": "B2", "topic": "",
            "en": "", "ru": "", "freq_rank": str(rank), "source": "freq",
            "status": "raw",
        })
        existing_lemmas.add(chosen.lower())
    return rows


def main():
    ensure_downloads()
    dwds = load_dwds()
    docx = parse_docx()

    by_lemma = {r["lemma"].lower(): r for r in dwds}
    merged = list(dwds)
    docx_added = 0
    for r in docx:
        hit = by_lemma.get(r["lemma"].lower())
        if hit:
            # word already covered at a lower level: keep level, adopt docx EN/topic hints
            if not hit["en"]:
                hit["en"] = r["en"]
            if not hit["topic"]:
                hit["topic"] = r["topic"]
        else:
            merged.append(r)
            by_lemma[r["lemma"].lower()] = r
            docx_added += 1

    # over-provision: the LLM enrichment pass rejects residual junk
    # (mislemmatized homographs, subtitle-corpus noise), so aim ~25% above
    # target and trim after enrichment.
    n_needed = max(0, int((TARGET_TOTAL - len(merged)) * 1.25))
    freq_rows = freq_fill(set(by_lemma.keys()), n_needed)
    merged.extend(freq_rows)

    seen_ids = set()
    for r in merged:
        base = f"{slugify(r['lemma'])}-{(r['pos'] or 'x')[0]}"
        wid, i = base, 1
        while wid in seen_ids:
            i += 1
            wid = f"{base}-{i}"
        seen_ids.add(wid)
        r["word_id"] = wid
        r["audio"] = f"word_{wid}.mp3"

    write_csv(WORDS_CSV, merged, WORD_FIELDS)
    from collections import Counter as C
    print(f"total: {len(merged)}")
    print("by level:", dict(C(r['level'] for r in merged)))
    print("by source:", dict(C(r['source'] for r in merged)))
    print(f"docx new entries: {docx_added}, docx merged into existing: {len(docx) - docx_added}")
    print(f"freq gap-fill: {len(freq_rows)}")


if __name__ == "__main__":
    main()
