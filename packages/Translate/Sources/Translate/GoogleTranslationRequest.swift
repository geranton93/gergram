import Foundation

enum GoogleTranslationRequest {
    static func url(text: String, from: String?, to: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "translate.googleapis.com"
        components.path = "/translate_a/single"
        components.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: from ?? "auto"),
            URLQueryItem(name: "tl", value: to),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: text)
        ]
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }

    static func result(from data: Data) -> (detect: String?, result: String)? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let segments = json.first as? [[Any]] else {
            return nil
        }
        let translation = segments.compactMap { $0.first as? String }.joined()
        guard !translation.isEmpty else { return nil }
        let detected = json.indices.contains(2) ? json[2] as? String : nil
        return (detected, translation)
    }
}
