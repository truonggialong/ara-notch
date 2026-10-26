/// Why a change to a reminder did not go through, for the notice that says so: before, the
/// notch only beeped and the change was gone at the next reload.
public enum ReminderFailure: Error, Equatable, Sendable {
    /// AraNotch may not use the user's reminders.
    case noAccess
    /// The reminder is not there any more, removed on another device perhaps.
    case gone
    /// The list it is in cannot be changed from this Mac, a shared list for one.
    case readOnly
    /// What the system said.
    case system(String)

    /// The first thing that stood in the way; nil when nothing did.
    public static func reason(hasAccess: Bool, exists: Bool, isWritable: Bool, systemMessage: String?) -> ReminderFailure? {
        if !hasAccess { return .noAccess }
        if !exists { return .gone }
        if !isWritable { return .readOnly }
        return systemMessage.map { .system($0) }
    }
}
