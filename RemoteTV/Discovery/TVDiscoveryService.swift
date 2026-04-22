import Foundation

/// Abstracts the discovery layer so ``DiscoveryViewModel`` can be exercised against a fake
/// in unit tests.
///
/// ``discoveries()`` returns a fresh ``AsyncStream`` each time it's called; callers that stop
/// iterating the returned stream automatically release the backing continuation.
protocol TVDiscoveryService: Sendable {
    func discoveries() async -> AsyncStream<DiscoveredTV>
    func start() async
    func stop() async
}
