import Foundation

@main
struct ModelTests {
    @MainActor static func main() async throws {
        let suite = "nonappa-model-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        let fixture = PreviewSleepBackend(state: "normal")
        let model = SleepModel(previewState: "normal", preferences: preferences, backend: fixture.backend)
        precondition(!model.updates.configured && !model.updates.canCheck)
        await model.readStatus()
        precondition(model.disabled == false && model.deadline == nil)
        model.minutes = 30
        await model.change(minutes: model.minutes)
        precondition(model.disabled == true && model.deadline != nil && !model.busy)
        let deadline = model.deadline

        // Reopening the UI reads the persisted duration and independent restore job.
        let reopened = SleepModel(previewState: "normal", preferences: preferences, backend: fixture.backend)
        await reopened.readStatus()
        precondition(reopened.minutes == 30 && reopened.deadline == deadline && reopened.disabled == true)
        await reopened.change(minutes: 0)
        precondition(reopened.disabled == true && reopened.deadline == nil)
        await reopened.change(minutes: -1)
        precondition(reopened.disabled == false && reopened.deadline == nil)

        // A denied or cancelled mutation must retain the observed system state.
        let cancelled = SleepBackend(read: fixture.backend.read, deadline: fixture.backend.deadline,
                                     change: { _ in throw AppError.message("User cancelled (-128)") })
        let cancellation = SleepModel(previewState: "normal", preferences: preferences, backend: cancelled)
        await cancellation.change(minutes: 60)
        precondition(cancellation.disabled == false && cancellation.deadline == nil && !cancellation.busy)
        precondition(cancellation.error == "Cancelled. Your sleep setting hasn’t changed.")

        // Read errors hide stale state and a successful retry clears only the read error.
        fixture.failure = "Unreadable status"
        await model.readStatus()
        precondition(model.disabled == nil && model.deadline == nil && model.error == "Unreadable status")
        fixture.failure = nil
        await model.readStatus()
        precondition(model.disabled == false && model.error == nil)
        model.error = "Helper installation denied"
        await model.readStatus()
        precondition(model.error == "Helper installation denied")

        // Controls cannot mutate an unknown state, skip setup, or issue concurrent commands.
        var calls = 0
        let guarded = SleepModel(previewState: "error", preferences: preferences,
                                 backend: SleepBackend(read: fixture.backend.read, deadline: { nil }, change: { _ in calls += 1 }))
        await guarded.change(minutes: 60)
        guarded.disabled = false; guarded.helperReady = false
        await guarded.change(minutes: 60)
        guarded.helperReady = true; guarded.busy = true
        await guarded.change(minutes: 60)
        precondition(calls == 0)
        print("Passed: UI model timed/indefinite/stop transitions, restart persistence, cancellation, error recovery, setup and busy guards; no OS mutations.")
    }
}
