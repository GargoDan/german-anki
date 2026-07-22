"""Step 6: build the Anki package (.apkg) from the processed dataset.

Deck tree:
  Deutsch::Woerter::{A1,A2,B1,B2}   - word cards (DE -> EN/RU, with sentence)
  Deutsch::Saetze::{A1,A2,B1,B2}    - sentence cards (sentence -> translations)

Note GUIDs are derived from word_id / sent_id, so rebuilding and re-importing
preserves review progress. Tags: level::<lvl>, topic::<slug>, source::<src>.

Output: decks/deutsch_a1_b2.apkg
"""
import html
import re
import sys
import zlib
from pathlib import Path

import genanki
import simplemma

sys.path.insert(0, str(Path(__file__).parent))
from lib import (DECKS, MEDIA, SENTENCES_CSV, WORD_SENTENCE_CSV, WORDS_CSV,
                 read_csv)

CSS = """
.card { font-family: -apple-system, "Helvetica Neue", sans-serif; font-size: 24px;
        text-align: center; color: #222; background-color: #fbfaf8; }
.night_mode .card { color: #eee; background-color: #2f2f31; }
.word { font-size: 34px; font-weight: 600; }
.forms { font-size: 18px; color: #888; margin-top: 4px; }
.trans { font-size: 26px; margin: 10px 0 2px; }
.trans.ru { color: #7a5ea8; } .night_mode .trans.ru { color: #b79ae0; }
.sentence { font-size: 22px; margin-top: 16px; }
.sentence b { color: #b3592a; } .night_mode .sentence b { color: #f0956a; }
.senttrans { font-size: 17px; color: #777; margin-top: 4px; }
.night_mode .senttrans { color: #aaa; }
.extras { margin-top: 10px; }
.extras .sentence { font-size: 19px; margin-top: 12px; }
.meta { font-size: 13px; color: #aaa; margin-top: 18px; }
hr { border: none; border-top: 1px solid #ddd; margin: 14px 0; }
.night_mode hr { border-top-color: #555; }
"""

WORD_MODEL = genanki.Model(
    1607392319, "DE Wort",
    fields=[{"name": f} for f in
            ("Word", "Forms", "EN", "RU", "Sentence", "SentenceEN", "SentenceRU",
             "WordAudio", "SentenceAudio", "Extras", "Topic", "Level")],
    templates=[{
        "name": "Recognition",
        "qfmt": '<div class="word">{{Word}}</div>{{WordAudio}}',
        "afmt": ('{{FrontSide}}<hr>'
                 '<div class="forms">{{Forms}}</div>'
                 '<div class="trans en">{{EN}}</div>'
                 '<div class="trans ru">{{RU}}</div>'
                 '<div class="sentence">{{Sentence}}</div>'
                 '<div class="senttrans">{{SentenceEN}}<br>{{SentenceRU}}</div>'
                 '{{SentenceAudio}}'
                 '{{#Extras}}<div class="extras">{{Extras}}</div>{{/Extras}}'
                 '<div class="meta">{{Level}} &middot; {{Topic}}</div>'),
    }],
    css=CSS,
)

SENT_MODEL = genanki.Model(
    1607392320, "DE Satz",
    fields=[{"name": f} for f in
            ("Sentence", "SentenceEN", "SentenceRU", "SentenceAudio",
             "Word", "EN", "RU", "Level")],
    templates=[{
        "name": "Sentence",
        "qfmt": '<div class="sentence">{{Sentence}}</div>{{SentenceAudio}}',
        "afmt": ('{{FrontSide}}<hr>'
                 '<div class="senttrans">{{SentenceEN}}<br>{{SentenceRU}}</div>'
                 '<div class="trans en" style="font-size:20px">{{Word}} — {{EN}} / {{RU}}</div>'
                 '<div class="meta">{{Level}}</div>'),
    }],
    css=CSS,
)


def deck_id(name: str) -> int:
    return zlib.crc32(name.encode()) + 2_000_000_000


def highlight(sentence: str, lemma: str) -> str:
    """Bold tokens of the sentence that lemmatize to the target lemma."""
    lem_low = lemma.lower()

    def repl(m):
        tok = m.group(0)
        if tok.lower() == lem_low or simplemma.lemmatize(tok, lang="de").lower() == lem_low:
            return f"<b>{tok}</b>"
        return tok

    return re.sub(r"[A-Za-zÄÖÜäöüß]+", repl, html.escape(sentence))


def forms_line(w: dict) -> str:
    if w["pos"] == "noun" and w["plural"]:
        return f"Pl.: {w['plural']}"
    if w["verb_forms"]:
        return w["verb_forms"]
    return ""


def main():
    words = [w for w in read_csv(WORDS_CSV) if w["status"] not in ("rejected",)]
    sentences = {s["sent_id"]: s for s in read_csv(SENTENCES_CSV)} if SENTENCES_CSV.exists() else {}
    primary, extras = {}, {}
    if WORD_SENTENCE_CSV.exists():
        for l in read_csv(WORD_SENTENCE_CSV):
            if l["is_primary"] == "1" and l["word_id"] not in primary:
                primary[l["word_id"]] = l["sent_id"]
            elif l["is_primary"] == "0":
                extras.setdefault(l["word_id"], []).append(l["sent_id"])

    decks = {}
    for kind in ("Woerter", "Saetze"):
        for lvl in ("A1", "A2", "B1", "B2"):
            name = f"Deutsch::{kind}::{lvl}"
            decks[(kind, lvl)] = genanki.Deck(deck_id(name), name)

    media: set[str] = set()

    def sound(fname: str) -> str:
        if fname and (MEDIA / fname).exists():
            media.add(fname)
            return f"[sound:{fname}]"
        return ""

    n_word = n_sent = 0
    for w in words:
        sid = primary.get(w["word_id"])
        s = sentences.get(sid, {})
        hl = highlight(s["de"], w["lemma"]) if s else ""
        tags = [f"level::{w['level']}", f"source::{w['source']}"]
        if w["topic"]:
            tags.append(f"topic::{w['topic']}")
        extras_html = ""
        for xid in extras.get(w["word_id"], []):
            x = sentences.get(xid)
            if not x:
                continue
            extras_html += (
                f'<div class="sentence">{highlight(x["de"], w["lemma"])}</div>'
                f'<div class="senttrans">{html.escape(x["en"])}<br>'
                f'{html.escape(x["ru"])}</div>{sound(x["audio"])}')
        note = genanki.Note(
            model=WORD_MODEL,
            fields=[
                html.escape(w["display"]), html.escape(forms_line(w)),
                html.escape(w["en"]), html.escape(w["ru"]),
                hl, html.escape(s.get("en", "")), html.escape(s.get("ru", "")),
                sound(w["audio"]), sound(s.get("audio", "")),
                extras_html, w["topic"], w["level"],
            ],
            guid=genanki.guid_for("word", w["word_id"]),
            tags=tags,
        )
        decks[("Woerter", w["level"])].add_note(note)
        n_word += 1

        if s:
            snote = genanki.Note(
                model=SENT_MODEL,
                fields=[
                    hl, html.escape(s.get("en", "")), html.escape(s.get("ru", "")),
                    sound(s.get("audio", "")),
                    html.escape(w["display"]), html.escape(w["en"]), html.escape(w["ru"]),
                    w["level"],
                ],
                guid=genanki.guid_for("sent", sid, w["word_id"]),
                tags=tags,
            )
            decks[("Saetze", w["level"])].add_note(snote)
            n_sent += 1

    DECKS.mkdir(exist_ok=True)
    pkg = genanki.Package(list(decks.values()))
    pkg.media_files = [str(MEDIA / m) for m in sorted(media)]
    out = DECKS / "deutsch_a1_b2.apkg"
    pkg.write_to_file(str(out))
    print(f"wrote {out}: {n_word} word notes, {n_sent} sentence notes, {len(media)} media files")
    for (kind, lvl), d in decks.items():
        print(f"  {kind}/{lvl}: {len(d.notes)} notes")


if __name__ == "__main__":
    main()
