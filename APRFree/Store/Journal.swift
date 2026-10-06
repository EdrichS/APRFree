import Foundation

/// The last few things the user did, so any of them can be taken back and put back again.
/// Each step keeps the data as it was just before it.
struct Journal: Codable {
    struct Step: Codable {
        /// What was done, in a few words: "Delete Chase".
        var label: String
        var data: AppData
    }

    static let limit = 15

    var undo: [Step] = []
    var redo: [Step] = []

    var isEmpty: Bool { undo.isEmpty && redo.isEmpty }

    /// Records that `label` is about to change the data from `before`. Anything that had been
    /// undone can no longer be redone: history has moved on.
    ///
    /// With `merging`, a run of the same change is one step. Typing a new safety buffer and then
    /// correcting it is undone in one go, back to what it was before the first of them.
    mutating func record(_ label: String, before: AppData, merging: Bool = false) {
        if merging, undo.last?.label == label {
            redo.removeAll()
            return
        }
        undo.append(Step(label: label, data: before.withoutHistory))
        if undo.count > Journal.limit { undo.removeFirst(undo.count - Journal.limit) }
        redo.removeAll()
    }

    /// Takes the latest step back. Returns the data to go back to.
    mutating func takeBack(current: AppData) -> Step? {
        guard let step = undo.popLast() else { return nil }
        redo.append(Step(label: step.label, data: current.withoutHistory))
        return step
    }

    /// Puts the latest undone step back.
    mutating func putBack(current: AppData) -> Step? {
        guard let step = redo.popLast() else { return nil }
        undo.append(Step(label: step.label, data: current.withoutHistory))
        return step
    }
}

extension AppData {
    /// Balance history is worked out from the entries, so there is no need to keep a copy in every step.
    fileprivate var withoutHistory: AppData {
        var copy = self
        copy.history = []
        return copy
    }

    /// Undo and redo move the debts, the entries and the plan back and forth. What belongs to the
    /// iPhone rather than to the plan stays as it is now: the reminder switches, the last backup,
    /// what has been accepted, and notices already read.
    func keepingDeviceSettings(of current: AppData) -> AppData {
        var copy = self
        copy.settings.remindDueDates = current.settings.remindDueDates
        copy.settings.remindPaydays = current.settings.remindPaydays
        copy.settings.lastBackup = current.settings.lastBackup
        copy.settings.onboarded = current.settings.onboarded
        copy.settings.acceptedPrivacy = current.settings.acceptedPrivacy
        copy.settings.acceptedDisclaimer = current.settings.acceptedDisclaimer
        copy.settings.acceptedLegalVersion = current.settings.acceptedLegalVersion
        copy.settings.notices = current.settings.notices
        return copy
    }
}
