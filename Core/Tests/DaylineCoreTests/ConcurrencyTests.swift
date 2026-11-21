import DaylineCore
import Testing

struct ConcurrencyTests {
    struct Odd: Error, Equatable {
        let value: Int
    }

    @Test func concurrentResultsKeepTheInputOrderWhenLaterItemsFinishFirst() async {
        let results = await [0, 1, 2, 3].concurrentResults { (value: Int) async throws(Odd) -> String in
            try? await Task.sleep(for: .milliseconds(40 - value * 10))
            guard value.isMultiple(of: 2) else { throw Odd(value: value) }
            return "item \(value)"
        }

        #expect(results.map { try? $0.get() } == ["item 0", nil, "item 2", nil])
        #expect(results.map { result in
            guard case .failure(let error) = result else { return nil }
            return error.value
        } == [nil, 1, nil, 3])
    }
}
