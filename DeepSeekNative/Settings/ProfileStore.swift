import Foundation
import Observation
import WebKit

/// An account slot. Each profile gets its own persistent `WKWebsiteDataStore`,
/// so several DeepSeek accounts can stay signed in side by side.
struct Profile: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
}

@MainActor
@Observable
final class ProfileStore {
    static let shared = ProfileStore()

    private enum Key {
        static let profiles = "profiles"
        static let currentProfile = "currentProfile"
    }

    @ObservationIgnored private let defaults: UserDefaults

    private(set) var profiles: [Profile]
    private(set) var currentID: UUID

    var current: Profile {
        profiles.first { $0.id == currentID } ?? profiles[0]
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var stored = (defaults.data(forKey: Key.profiles))
            .flatMap { try? JSONDecoder().decode([Profile].self, from: $0) } ?? []
        if stored.isEmpty {
            stored = [Profile(id: UUID(), name: "默认账户")]
        }
        profiles = stored
        let savedID = defaults.string(forKey: Key.currentProfile).flatMap(UUID.init(uuidString:))
        currentID = stored.first { $0.id == savedID }?.id ?? stored[0].id
        save()
    }

    func dataStore(for id: UUID) -> WKWebsiteDataStore {
        WKWebsiteDataStore(forIdentifier: id)
    }

    @discardableResult
    func add(named name: String? = nil) -> Profile {
        let profile = Profile(id: UUID(), name: name ?? nextDefaultName())
        profiles.append(profile)
        save()
        return profile
    }

    func rename(_ id: UUID, to name: String) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profiles[index].name = trimmed.isEmpty ? nextDefaultName() : trimmed
        save()
    }

    func select(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        currentID = id
        save()
    }

    /// Deletes a profile that is not in use, together with its cookies and storage.
    func remove(_ id: UUID) async {
        guard id != currentID, profiles.count > 1 else { return }
        profiles.removeAll { $0.id == id }
        save()
        let store = dataStore(for: id)
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        // Best effort: WebKit refuses while anything still references the store; the data is already gone.
        try? await WKWebsiteDataStore.remove(forIdentifier: id)
    }

    private func nextDefaultName() -> String {
        var index = profiles.count + 1
        while profiles.contains(where: { $0.name == "账户 \(index)" }) { index += 1 }
        return "账户 \(index)"
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profiles) {
            defaults.set(data, forKey: Key.profiles)
        }
        defaults.set(currentID.uuidString, forKey: Key.currentProfile)
    }
}
