import Foundation
import JavaScriptCore

/// Runs the shared catalog parsers in a serial JavaScriptCore context. All
/// network I/O goes through URLSession, and no app credentials enter the context.
actor DirectMusicCatalog {
    private struct FetchOptions: Decodable {
        let method: String?
        let headers: [String: String]?
        let body: String?
    }

    private let session: URLSession
    private var context: JSContext?
    private var requests: [String: CheckedContinuation<Data, Error>] = [:]

    init(session: URLSession) {
        self.session = session
    }

    func load(path: String, query: [String: String]) async throws -> Data {
        let context = try loadContext()
        let payload = try JSONEncoder().encode(query)
        let id = UUID().uuidString
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                requests[id] = continuation
                context.objectForKeyedSubscript("startCatalogRequest")
                    .call(withArguments: [id, path, String(decoding: payload, as: UTF8.self)])
            }
        } onCancel: {
            Task { await self.finish(id: id, result: .failure(CancellationError())) }
        }
    }

    private func loadContext() throws -> JSContext {
        if let context { return context }
        guard let url = Bundle.main.url(forResource: "YouTubeMusicCatalog", withExtension: "js"),
              let context = JSContext() else { throw APIError.catalogUnavailable }

        let fetch: @convention(block) (Int32, String, String) -> Void = { [weak self] id, url, options in
            Task { await self?.fetch(id: id, address: url, options: options) }
        }
        let complete: @convention(block) (String, String, String) -> Void = { [weak self] id, payload, error in
            Task {
                let result: Result<Data, Error> = error.isEmpty
                    ? .success(Data(payload.utf8))
                    : .failure(APIError.upstream(error))
                await self?.finish(id: id, result: result)
            }
        }
        let decodeBase64: @convention(block) (String) -> String? = { input in
            var padded = input
            padded.append(String(repeating: "=", count: (4 - input.utf8.count % 4) % 4))
            guard let data = Data(base64Encoded: padded) else { return nil }
            return data.map { String(UnicodeScalar($0)) }.joined()
        }

        context.setObject(fetch, forKeyedSubscript: "nativeFetch" as NSString)
        context.setObject(complete, forKeyedSubscript: "nativeComplete" as NSString)
        context.setObject(decodeBase64, forKeyedSubscript: "atob" as NSString)
        context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
        guard context.exception == nil,
              context.objectForKeyedSubscript("startCatalogRequest")?.isObject == true else {
            throw APIError.catalogUnavailable
        }
        self.context = context
        return context
    }

    private func fetch(id: Int32, address: String, options: String) async {
        let reply = context?.objectForKeyedSubscript("completeFetch")
        do {
            guard let url = URL(string: address), url.scheme == "https", url.host == "music.youtube.com" else {
                throw APIError.catalogUnavailable
            }
            let options = try JSONDecoder().decode(FetchOptions.self, from: Data(options.utf8))
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.httpMethod = options.method ?? "GET"
            request.allHTTPHeaderFields = options.headers
            request.httpBody = options.body.map { Data($0.utf8) }
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            reply?.call(withArguments: [id, status, String(decoding: data, as: UTF8.self), ""])
        } catch {
            reply?.call(withArguments: [id, 0, "", error.localizedDescription])
        }
    }

    private func finish(id: String, result: Result<Data, Error>) {
        requests.removeValue(forKey: id)?.resume(with: result)
    }
}
