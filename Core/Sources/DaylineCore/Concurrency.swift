extension Array where Element: Sendable {
    public func concurrentResults<Value: Sendable, Failure: Error>(
        _ transform: @escaping @Sendable (Element) async throws(Failure) -> Value
    ) async -> [Result<Value, Failure>] {
        await withTaskGroup(of: (Int, Result<Value, Failure>).self) { group in
            for (index, element) in enumerated() {
                group.addTask {
                    let result: Result<Value, Failure>
                    do throws(Failure) {
                        result = .success(try await transform(element))
                    } catch {
                        result = .failure(error)
                    }
                    return (index, result)
                }
            }
            var results = [Result<Value, Failure>?](repeating: nil, count: count)
            for await (index, result) in group {
                results[index] = result
            }
            return results.map { $0! }
        }
    }
}
