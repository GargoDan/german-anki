import Foundation

/// All SRS tuning parameters in one place. Values follow Anki's SM-2 defaults.
enum SchedulerConfig {
    /// Learning steps for new cards, in seconds (1 min, 10 min).
    static let learningSteps: [TimeInterval] = [60, 600]
    /// Relearning steps after a lapse, in seconds (10 min).
    static let relearningSteps: [TimeInterval] = [600]
    /// Interval (days) when graduating from learning with Good.
    static let graduatingIntervalDays = 1.0
    /// Interval (days) when grading Easy while learning.
    static let easyIntervalDays = 4.0
    static let startingEase = 2.5
    static let easeFloor = 1.3
    static let lapseEaseDelta = -0.2
    static let hardEaseDelta = -0.15
    static let easyEaseDelta = 0.15
    /// A lapsed card's next review interval = old interval × this (min 1 day).
    static let lapseIntervalMultiplier = 0.5
    static let hardIntervalMultiplier = 1.2
    static let easyBonus = 1.3
    static let maxIntervalDays = 365.0
    /// Review intervals get a deterministic ±5 % fuzz so cards don't clump.
    static let fuzz = 0.05
    /// The SRS "day" rolls over at 04:00 local time, like Anki.
    static let rolloverHour = 4
    /// A card is "learned" (mature) once its review interval reaches this.
    static let matureIntervalDays = 21.0
}
