# Beyond Vocabulary: Expansion Plan for the German App

**Status:** design only — nothing here is implemented yet. This document is the
source of truth for *what the app could become* after the vocabulary SRS.
**Last updated:** 2026-07-22.

## Why this doc exists

The app today is a strong **vocabulary SRS** (3 pages — Progress / Session /
Settings, SM-2 scheduling, per-level and per-topic progress, audio, browse). That
covers exactly one slice of what the Goethe exam demands. The exam is **four
graded modules** — Lesen (reading), Hören (listening), Schreiben (writing),
Sprechen (speaking) — sitting on top of **grammar** that escalates per level
(see `compass_artifact_..._markdown.md` for the full syllabus). We've built the
*fuel* (words) but not the *skills* the exam scores.

This doc records a brainstorm of how to grow the app toward full exam prep, what
we decided to build first, and a wide menu of options we have **not** planned in
detail so nothing is lost.

## Design principles (constraints every addition must respect)

These come from the original `design.md` and the way the app is already built.
New modules should not violate them without an explicit decision:

1. **On-device, no deployed backend.** Content is bundled static; "intelligence"
   lives in the offline generation pipeline, not a server. The one feature that
   genuinely breaks this is Writing/Speaking feedback (see below).
2. **Minimalist, uncluttered, 3-page frame.** Grow *within* Progress / Session /
   Settings rather than sprawling into many tabs.
3. **Everything rides the same SRS engine.** Reuse SM-2, the 04:00 rollover,
   "learned = interval ≥ 21 d", the strength meter, and review history. New
   learnable content = new card types, not new schedulers.
4. **Reuse the content pipeline.** The OpenAI batch pipeline that authored the
   vocab deck can author grammar, reading, and listening content offline, keeping
   the phone static, free, and lag-free.
5. **Progress is always by level and topic**, shown as bars/rings, not raw
   numbers (numbers on tap only).

## Decisions made in this session (2026-07-22)

- **Grammar drills** are the first module to build after vocab (highest leverage,
  least new plumbing).
- **Writing & Speaking feedback is parked** for now (it's the only piece needing a
  live LLM; revisit later).
- Grammar cards use **reveal + self-grade (Anki-style)** — *not* typed input or
  auto-checking. This collapses all card types into one interaction and removes
  the need for distractors and fuzzy matching.

---

## The original brainstorm — the full initial menu

Before we drilled into grammar, the first brainstorm proposed a whole set of
modules, organized by **how much new plumbing each needs**. Capturing it here so
the original vision is preserved as one list, independent of what we later chose
to build first.

**Framing:** vocabulary is the *fuel*; the exam scores *skills*. The Goethe exam
is four graded modules — **Lesen, Hören, Schreiben, Sprechen** — on top of
**grammar**. The app has the fuel but none of the skills yet. The four skills map
directly onto candidate modules below.

**Tier 1 — reuse the SRS rails, 100% on-device, no backend:**
- **Grammar drills** — cloze/transformation cards mapping onto the existing level
  system; the highest-leverage, least-plumbing addition. *(Now planned in detail
  below.)*
- **Listening (Hören)** — reuse the ~19k audio clips already generated: play a
  sentence/dialog with text hidden, then comprehension/reveal. Nearly free.

**Tier 2 — new content type, still local (pipeline-authored, bundled):**
- **Reading (Lesen)** — graded passages per level with comprehension questions and
  **tap-any-word to reveal its translation/card**, feeding unknown words back into
  the vocab deck.
- **Mock-exam mode** — timed Modellsatz-style sets with a **readiness-per-module**
  gauge; especially valuable at B1/B2, which are modular and passed per skill.

**Tier 3 — genuinely needs a live LLM (the backend conversation):**
- **Writing (Schreiben) & Speaking (Sprechen)** — the only modules that can't be
  static, because they grade the user's *own* output. Three handling options:
  on-device checklist (no backend), thin cloud call on submit (no persistent
  server), or full backend (not recommended). *(Parked for now.)*

**Cross-cutting from the initial brainstorm:**
- **Navigation:** keep the 3-page frame; turn the **Progress page into a
  disciplines hub** (Words · Grammar · Listening · Reading · Writing, each with its
  own level bar) and make the **middle page a polymorphic session runner**.
- **The unlock you already own:** every non-writing module can be **authored
  offline by the same batch LLM pipeline** that built the vocab deck, so the phone
  stays static, free, and lag-free — the intelligence lives in generation, not a
  server.

*(Each of these is expanded either in "Module 1" below or in "Modules discussed
but NOT planned in detail". The wider, previously-unconsidered ideas live in the
"open idea bank" further down.)*

---

## Module 1 — Grammar drills (PLANNED IN DETAIL, not yet built)

The whole design goal is to make grammar behave like vocabulary so it inherits
the SRS engine, progress bars, and session runner.

### Two new concepts

**Grammar topics** — the grammar analog of vocab topics, one progress bar per
level, taken from the study-plan doc:

- **A1:** Präsens · sein/haben · Modalverben · trennbare Verben · Nom/Akk
  articles · kein vs. nicht · W-Fragen / V2 word order
- **A2:** Dativ · Wechselpräpositionen · Perfekt · Nebensätze (weil/dass/wenn) ·
  Komparativ/Superlativ · Adjektivdeklination · Infinitiv mit zu / um…zu
- **B1:** Konjunktiv II · Passiv (Vorgangs-/Zustandspassiv) · Relativsätze ·
  Genitiv · Plusquamperfekt · Konnektoren (obwohl/deshalb/je…desto)
- **B2:** Konjunktiv I · Partizipialattribute · Nominalstil ↔ Verbalstil ·
  erweitertes Passiv & Passiversatz · Futur II · advanced Konnektoren

**Card types** (the `type` field only changes how the prompt is *phrased*, since
the answer interaction is identical for all):

- **Cloze** — the workhorse: "Gestern `___` ich ins Kino gegangen. *(gehen)*" → `bin`
- **Multiple choice** — der/die/das, Akk vs. Dativ, correct connector (rendered as
  a question; answer revealed, still self-graded)
- **Transformation** — "Präsens → Perfekt", "decline the adjective"
- **Word order / Satzbau** — arrange the sentence (verb-second, verb-final in
  Nebensätze). Highest value for German but the only type needing custom
  interaction if ever made interactive; with reveal + self-grade it just shows
  the correctly ordered sentence. Add in a later pass.

### Card shape (one shape for all types)

- `prompt` — the drill, blank shown as `___`
- `answer` — revealed on tap
- `explanation` — one line shown with the answer
  ("Bewegungsverben bilden das Perfekt mit *sein*.")
- `level`, `grammar_topic`, `type`

No distractors, no alternatives — reveal + self-grade makes them unnecessary.

### Schema

- `content.sqlite`: new table
  `grammar_cards(id, level, grammar_topic, type, prompt, answer, explanation)` —
  bundled, static.
- `progress.sqlite`: **reuse** `card_state` / `review_log` with `g:<id>`
  namespacing so grammar and vocab schedule independently but share one SM-2
  engine, rollover, "learned ≥ 21 d", strength meter, and history — all for free.

### Generation

- `pipeline/11_grammar_cards.py`: OpenAI batch job, per grammar topic, emits
  `{prompt, answer, explanation, type}` JSON.
- Grammar answers are far more verifiable than free-text sentences, so add a
  **rule-based validator** (answer is a real conjugation / declension, prompt
  contains exactly one blank, etc.) for much tighter QA than the vocab sentences
  got. Mirror the existing crosscheck → `qa_flagged` pattern.

### UI (no new pages)

- **Progress hub:** a **Grammar** discipline next to Words — per-level bar + a
  grammar-topic grid reusing `TopicGridCard` / progress-ring style (new icons in
  the `TopicStyle` map). Tap a topic → `TopicStartSheet` → grammar session.
- **Session runner:** the existing word-card view with different field labels —
  reveal on tap, then the existing 4-button self-grade. Fully generalizes.
- **Browse/Settings:** grammar cards appear in browse with their explanation; the
  strength meter and answer history already built work unchanged.

**Net new work:** one table, one card view, one pipeline script. No architectural
change.

---

## Modules discussed but NOT planned in detail

These were part of the brainstorm and are the natural next candidates after
grammar. They are sketched, not specified.

### Listening (Hören) — Tier 1, no backend

You already have ~19k generated audio clips. Turn them into listening cards: play
a sentence / short dialog with the text hidden, then a comprehension tap or
reveal. Nearly free given the existing audio pipeline. Extend later with
generated multi-line dialogs and number/date/time drills (a classic exam trap).

### Reading (Lesen) — Tier 2, no backend

Graded passages per level with comprehension questions, plus **tap-any-word to
reveal its translation/card** — which ties reading back into the vocab deck
(unknown words can be pushed into review). Passages authored offline via the
existing batch pipeline and bundled like the words.

### Mock-exam mode — Tier 2, no backend

Timed, Modellsatz-style sets — especially valuable at B1/B2 since those exams are
**modular** and passed per skill. A "readiness per module" gauge is probably the
single most motivating feature for someone aiming at a dated exam. Depends on
having reading/listening/grammar content to draw from.

### Writing & Speaking (Schreiben / Sprechen) — Tier 3, needs a live LLM

The two modules you **cannot** fake with static content, because they require
feedback on the user's *own* output (grading a forum post, correcting a formal
email, evaluating a 4-minute Vortrag). Three handling options:

1. **On-device checklist only** — model answers + a self-assessment rubric
   (structure, connectors, register). Zero backend, zero cost, no personalized
   correction. *(This is the current parked-but-safe default.)*
2. **Thin cloud call on submit** — the phone calls an LLM only when the user
   submits writing/speech (speech transcribed on-device via iOS Speech).
   Pay-per-use, no persistent server — fits "no deployed backend" while giving
   real feedback. The one place the tradeoff is arguably worth it.
3. **Full backend** — overkill for a single-user phone app; not recommended.

**Decision so far:** parked. Revisit once the receptive skills exist.

### Navigation evolution — the disciplines hub

Adding grammar (and later listening/reading) means the **Progress page becomes a
hub**: instead of only "start a vocab session," you pick a **discipline** —
Words · Grammar · Listening · Reading · (Writing) — each with its own
progress-by-level bar, so "A2 grammar 40 %, A2 vocab 80 %" is visible at a glance.
The **middle page stays the session runner but goes polymorphic**, rendering
whatever card type the session is. **Settings** gains discipline toggles, an
exam-date countdown, and (later) the writing-feedback mode. This shift affects
everything added later, so it's worth designing before the second discipline
lands.

---

## Options we did NOT consider or plan (open idea bank)

A wider menu, unfiltered, so nothing is lost. Not endorsed — just captured. Loosely
grouped and tagged by how well they fit the constraints.

### German-specific trainers (all Tier 1, no backend, pipeline-authored)

- **Gender trainer (der/die/das).** Gender is one of the hardest parts of German;
  a dedicated fast-tap drill over nouns you already have, possibly color-coded by
  gender, with plural forms. Very high value, trivial content (already in the
  word data).
- **Verb conjugation trainer.** Full conjugation tables + drills (person/tense).
  Strong candidate to fold into the grammar module rather than stand alone.
- **Separable/inseparable prefix verbs.** A notorious stumbling block; drill the
  prefix placement and meaning shifts (stehen → aufstehen → verstehen).
- **Wortfamilie / word roots.** Group words by root and prefix to teach derivation
  and expand vocab productively rather than one word at a time.
- **Redemittel / fixed phrases.** Chunk lists of formulaic phrases for Schreiben
  and Sprechen (opinion, agreeing, structuring a presentation). Directly targets
  the productive modules without needing feedback — just memorization.
- **Collocations.** "starke/schwache Verben + Nomen" pairs; teaches words in the
  combinations examiners expect.

### Production & pronunciation (mixed feasibility)

- **Typed production / reverse cards.** Translation → produce the German (typed).
  More rigorous than recognition; needs fuzzy matching (umlauts, case). We
  explicitly chose *against* this for grammar, but it could be an optional "hard
  mode" per discipline.
- **Diktat (dictation).** Hear audio → type what you heard. Trains listening +
  spelling together; uses existing audio; needs typed-input checking.
- **Pronunciation scoring.** On-device iOS Speech recognition to check whether a
  spoken word/sentence is intelligible. No backend, but accuracy is limited and it
  can be discouraging if too strict.

### Scheduling, motivation, retention

- **Exam-date countdown + study planner.** Enter your exam date and target level;
  the app back-plans a daily card budget across disciplines (the study-plan doc
  gives hour estimates per level to anchor this).
- **Daily goals, streaks, gamification.** Light streak/goal mechanics to drive the
  daily-review habit SRS depends on. Keep minimal to respect the uncluttered
  principle.
- **Home-screen widget + notifications.** "42 cards due" widget and a daily
  reminder. Notifications are the highest-leverage retention feature for any SRS
  app and cost almost nothing.
- **"Weak spots" auto-deck.** A dynamically composed review of your most-lapsed
  cards across all disciplines (error log). Falls out naturally from `review_log`.
- **Adaptive mixed sessions.** A single session that interleaves vocab + grammar +
  listening weighted by what's due and weak, instead of choosing one discipline.

### Content depth & authenticity

- **Sentence mining from real media.** Pull example sentences/passages from
  authentic B1–B2 sources (news, DW Nachrichten) rather than generated ones, for
  register authenticity. Licensing needs care.
- **Landeskunde / cultural notes.** Short cultural/context notes attached to
  topics — relevant to the exam's real-world scenarios and generally enriching.
- **Etymology / mnemonics.** Optional memory hooks per word (especially for
  gender), pipeline-generated.

### Platform & sync (the backend-lite conversation)

- **iCloud / CloudKit progress sync.** Not a "deployed backend" in the server
  sense — Apple hosts it — so it could sync progress across a user's own devices
  without violating the no-server rule. Enables an iPad/Mac Catalyst version and a
  safety net for progress.
- **Progress import/export.** Simple file-based backup of `progress.sqlite`.
- **Apple Watch companion.** Quick review on the wrist; a stretch, but SRS suits
  micro-sessions.
- **FSRS instead of SM-2.** A modern scheduler (FSRS) usually beats SM-2 on
  retention efficiency; a possible future upgrade to the engine underneath
  everything. Would change scheduling behavior for existing users, so gate it.

### Accessibility & polish

- **Dynamic Type, VoiceOver, high-contrast.** Especially relevant since audio and
  color-coding carry meaning (gender colors must not be the *only* signal).
- **On-device TTS fallback.** For any user-added or newly generated content that
  lacks a pre-baked clip.

---

## Suggested phasing (not committed)

1. **Grammar drills** (specified above) + the **disciplines hub** navigation
   refactor that makes room for it.
2. **Listening** (cheap — reuse existing audio) and the **gender/conjugation
   trainers** (cheap — reuse existing word data).
3. **Reading** passages + **tap-to-translate** integration.
4. **Mock-exam mode** once 1–3 provide the item pool; add **exam countdown /
   planner** and **notifications**.
5. **Writing/Speaking** — decide backend stance (on-device checklist vs. thin
   cloud call) and build last.

## Open decisions to revisit

- Whether Writing/Speaking ever gets a live-LLM path, and if so which of the three
  options above.
- Whether to keep SM-2 or migrate to FSRS before the deck of disciplines grows.
- Whether the conjugation/gender trainers are standalone disciplines or live
  inside the Grammar module.
- Whether to add typed "hard mode" production anywhere, given we chose recognition
  + self-grade for grammar.
