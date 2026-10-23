import Foundation
import Supabase

/// Listens for the scheduler's `poll_finished` broadcast on the public Realtime channel
/// `polls`. The payload (`{tick_at, updated, failed}`) is ignored: it's only a ping, and the
/// app refetches everything from FastAPI.
struct PollListener: Sendable {
    let client: SupabaseClient

    /// One element per finished tick, until the consumer stops iterating. The channel is
    /// joined on first iteration and removed when the stream ends. A failed join just ends
    /// the stream: live refresh is a nicety, and the hour slider still refetches by hand.
    func pings() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                let channel = client.channel("polls")
                let broadcasts = channel.broadcastStream(event: "poll_finished")
                do {
                    try await channel.subscribeWithError()
                    for await _ in broadcasts {
                        continuation.yield()
                    }
                } catch {}
                await client.removeChannel(channel)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
