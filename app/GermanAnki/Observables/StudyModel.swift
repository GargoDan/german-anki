import Foundation
import Observation

/// Drives the card-learning page: the front/reveal state machine, free random
/// browsing, and active study sessions. Grades always persist, session or not.
@Observable @MainActor
final class StudyModel {
    enum Phase: Equatable {
        /// Front side. `sentenceIndex` nil shows the word; 0..2 an example sentence.
        case front(sentenceIndex: Int?)
        /// Answer side with a pending, not-yet-committed grade and its projection.
        case reveal(pending: Grade, projected: CardState)
    }

    private unowned let app: AppModel

    private(set) var word: Word?
    private(set) var sentences: [Sentence] = []
    private(set) var phase: Phase = .front(sentenceIndex: nil)
    private(set) var queue: SessionQueue?
    private(set) var sessionComplete = false

    /// Card state as it was when the card was shown — grades project from here.
    private var baseState: CardState = .newCard("")
    private var recentIDs: [String] = []

    init(app: AppModel) {
        self.app = app
    }

    // MARK: - Card display

    func showRandom() {
        let pool = app.words.filter { !recentIDs.contains($0.id) }
        guard let next = (pool.isEmpty ? app.words : pool).randomElement() else { return }
        show(next)
    }

    private func show(_ w: Word) {
        word = w
        sentences = app.sentences(for: w.id)
        baseState = (try? app.repository?.state(for: w.id)) ?? .newCard(w.id)
        phase = .front(sentenceIndex: nil)
        recentIDs.append(w.id)
        if recentIDs.count > 20 { recentIDs.removeFirst() }
    }

    /// Tap on the word cycles word → sentence 1 → 2 → 3 → word.
    func tapWord() {
        guard case .front(let index) = phase, !sentences.isEmpty else { return }
        switch index {
        case nil: phase = .front(sentenceIndex: 0)
        case let i? where i + 1 < sentences.count: phase = .front(sentenceIndex: i + 1)
        default: phase = .front(sentenceIndex: nil)
        }
    }

    /// Plays audio for whatever is currently shown (word or sentence).
    func playCurrent() {
        guard let word else { return }
        if case .front(let i?) = phase, i < sentences.count, let audio = sentences[i].audio {
            app.audio.play(audio)
        } else {
            app.audio.play(word.audio)
        }
    }

    func play(_ filename: String?) {
        if let filename { app.audio.play(filename) }
    }

    // MARK: - Grading

    func select(_ grade: Grade) {
        let projected = Scheduler.apply(grade, to: baseState, now: .now)
        phase = .reveal(pending: grade, projected: projected)
    }

    func commitAndContinue() {
        guard case .reveal(let grade, let projected) = phase, word != nil else { return }
        try? app.repository?.commit(previous: baseState, next: projected, grade: grade,
                                    sessionID: queue?.info.id, now: .now)
        if let queue {
            queue.didGrade(wordID: projected.wordID)
            advanceInSession()
        } else {
            showRandom()
        }
    }

    private func advanceInSession() {
        guard let queue else { return }
        if let nextID = queue.next(), let next = app.wordsByID[nextID] {
            show(next)
        } else {
            sessionComplete = true
        }
    }

    // MARK: - Sessions

    func startSession(mode: SessionMode, level: Level?, topic: String?, target: Int) {
        if queue != nil { endSession() }
        let info = SessionInfo(id: UUID().uuidString, mode: mode,
                               level: level, topic: topic, target: target)
        let states = (try? app.repository?.allStates()) ?? [:]
        let built = SessionQueue.build(info: info, words: app.words, states: states, now: .now)
        try? app.repository?.insertSession(info, now: .now)
        queue = built
        sessionComplete = false
        advanceInSession()
    }

    func endSession() {
        if let queue {
            try? app.repository?.endSession(id: queue.info.id, now: .now)
        }
        queue = nil
        sessionComplete = false
        showRandom()
    }
}
