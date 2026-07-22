"""Step 3: LLM enrichment via the OpenAI Batch API (model: gpt-5.6-luna).

Per word the model returns: EN + RU translations, topic slug (from the level's
taxonomy), verified/filled grammar (pos, gender, plural, verb forms), and an
example sentence: either the best Tatoeba candidate (id + RU translation if
missing) or a newly written level-appropriate sentence with EN + RU. Junk
frequency-mined entries (proper names, inflected forms, corpus artifacts) are
rejected.

Usage:
  python 03_enrich_batch.py submit          # build + upload + create batch
  python 03_enrich_batch.py poll            # check status, download when done
  python 03_enrich_batch.py merge           # apply results to words/sentences csv
  python 03_enrich_batch.py run             # submit + poll until done + merge

Requires OPENAI_API_KEY.
"""
import json
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from lib import (PROCESSED, SENTENCE_FIELDS, SENTENCES_CSV, WORD_FIELDS,
                 WORD_SENTENCE_CSV, WORDS_CSV, WS_FIELDS, load_topics,
                 read_csv, slugify, write_csv)

MODEL = "gpt-5.6-luna"
CHUNK = 15
STATE = PROCESSED / "batch_state.json"
BATCH_IN = PROCESSED / "batch_input.jsonl"
BATCH_OUT = PROCESSED / "batch_output.jsonl"

GRAMMAR_CAP = {
    "A1": "present tense, Nom/Akk, modal & separable verbs, simple main clauses and W-questions",
    "A2": "adds Dativ, Perfekt, subordinate clauses (weil/dass/wenn), comparatives, reflexive verbs",
    "B1": "adds Konjunktiv II, passive, relative clauses, Genitiv, Präteritum, infinitive constructions",
    "B2": "adds Konjunktiv I, advanced passive, participial attributes, nominal style, complex connectors",
}

SYSTEM = """You are an expert German lexicographer building a high-quality Goethe-exam-aligned \
vocabulary dataset (levels A1-B2) for learners whose languages are English and Russian.

For EVERY word in the input you must return one JSON object with:
- "word_id": copied verbatim.
- "action": "keep" or "reject". Reject only clear junk: proper names (people/places/brands), \
inflected non-lemma forms (participles like "gefunden", plural-only corpus artifacts), \
corpus noise, or purely vulgar words with no value for exam preparation. Colloquial but \
useful words are kept. Words from source "dwds" or "docx" are NEVER rejected. \
If rejected, add "reject_reason" and skip all other fields.
- "en": concise English translation(s); 1-2 senses, comma-separated, max ~5 words per sense. \
If an English gloss is already provided in the input, keep its sense (refine wording only).
- "ru": concise Russian translation(s), same format, natural modern Russian.
- "pos": one of noun|verb|adj|adv|prep|conj|pron|num|particle|interj|phrase|other (fix if input is wrong/empty).
- "gender": for nouns: mask.|fem.|neutr. ("" otherwise).
- "plural": for nouns the full plural form (e.g. "Häuser", or "-" if unchanged, "(Sg.)" if no plural); "" otherwise.
- "verb_forms": for irregular/notable verbs: "3rd sg present, Präteritum, Perfekt" \
(e.g. "spricht, sprach, hat gesprochen"); "" for regular weak verbs and non-verbs.
- "topic": exactly one topic slug from the topic list given for the word's level. Choose the \
topic where this word is most likely to appear in Goethe exam materials. If a topic is already \
set in the input, keep it unless clearly wrong.
- "sentence": the example sentence, as ONE of:
    {"tatoeba_id": "<tid>", "ru": "<Russian translation>"} - pick the BEST candidate: it must \
illustrate the word's core meaning naturally, and its vocabulary/grammar must be appropriate \
at or below the word's CEFR level. Copy the ru field from the candidate if it has one, else \
translate the German sentence to Russian yourself.
    {"de": "...", "en": "...", "ru": "..."} - write a NEW sentence only if no candidate is \
suitable. Constraints: 6-12 words, natural everyday German, vocabulary and grammar within \
the word's CEFR level (grammar ceiling is given), the target word used in a typical collocation. \
Translate it to English and Russian.

Return strict JSON: {"words": [ ... one object per input word ... ]}. No markdown, no commentary."""


def build_requests() -> list[dict]:
    words = [w for w in read_csv(WORDS_CSV) if w["status"] == "raw"]
    cands = {}
    cpath = PROCESSED / "candidates.jsonl"
    if cpath.exists():
        for line in open(cpath, encoding="utf-8"):
            o = json.loads(line)
            cands[o["word_id"]] = o["candidates"]
    topics = load_topics()

    requests_out = []
    for i in range(0, len(words), CHUNK):
        chunk = words[i:i + CHUNK]
        levels = sorted({w["level"] for w in chunk})
        topic_block = {lv: [t["slug"] + " (" + t["en"] + ")" for t in topics[lv]] for lv in levels}
        grammar_block = {lv: GRAMMAR_CAP[lv] for lv in levels}
        items = []
        for w in chunk:
            item = {k: w[k] for k in ("word_id", "display", "lemma", "pos", "gender",
                                      "plural", "verb_forms", "level", "topic", "en", "source")
                    if w.get(k)}
            item["word_id"] = w["word_id"]
            item["candidates"] = [
                {"tid": c["tid"], "de": c["de"], "en": c["en"], **({"ru": c["ru"]} if c["ru"] else {})}
                for c in cands.get(w["word_id"], [])
            ]
            items.append(item)
        user = (f"Topic slugs per level:\n{json.dumps(topic_block, ensure_ascii=False)}\n\n"
                f"Grammar ceiling per level:\n{json.dumps(grammar_block, ensure_ascii=False)}\n\n"
                f"Words:\n{json.dumps(items, ensure_ascii=False)}")
        requests_out.append({
            "custom_id": f"chunk-{i // CHUNK:04d}",
            "method": "POST",
            "url": "/v1/chat/completions",
            "body": {
                "model": MODEL,
                "response_format": {"type": "json_object"},
                "messages": [
                    {"role": "system", "content": SYSTEM},
                    {"role": "user", "content": user},
                ],
            },
        })
    return requests_out


def get_client():
    from openai import OpenAI
    if not os.environ.get("OPENAI_API_KEY"):
        sys.exit("OPENAI_API_KEY is not set. Export it and re-run.")
    return OpenAI()


def submit():
    reqs = build_requests()
    with open(BATCH_IN, "w", encoding="utf-8") as f:
        for r in reqs:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    print(f"built {len(reqs)} batch requests -> {BATCH_IN}")
    client = get_client()
    up = client.files.create(file=open(BATCH_IN, "rb"), purpose="batch")
    batch = client.batches.create(input_file_id=up.id, endpoint="/v1/chat/completions",
                                  completion_window="24h")
    STATE.write_text(json.dumps({"batch_id": batch.id, "stage": "enrich"}))
    print(f"submitted batch {batch.id} (status {batch.status})")


def poll(wait: bool = False) -> bool:
    client = get_client()
    bid = json.loads(STATE.read_text())["batch_id"]
    while True:
        b = client.batches.retrieve(bid)
        counts = getattr(b, "request_counts", None)
        print(f"status={b.status} counts={counts}")
        if b.status == "completed":
            content = client.files.content(b.output_file_id).content
            BATCH_OUT.write_bytes(content)
            if getattr(b, "error_file_id", None):
                err = client.files.content(b.error_file_id).content
                (PROCESSED / "batch_errors.jsonl").write_bytes(err)
                print("NOTE: some requests errored, see batch_errors.jsonl")
            print(f"downloaded -> {BATCH_OUT}")
            if getattr(b, "usage", None):
                print("usage:", b.usage)
            return True
        if b.status in ("failed", "expired", "cancelled"):
            sys.exit(f"batch ended with status {b.status}: {getattr(b, 'errors', '')}")
        if not wait:
            return False
        time.sleep(60)


def merge():
    words = read_csv(WORDS_CSV)
    by_id = {w["word_id"]: w for w in words}
    cands = {}
    cpath = PROCESSED / "candidates.jsonl"
    if cpath.exists():
        for line in open(cpath, encoding="utf-8"):
            o = json.loads(line)
            cands[o["word_id"]] = {c["tid"]: c for c in o["candidates"]}

    results = []
    for line in open(BATCH_OUT, encoding="utf-8"):
        o = json.loads(line)
        body = o.get("response", {}).get("body", {})
        if o.get("error") or body.get("error"):
            print(f"request {o.get('custom_id')} errored: {o.get('error') or body.get('error')}")
            continue
        content = body["choices"][0]["message"]["content"]
        try:
            results.extend(json.loads(content)["words"])
        except (json.JSONDecodeError, KeyError, TypeError) as e:
            print(f"unparseable result in {o.get('custom_id')}: {e}")

    sentences, links = [], []
    seen_sent = set()
    n_keep = n_reject = n_tatoeba = n_llm = 0
    for r in results:
        w = by_id.get(r.get("word_id"))
        if not w:
            continue
        if r.get("action") == "reject" and w["source"] == "freq":
            w["status"] = "rejected"
            n_reject += 1
            continue
        n_keep += 1
        for field in ("en", "ru", "pos", "gender", "plural", "verb_forms", "topic"):
            if r.get(field):
                w[field] = str(r[field]).strip()
        if w["pos"] == "noun" and w["gender"] and not w["display"].startswith(("der ", "die ", "das ")):
            art = {"mask.": "der", "fem.": "die", "neutr.": "das"}.get(w["gender"])
            if art:
                w["display"] = f"{art} {w['lemma']}"
        w["status"] = "enriched"

        s = r.get("sentence") or {}
        if s.get("tatoeba_id"):
            tid = str(s["tatoeba_id"])
            c = cands.get(w["word_id"], {}).get(tid)
            if not c:
                continue
            sent_id = f"t{tid}"
            n_tatoeba += 1
            if sent_id not in seen_sent:
                seen_sent.add(sent_id)
                sentences.append({
                    "sent_id": sent_id, "de": c["de"], "en": c["en"],
                    "ru": c.get("ru") or s.get("ru", ""), "level": w["level"],
                    "source": f"tatoeba:{tid}", "audio": f"sent_{sent_id}.mp3",
                    "tatoeba_audio_license": c.get("audio_license", ""),
                })
            links.append({"word_id": w["word_id"], "sent_id": sent_id, "is_primary": "1"})
        elif s.get("de"):
            sent_id = f"g-{w['word_id']}"
            n_llm += 1
            if sent_id not in seen_sent:
                seen_sent.add(sent_id)
                sentences.append({
                    "sent_id": sent_id, "de": s["de"], "en": s.get("en", ""),
                    "ru": s.get("ru", ""), "level": w["level"], "source": "llm",
                    "audio": f"sent_{sent_id}.mp3", "tatoeba_audio_license": "",
                })
            links.append({"word_id": w["word_id"], "sent_id": sent_id, "is_primary": "1"})

    kept_words = [w for w in words if w["status"] != "rejected"]
    write_csv(WORDS_CSV, kept_words, WORD_FIELDS)
    write_csv(SENTENCES_CSV, sentences, SENTENCE_FIELDS)
    write_csv(WORD_SENTENCE_CSV, links, WS_FIELDS)
    missing = [w["word_id"] for w in kept_words if w["status"] != "enriched"]
    no_sentence = {w["word_id"] for w in kept_words} - {l["word_id"] for l in links}
    print(f"kept {n_keep}, rejected {n_reject}; sentences: {n_tatoeba} tatoeba / {n_llm} llm")
    print(f"words remaining: {len(kept_words)}; not enriched: {len(missing)}; without sentence: {len(no_sentence)}")
    if missing[:10]:
        print("  e.g. not enriched:", missing[:10])


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
