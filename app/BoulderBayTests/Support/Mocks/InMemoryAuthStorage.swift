import Foundation
import Supabase

final class InMemoryAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private let values = LockedBox<[String: Data]>([:])

    func store(key: String, value: Data) throws {
        values.withValue { $0[key] = value }
    }

    func retrieve(key: String) throws -> Data? {
        values.withValue { $0[key] }
    }

    func remove(key: String) throws {
        values.withValue { $0[key] = nil }
    }
}
