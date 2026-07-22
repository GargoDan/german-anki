# German A1→B2 Anki data pipeline

Builds a ~5,000-word German learning dataset (EN + RU translations, CEFR level,
Goethe-aligned topic, example sentence with translations, German audio for words
and sentences) and packages it as Anki decks with stable GUIDs (progress survives
rebuilds).

## Setup

```sh
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
export OPENAI_API_KEY=sk-...   # needed for steps 03 and 07 only
```

## Steps (run from the repo root)

| # | Script | What it does | Needs |
|---|---|---|---|
| 00 | `00_lexicon.py` | Condenses two kaikki.org Wiktionary extracts into `data/processed/lexicon.json.gz` (POS gate + EN/RU reference translations) | ~400MB download (done by hand or re-download the two `data/raw/kaikki_*.jsonl.gz` files) |
| 01 | `01_ingest.py` | Word inventory: DWDS Goethe A1/A2/B1 lists + the B2 docx in `docs/` + lexicon-gated frequency gap-fill → `words.csv` (over-provisioned ~5.3k; LLM rejects junk later) | internet |
| 02 | `02_tatoeba.py` | Downloads Tatoeba exports, indexes DE sentences by lemma, selects ≤5 candidates/word (must have EN; prefers RU + human audio) → `candidates.jsonl` | internet, ~1GB downloads |
| 03 | `03_enrich_batch.py run` | OpenAI Batch (`gpt-5.6-luna`): EN/RU translations, topic, grammar fill, sentence choice (Tatoeba pick or new level-appropriate sentence), junk rejection → updates `words.csv`, writes `sentences.csv` + `word_sentence.csv` | `OPENAI_API_KEY` |
| 04 | `04_crosscheck.py` | Flags words whose EN/RU disagree with Wiktionary → `status=qa_flagged` + `crosscheck_report.csv` | — |
| 05 | `05_audio.py` | edge-tts (`de-DE-KatjaNeural`) audio for every word (+article for nouns) and sentence → `media/`. Resumable. | internet |
| 06 | `06_build_decks.py` | Builds `decks/deutsch_a1_b2.apkg`: `Deutsch::Woerter::{A1..B2}` + `Deutsch::Saetze::{A1..B2}`, tags `level::…`, `topic::…` | — |
| 07 | `07_qa_batch.py run` | QA batch: scores every entry, fixes bad translations/sentences (flagged words get Wiktionary hints). Then re-run 05 + 06. | `OPENAI_API_KEY` |
| 08 | `08_extra_sentences.py run` | Adds 2 extra example sentences per word (vetted Tatoeba candidates, LLM fallback) → every word has 3 sentences. Then re-run 05 + 06. | `OPENAI_API_KEY` |
| 09 | `09_build_app_db.py` | Builds `data/app/content.sqlite` for the iOS app (words + sentences + links + topics; `--verify-audio` checks files exist) | run 10 first |
| 10 | `10_convert_audio.py` | Converts `media/*.mp3` → HE-AAC `data/app/audio/{words,sentences}/*.m4a` (~25% smaller) for the app bundle. Resumable; `--check` verifies parity. | macOS `afconvert` |

Steps 03/07 also support `submit` / `poll` / `merge` subcommands if you don't
want to keep a terminal open while the batch runs (batches usually finish in
well under an hour; the API allows up to 24h).

## Data model

- `data/processed/words.csv` — one row per word; `word_id` is the stable key and the Anki note GUID.
- `data/processed/sentences.csv` — `sent_id` (`t<tatoeba-id>`, `g-<word_id>` LLM, `q-<word_id>` QA-replacement), DE/EN/RU, audio filename.
- `data/processed/word_sentence.csv` — links, `is_primary=1` marks the sentence shown on the word card.
- `data/processed/topics.json` — per-level topic taxonomy distilled from `docs/`.
- `media/` — `word_<word_id>.mp3`, `sent_<sent_id>.mp3`.

## Notes

- Rebuilding the .apkg and re-importing into Anki updates card content in place
  and keeps scheduling, because GUIDs derive from `word_id`/`sent_id`.
- The word note type has a Recognition card (DE → EN/RU). A production card
  (EN/RU → DE) can be added by appending a second template in
  `06_build_decks.py` — all fields are already present.
- Tatoeba content is CC-BY (attribution: tatoeba.org); sentence IDs are kept in
  `sentences.csv` (`source` column).
