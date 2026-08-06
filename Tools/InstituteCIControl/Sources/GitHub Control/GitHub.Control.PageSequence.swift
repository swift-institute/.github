import GitHub
import GitHub_HTTP

extension GitHub.Control {
    /// Complete pagination for control-plane reads: drives a page-fetch
    /// closure to exhaustion and refuses to surface a partial collection
    /// silently — an interrupted traversal is a typed error, never a
    /// shorter list (complete-pagination rule; C-12).
    public enum PageSequence {
        public enum Error<Underlying: Swift.Error>: Swift.Error {
            case page(number: Int, underlying: Underlying)
            case exceededPageBudget(Int)
        }

        /// Fetches every page. `fetch` returns the page's items plus the
        /// next page number (nil when exhausted, from the canonical Link
        /// witness). `pageBudget` bounds runaway traversal; hitting it is
        /// an error, never a truncation.
        public static func all<Item, Underlying: Swift.Error>(
            pageBudget: Int = 1000,
            fetch: (Int) async throws(Underlying) -> (items: [Item], next: Int?)
        ) async throws(Error<Underlying>) -> [Item] {
            var items: [Item] = []
            var page = 1
            var fetched = 0
            while true {
                guard fetched < pageBudget else {
                    throw .exceededPageBudget(pageBudget)
                }
                let result: (items: [Item], next: Int?)
                do {
                    result = try await fetch(page)
                } catch {
                    throw .page(number: page, underlying: error)
                }
                items += result.items
                fetched += 1
                guard let next = result.next else { return items }
                page = next
            }
        }
    }
}
