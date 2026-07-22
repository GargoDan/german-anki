"""Step 2: mine Tatoeba for candidate example sentences per word.

Downloads per-language exports (DE sentences, DE-EN / DE-RU links, EN/RU
sentences, DE audio index), indexes DE sentences by lemma, and selects up to
5 candidates per word: 4-14 tokens, must have an EN translation; prefers
candidates with a RU translation and/or human audio, and mid-length sentences.

Output: data/processed/candidates.jsonl  {word_id, candidates:[{tid, de, en, ru, audio_license}]}
"""
import bz2
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

import requests
import simplemma

sys.path.insert(0, str(Path(__file__).parent))
from lib import PROCESSED, RAW, WORDS_CSV, read_csv

BASE = "https://downloads.tatoeba.org/exports/per_language"
FILES = {
    "deu_sentences.tsv.bz2": f"{BASE}/deu/deu_sentences.tsv.bz2",
    "deu-eng_links.tsv.bz2": f"{BASE}/deu/deu-eng_links.tsv.bz2",
    "deu-rus_links.tsv.bz2": f"{BASE}/deu/deu-rus_links.tsv.bz2",
    "eng_sentences.tsv.bz2": f"{BASE}/eng/eng_sentences.tsv.bz2",
    "rus_sentences.tsv.bz2": f"{BASE}/rus/rus_sentences.tsv.bz2",
    "deu_sentences_with_audio.tsv.bz2": f"{BASE}/deu/deu_sentences_with_audio.tsv.bz2",
}

TOKEN_RE = re.compile(r"[A-Za-zÄÖÜäöüß]+")


def ensure_downloads():
    for name, url in FILES.items():
        p = RAW / name
        if p.exists() and p.stat().st_size > 1000:
            continue
        print(f"downloading {name} ...")
        r = requests.get(url, timeout=600)
        r.raise_for_status()
        p.write_bytes(r.content)


def read_tsv(name: str):
    with bz2.open(RAW / name, "rt", encoding="utf-8") as f:
        for line in f:
            yield line.rstrip("\n").split("\t")


def main():
    ensure_downloads()
    words = read_csv(WORDS_CSV)

    print("loading links / audio ...")
    de_to_en: dict[str, list[str]] = defaultdict(list)
    for row in read_tsv("deu-eng_links.tsv.bz2"):
        if len(row) >= 2:
            de_to_en[row[0]].append(row[1])
    de_to_ru: dict[str, list[str]] = defaultdict(list)
    for row in read_tsv("deu-rus_links.tsv.bz2"):
        if len(row) >= 2:
            de_to_ru[row[0]].append(row[1])
    audio_license: dict[str, str] = {}
    for row in read_tsv("deu_sentences_with_audio.tsv.bz2"):
        if len(row) >= 4 and row[0] not in audio_license:
            audio_license[row[0]] = row[3] or ""

    print("loading + indexing DE sentences ...")
    de_text: dict[str, str] = {}
    lemma_index: dict[str, list[str]] = defaultdict(list)
    for row in read_tsv("deu_sentences.tsv.bz2"):
        if len(row) < 3:
            continue
        sid, text = row[0], row[2]
        if sid not in de_to_en:
            continue
        tokens = TOKEN_RE.findall(text)
        if not (4 <= len(tokens) <= 14):
            continue
        de_text[sid] = text
        seen = set()
        for t in tokens:
            for lem in {simplemma.lemmatize(t, lang="de"), t}:
                if lem not in seen:
                    seen.add(lem)
                    lemma_index[lem].append(sid)
    print(f"  indexed {len(de_text)} usable DE sentences")

    print("loading needed EN/RU translations ...")
    needed_en = {e for sid in de_text for e in de_to_en.get(sid, [])}
    needed_ru = {r for sid in de_text for r in de_to_ru.get(sid, [])}
    en_text = {r[0]: r[2] for r in read_tsv("eng_sentences.tsv.bz2")
               if len(r) >= 3 and r[0] in needed_en}
    ru_text = {r[0]: r[2] for r in read_tsv("rus_sentences.tsv.bz2")
               if len(r) >= 3 and r[0] in needed_ru}

    def candidates_for(word: dict) -> list[dict]:
        lemma = word["lemma"]
        if word["pos"] == "phrase":
            # substring match on the fixed part of the phrase
            frag = lemma.lower()
            sids = [sid for sid, t in de_text.items() if frag in t.lower()] if len(frag) >= 8 else []
        else:
            sids = list(dict.fromkeys(
                lemma_index.get(lemma, []) + lemma_index.get(lemma.lower(), [])
                + lemma_index.get(lemma.capitalize(), [])))
        scored = []
        for sid in sids:
            ens = [en_text[e] for e in de_to_en.get(sid, []) if e in en_text]
            if not ens:
                continue
            rus = [ru_text[r] for r in de_to_ru.get(sid, []) if r in ru_text]
            n_tok = len(TOKEN_RE.findall(de_text[sid]))
            score = (2 if rus else 0) + (1 if sid in audio_license else 0) - abs(n_tok - 8) * 0.1
            scored.append((score, sid, ens[0], rus[0] if rus else ""))
        scored.sort(key=lambda x: -x[0])
        return [{"tid": sid, "de": de_text[sid], "en": en, "ru": ru,
                 "audio_license": audio_license.get(sid, "")}
                for _, sid, en, ru in scored[:5]]

    n_with = 0
    with open(PROCESSED / "candidates.jsonl", "w", encoding="utf-8") as out:
        for w in words:
            cands = candidates_for(w)
            if cands:
                n_with += 1
            out.write(json.dumps({"word_id": w["word_id"], "candidates": cands},
                                 ensure_ascii=False) + "\n")
    print(f"words with >=1 candidate: {n_with}/{len(words)}")


if __name__ == "__main__":
    main()
