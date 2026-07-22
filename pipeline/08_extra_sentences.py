"""Step 8: add 2 extra example sentences per word (OpenAI batch, vetted selection).

For every word the model sees its translations, level, current primary sentence
and up to 4 unused Tatoeba candidates. It picks the best 2 complementary
candidates (translating missing RU itself), and writes level-appropriate
replacements only when fewer than 2 candidates qualify.

Merge is append-only: new rows are added to sentences.csv and word_sentence.csv
(is_primary=0); existing rows are never rewritten. After merging, re-run
05_audio.py (new clips) and 06_build_decks.py (extras render on word cards).

Usage: python 08_extra_sentences.py [submit|poll|merge|run]   (default: run)
"""
import json
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from lib import (PROCESSED, SENTENCE_FIELDS, SENTENCES_CSV, WORD_SENTENCE_CSV,
                 WORDS_CSV, WS_FIELDS, read_csv, write_csv)

MODEL = "gpt-5.6-luna"
CHUNK = 20
EXTRAS_PER_WORD = 2
STATE = PROCESSED / "extra_state.json"
EXTRA_IN = PROCESSED / "extra_input.jsonl"
EXTRA_OUT = PROCESSED / "extra_output.jsonl"

GRAMMAR_CAP = {
    "A1": "present tense, Nom/Akk, modal & separable verbs, simple main clauses and W-questions",
    "A2": "adds Dativ, Perfekt, subordinate clauses (weil/dass/wenn), comparatives, reflexive verbs",
    "B1": "adds Konjunktiv II, passive, relative clauses, Genitiv, Präteritum, infinitive constructions",
    "B2": "adds Konjunktiv I, advanced passive, participial attributes, nominal style, complex connectors",
}

SYSTEM = """You are curating example sentences for a German A1-B2 vocabulary dataset for \
learners whose languages are English and Russian. Each input word has: display form, pos, \
level, EN/RU translations, its existing primary example sentence, and up to 4 candidate \
sentences from the Tatoeba corpus ("de" + "en"; "ru" sometimes missing).

Allowed grammar per level (cumulative):
{caps}

For each word select exactly {n} ADDITIONAL example sentences:
1. Prefer Tatoeba candidates. A candidate qualifies if it clearly uses the word in one of \
its listed senses, is natural, is at most 16 words long, and its grammar and vocabulary do \
not exceed the word's CEFR level.
2. Prefer variety: sentences showing a different context, collocation, or sense than the \
primary sentence and than each other.
3. If a chosen candidate lacks "ru", translate its "de" into natural modern Russian \
yourself, faithful to the German and consistent with the "en".
4. Only if fewer than {n} candidates qualify, write replacements yourself: 6-12 words, \
strictly within the word's level per the table above, everyday context, with "en" and "ru".

Return strict JSON {{"items": [{{"word_id": "...", "sentences": [s1, s2]}}, ...]}} where each s is
  {{"tatoeba_id": "<tid>"}} or {{"tatoeba_id": "<tid>", "ru": "..."}}   (chosen candidate; "ru" only if it was missing)
or
  {{"de": "...", "en": "...", "ru": "..."}}                             (written replacement)
Exactly {n} sentences per word. No markdown, no commentary."""


def get_client():
    from openai import OpenAI
    if not os.environ.get("OPENAI_API_KEY"):
        sys.exit("OPENAI_API_KEY is not set. Export it and re-run.")
    return OpenAI()


def load_state() -> tuple[list[dict], dict, dict, dict]:
    words = [w for w in read_csv(WORDS_CSV)
             if w["status"] in ("enriched", "qa_flagged", "qa_ok")]
    sentences = {s["sent_id"]: s for s in read_csv(SENTENCES_CSV)}
    primary, extra_count = {}, {}
    for l in read_csv(WORD_SENTENCE_CSV):
        if l["is_primary"] == "1":
            primary.setdefault(l["word_id"], l["sent_id"])
        else:
            extra_count[l["word_id"]] = extra_count.get(l["word_id"], 0) + 1
    return words, sentences, primary, extra_count


def load_candidates() -> dict:
    cands = {}
    for line in open(PROCESSED / "candidates.jsonl", encoding="utf-8"):
        o = json.loads(line)
        cands[o["word_id"]] = {str(c["tid"]): c for c in o["candidates"]}
    return cands


def build_requests() -> list[dict]:
    words, sentences, primary, extra_count = load_state()
    cands = load_candidates()
    # skip words that already have enough extras (makes re-runs safe)
    todo = [w for w in words if extra_count.get(w["word_id"], 0) < EXTRAS_PER_WORD]

    system = SYSTEM.format(
        caps="\n".join(f"- {l}: {c}" for l, c in GRAMMAR_CAP.items()),
        n=EXTRAS_PER_WORD)
    reqs = []
    for i in range(0, len(todo), CHUNK):
        items = []
        for w in todo[i:i + CHUNK]:
            prim = sentences.get(primary.get(w["word_id"], ""), {})
            unused = [c for tid, c in cands.get(w["word_id"], {}).items()
                      if f"t{tid}" != primary.get(w["word_id"])][:4]
            items.append({
                "word_id": w["word_id"], "word": w["display"], "pos": w["pos"],
                "level": w["level"], "en": w["en"], "ru": w["ru"],
                "primary_sentence": prim.get("de", ""),
                "candidates": [{"tatoeba_id": str(c["tid"]), "de": c["de"],
                                "en": c["en"], **({"ru": c["ru"]} if c.get("ru") else {})}
                               for c in unused],
            })
        reqs.append({
            "custom_id": f"extra-{i // CHUNK:04d}",
            "method": "POST",
            "url": "/v1/chat/completions",
            "body": {
                "model": MODEL,
                "response_format": {"type": "json_object"},
                "messages": [{"role": "system", "content": system},
                             {"role": "user", "content": json.dumps(items, ensure_ascii=False)}],
            },
        })
    return reqs


def submit():
    reqs = build_requests()
    if not reqs:
        sys.exit("nothing to do: all words already have enough extra sentences")
    with open(EXTRA_IN, "w", encoding="utf-8") as f:
        for r in reqs:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    client = get_client()
    up = client.files.create(file=open(EXTRA_IN, "rb"), purpose="batch")
    batch = client.batches.create(input_file_id=up.id, endpoint="/v1/chat/completions",
                                  completion_window="24h")
    STATE.write_text(json.dumps({"batch_id": batch.id, "stage": "extra"}))
    print(f"submitted extra-sentences batch {batch.id} ({len(reqs)} requests)")


def poll(wait: bool = False) -> bool:
    client = get_client()
    bid = json.loads(STATE.read_text())["batch_id"]
    while True:
        b = client.batches.retrieve(bid)
        print(f"status={b.status} counts={getattr(b, 'request_counts', None)}")
        if b.status == "completed":
            EXTRA_OUT.write_bytes(client.files.content(b.output_file_id).content)
            print(f"downloaded -> {EXTRA_OUT}")
            if getattr(b, "usage", None):
                print("usage:", b.usage)
            return True
        if b.status in ("failed", "expired", "cancelled"):
            sys.exit(f"batch ended with status {b.status}")
        if not wait:
            return False
        time.sleep(60)


def merge():
    words, sentences, primary, extra_count = load_state()
    by_id = {w["word_id"]: w for w in words}
    cands = load_candidates()
    links = read_csv(WORD_SENTENCE_CSV)
    existing_links = {(l["word_id"], l["sent_id"]) for l in links}

    results = []
    for line in open(EXTRA_OUT, encoding="utf-8"):
        o = json.loads(line)
        body = o.get("response", {}).get("body", {})
        if o.get("error") or body.get("error"):
            print(f"request {o.get('custom_id')} errored")
            continue
        try:
            results.extend(json.loads(body["choices"][0]["message"]["content"])["items"])
        except (json.JSONDecodeError, KeyError, TypeError) as e:
            print(f"unparseable {o.get('custom_id')}: {e}")

    new_sents, new_links = [], []
    n_tatoeba = n_llm = n_bad = 0
    for r in results:
        w = by_id.get(r.get("word_id"))
        if not w:
            continue
        room = EXTRAS_PER_WORD - extra_count.get(w["word_id"], 0)
        gen_i = 0
        for s in (r.get("sentences") or [])[:max(room, 0)]:
            if s.get("tatoeba_id"):
                tid = str(s["tatoeba_id"])
                c = cands.get(w["word_id"], {}).get(tid)
                if not c:
                    n_bad += 1
                    continue
                sent_id = f"t{tid}"
                if sent_id not in sentences:
                    sentences[sent_id] = True
                    new_sents.append({
                        "sent_id": sent_id, "de": c["de"], "en": c["en"],
                        "ru": c.get("ru") or s.get("ru", ""), "level": w["level"],
                        "source": f"tatoeba:{tid}", "audio": f"sent_{sent_id}.mp3",
                        "tatoeba_audio_license": c.get("audio_license", ""),
                    })
                n_tatoeba += 1
            elif s.get("de"):
                gen_i += 1
                sent_id = f"x{gen_i}-{w['word_id']}"
                if sent_id not in sentences:
                    sentences[sent_id] = True
                    new_sents.append({
                        "sent_id": sent_id, "de": s["de"], "en": s.get("en", ""),
                        "ru": s.get("ru", ""), "level": w["level"], "source": "llm-extra",
                        "audio": f"sent_{sent_id}.mp3", "tatoeba_audio_license": "",
                    })
                n_llm += 1
            else:
                n_bad += 1
                continue
            if (w["word_id"], sent_id) not in existing_links:
                existing_links.add((w["word_id"], sent_id))
                new_links.append({"word_id": w["word_id"], "sent_id": sent_id,
                                  "is_primary": "0"})

    # append-only: never rewrite existing rows
    all_sents = read_csv(SENTENCES_CSV) + new_sents
    all_links = links + new_links
    write_csv(SENTENCES_CSV, all_sents, SENTENCE_FIELDS)
    write_csv(WORD_SENTENCE_CSV, all_links, WS_FIELDS)

    n_extras = {}
    for l in all_links:
        if l["is_primary"] == "0":
            n_extras[l["word_id"]] = n_extras.get(l["word_id"], 0) + 1
    short = [wid for wid in by_id if n_extras.get(wid, 0) < EXTRAS_PER_WORD]
    print(f"merged: +{len(new_sents)} sentences, +{len(new_links)} links "
          f"({n_tatoeba} tatoeba / {n_llm} llm picks, {n_bad} invalid refs)")
    print(f"words still short of {EXTRAS_PER_WORD} extras: {len(short)}"
          + (f"  e.g. {short[:8]}" if short else ""))
    print("next: re-run 05_audio.py and 06_build_decks.py")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "run"
    if cmd == "submit":
        submit()
    elif cmd == "poll":
        poll(wait="--wait" in sys.argv)
    elif cmd == "merge":
        merge()
    elif cmd == "run":
        submit()
        poll(wait=True)
        merge()
    else:
        sys.exit(f"unknown command {cmd}")
