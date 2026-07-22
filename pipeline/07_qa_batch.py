"""Step 7: QA pass (run after v1 is in use) - second OpenAI batch.

Every word+sentence pair is scored; weak items are fixed in place:
- translation errors (incl. crosscheck-flagged words from step 04, whose
  Wiktionary hints are included in the prompt)
- sentences that don't illustrate the word or exceed the word's CEFR level
- unbalanced sentences (too trivial / too long)

Fixed sentences get a new sent_id, so re-running 05_audio.py generates their
audio and 06_build_decks.py picks everything up (word GUIDs unchanged).

Usage: python 07_qa_batch.py [submit|poll|merge|run]   (default: run)
"""
import gzip
import json
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from lib import (PROCESSED, SENTENCE_FIELDS, SENTENCES_CSV, WORD_FIELDS,
                 WORD_SENTENCE_CSV, WORDS_CSV, WS_FIELDS, read_csv, write_csv)

MODEL = "gpt-5.6-luna"
CHUNK = 20
STATE = PROCESSED / "qa_state.json"
QA_IN = PROCESSED / "qa_input.jsonl"
QA_OUT = PROCESSED / "qa_output.jsonl"

SYSTEM = """You are reviewing entries of a German A1-B2 vocabulary dataset (EN + RU translations,
one example sentence each). For every entry decide "ok" or "fix".

Fix when any of these hold:
- EN or RU translation is wrong, unnatural, or misses the word's primary sense
  (a "wikt" field, when present, gives independent Wiktionary reference translations - the
  entry may still be right when it disagrees with wikt, judge for yourself);
- the sentence does not clearly illustrate the word's core meaning;
- the sentence's vocabulary or grammar is clearly above the word's CEFR level;
- the sentence is degenerate (fragment, wrong word highlighted, >16 words, unnatural);
- the sentence translations (en/ru) are wrong or missing.

Return strict JSON {"items": [...]}, one object per input entry:
  {"word_id": "...", "verdict": "ok"}
or
  {"word_id": "...", "verdict": "fix",
   "en": "...", "ru": "...",                      // only fields that change
   "sentence": {"de": "...", "en": "...", "ru": "..."}  // full replacement, only if the sentence changes;
                                                        // 6-12 words, within the word's CEFR level
  }
No markdown, no commentary."""


def get_client():
    from openai import OpenAI
    if not os.environ.get("OPENAI_API_KEY"):
        sys.exit("OPENAI_API_KEY is not set. Export it and re-run.")
    return OpenAI()


def build_requests() -> list[dict]:
    words = [w for w in read_csv(WORDS_CSV) if w["status"] in ("enriched", "qa_flagged")]
    sentences = {s["sent_id"]: s for s in read_csv(SENTENCES_CSV)}
    primary = {}
    for l in read_csv(WORD_SENTENCE_CSV):
        if l["is_primary"] == "1" and l["word_id"] not in primary:
            primary[l["word_id"]] = l["sent_id"]
    with gzip.open(PROCESSED / "lexicon.json.gz", "rt", encoding="utf-8") as f:
        lexicon = json.load(f)

    reqs = []
    for i in range(0, len(words), CHUNK):
        items = []
        for w in words[i:i + CHUNK]:
            s = sentences.get(primary.get(w["word_id"], ""), {})
            item = {"word_id": w["word_id"], "word": w["display"], "pos": w["pos"],
                    "level": w["level"], "en": w["en"], "ru": w["ru"],
                    "sentence": {"de": s.get("de", ""), "en": s.get("en", ""),
                                 "ru": s.get("ru", "")}}
            if w["status"] == "qa_flagged":
                entry = lexicon.get(w["lemma"]) or lexicon.get(w["lemma"].capitalize()) or {}
                item["wikt"] = {"en": entry.get("en", [])[:3], "ru": entry.get("ru", [])[:3]}
            items.append(item)
        reqs.append({
            "custom_id": f"qa-{i // CHUNK:04d}",
            "method": "POST",
            "url": "/v1/chat/completions",
            "body": {
                "model": MODEL,
                "response_format": {"type": "json_object"},
                "messages": [{"role": "system", "content": SYSTEM},
                             {"role": "user", "content": json.dumps(items, ensure_ascii=False)}],
            },
        })
    return reqs


def submit():
    reqs = build_requests()
    with open(QA_IN, "w", encoding="utf-8") as f:
        for r in reqs:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    client = get_client()
    up = client.files.create(file=open(QA_IN, "rb"), purpose="batch")
    batch = client.batches.create(input_file_id=up.id, endpoint="/v1/chat/completions",
                                  completion_window="24h")
    STATE.write_text(json.dumps({"batch_id": batch.id, "stage": "qa"}))
    print(f"submitted QA batch {batch.id} ({len(reqs)} requests)")


def poll(wait: bool = False) -> bool:
    client = get_client()
    bid = json.loads(STATE.read_text())["batch_id"]
    while True:
        b = client.batches.retrieve(bid)
        print(f"status={b.status} counts={getattr(b, 'request_counts', None)}")
        if b.status == "completed":
            QA_OUT.write_bytes(client.files.content(b.output_file_id).content)
            print(f"downloaded -> {QA_OUT}")
            return True
        if b.status in ("failed", "expired", "cancelled"):
            sys.exit(f"QA batch ended with status {b.status}")
        if not wait:
            return False
        time.sleep(60)


def merge():
    words = read_csv(WORDS_CSV)
    by_id = {w["word_id"]: w for w in words}
    sentences = read_csv(SENTENCES_CSV)
    sent_by_id = {s["sent_id"]: s for s in sentences}
    links = read_csv(WORD_SENTENCE_CSV)
    primary_link = {l["word_id"]: l for l in links if l["is_primary"] == "1"}

    results = []
    for line in open(QA_OUT, encoding="utf-8"):
        o = json.loads(line)
        body = o.get("response", {}).get("body", {})
        if o.get("error") or body.get("error"):
            print(f"request {o.get('custom_id')} errored")
            continue
        try:
            results.extend(json.loads(body["choices"][0]["message"]["content"])["items"])
        except (json.JSONDecodeError, KeyError, TypeError) as e:
            print(f"unparseable {o.get('custom_id')}: {e}")

    n_ok = n_fix = n_sent_fix = 0
    for r in results:
        w = by_id.get(r.get("word_id"))
        if not w:
            continue
        if r.get("verdict") == "ok":
            w["status"] = "qa_ok"
            n_ok += 1
            continue
        n_fix += 1
        for f in ("en", "ru", "topic"):
            if r.get(f):
                w[f] = str(r[f]).strip()
        s = r.get("sentence") or {}
        if s.get("de"):
            n_sent_fix += 1
            new_id = f"q-{w['word_id']}"
            sent_by_id[new_id] = {
                "sent_id": new_id, "de": s["de"], "en": s.get("en", ""),
                "ru": s.get("ru", ""), "level": w["level"], "source": "llm-qa",
                "audio": f"sent_{new_id}.mp3", "tatoeba_audio_license": "",
            }
            link = primary_link.get(w["word_id"])
            if link:
                link["sent_id"] = new_id
            else:
                links.append({"word_id": w["word_id"], "sent_id": new_id, "is_primary": "1"})
        w["status"] = "qa_ok"

    # keep only referenced sentences
    used = {l["sent_id"] for l in links}
    sentences_out = [s for s in sent_by_id.values() if s["sent_id"] in used]
    write_csv(WORDS_CSV, words, WORD_FIELDS)
    write_csv(SENTENCES_CSV, sentences_out, SENTENCE_FIELDS)
    write_csv(WORD_SENTENCE_CSV, links, WS_FIELDS)
    print(f"QA merged: {n_ok} ok, {n_fix} fixed ({n_sent_fix} sentences replaced)")
    print("next: re-run 05_audio.py (new sentence audio) and 06_build_decks.py")


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
