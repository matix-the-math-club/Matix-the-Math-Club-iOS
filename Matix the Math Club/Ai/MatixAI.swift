import Foundation

struct MatixSource: Sendable, Hashable {
    let title: String
    let url: URL
    let snippet: String
    let provider: String
}

enum MatixAI {
    private static let maxResults = 10
    private static let totalBudgetSeconds: TimeInterval = 2.8
    private static let googleSliceSeconds: TimeInterval = 2.2
    private static let perRequestTimeout: TimeInterval = 2.4

    static func search(_ query: String) async -> [MatixSource] {
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return [] }

        let started = Date()
        let googleResults = await withTimeout(seconds: googleSliceSeconds) {
            await google(cleaned)
        } ?? []
        if !googleResults.isEmpty {
            return googleResults
        }

        let elapsed = Date().timeIntervalSince(started)
        let remaining = totalBudgetSeconds - elapsed
        guard remaining > 0 else { return [] }
        return await withTimeout(seconds: min(remaining, 1.0)) {
            await duck(cleaned)
        } ?? []
    }

    static func solveMath(_ prompt: String) async -> [MatixSource] {
        await search("solve math problem \(prompt)")
    }

    static func lookupWeather(_ prompt: String) async -> [MatixSource] {
        await search("weather \(prompt)")
    }

    static func oneClickLessonSummary(_ prompt: String) async -> [MatixSource] {
        await search("lesson summary \(prompt)")
    }

    static func validateCoreFlowBudget() async -> Bool {
        await withinBudget { await solveMath("2x + 5 = 19") }
            && await withinBudget { await lookupWeather("in London today") }
            && await withinBudget { await oneClickLessonSummary("fractions for beginners") }
    }

    private static func withinBudget(_ action: @escaping @Sendable () async -> [MatixSource]) async -> Bool {
        let start = Date()
        _ = await action()
        return Date().timeIntervalSince(start) <= totalBudgetSeconds
    }

    static func google(_ query: String) async -> [MatixSource] {
        guard var components = URLComponents(string: "https://www.google.com/search") else { return [] }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "num", value: "10"),
            URLQueryItem(name: "hl", value: "en"),
            URLQueryItem(name: "gbv", value: "1")
        ]
        guard let url = components.url else { return [] }

        guard let html = await fetchHTML(from: url) else { return [] }
        return parseGoogleHTML(html)
    }

    static func duck(_ query: String) async -> [MatixSource] {
        guard var components = URLComponents(string: "https://duckduckgo.com/html/") else { return [] }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "kl", value: "us-en")
        ]
        guard let url = components.url else { return [] }

        guard let html = await fetchHTML(from: url) else { return [] }
        return parseDuckHTML(html)
    }

    private static func fetchHTML(from url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = perRequestTimeout
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private static func parseGoogleHTML(_ html: String) -> [MatixSource] {
        let pattern = #"<a href="/url\?q=([^"&]+)[^"]*"[^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)

        var out: [MatixSource] = []
        var seen = Set<String>()
        regex.enumerateMatches(in: html, options: [], range: range) { match, _, stop in
            guard let match,
                  let urlRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html) else { return }

            let encoded = String(html[urlRange])
            let decodedURL = encoded.removingPercentEncoding ?? encoded
            guard let finalURL = URL(string: decodedURL),
                  finalURL.scheme?.hasPrefix("http") == true else { return }

            let key = finalURL.absoluteString
            guard !seen.contains(key) else { return }
            seen.insert(key)

            let title = plainText(String(html[titleRange]))
            if title.isEmpty { return }
            out.append(MatixSource(title: title, url: finalURL, snippet: "", provider: "google"))
            if out.count >= maxResults { stop.pointee = true }
        }
        return out
    }

    private static func parseDuckHTML(_ html: String) -> [MatixSource] {
        let pattern = #"<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>(?:.|\n){0,420}?<a[^>]*class="result__snippet"[^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)

        var out: [MatixSource] = []
        var seen = Set<String>()
        regex.enumerateMatches(in: html, options: [], range: range) { match, _, stop in
            guard let match,
                  let urlRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html),
                  let snippetRange = Range(match.range(at: 3), in: html) else { return }

            let rawURL = String(html[urlRange])
            let decodedURL = rawURL.removingPercentEncoding ?? rawURL
            guard let finalURL = URL(string: decodedURL),
                  finalURL.scheme?.hasPrefix("http") == true else { return }

            let key = finalURL.absoluteString
            guard !seen.contains(key) else { return }
            seen.insert(key)

            let title = plainText(String(html[titleRange]))
            let snippet = plainText(String(html[snippetRange]))
            if title.isEmpty { return }
            out.append(MatixSource(title: title, url: finalURL, snippet: snippet, provider: "duck"))
            if out.count >= maxResults { stop.pointee = true }
        }
        return out
    }

    private static func plainText(_ html: String) -> String {
        let stripped = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let decoded = decodeEntities(stripped)
        return decoded
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeEntities(_ text: String) -> String {
        guard let data = text.data(using: .utf8) else { return text }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        return (try? NSAttributedString(data: data, options: options, documentAttributes: nil).string) ?? text
    }

    private static func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async -> T
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                let ns = UInt64(max(0, seconds) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
