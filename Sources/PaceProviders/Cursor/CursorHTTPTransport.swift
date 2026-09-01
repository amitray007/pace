import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

struct CursorHTTPResponse: Sendable {
    let statusCode: Int
    let headers: [String: String]
    let body: Data

    init(statusCode: Int, headers: [String: String] = [:], body: Data) {
        self.statusCode = statusCode
        self.headers = Dictionary(uniqueKeysWithValues: headers.map { key, value in
            (key.lowercased(), value)
        })
        self.body = body
    }

    func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

protocol CursorHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> CursorHTTPResponse
}

struct CursorURLSessionTransport: CursorHTTPTransport {
    static let maximumResponseSize = 1_048_576
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        session = URLSession(
            configuration: configuration,
            delegate: CursorRedirectBlocker(),
            delegateQueue: nil,
        )
    }

    func send(_ request: URLRequest) async throws -> CursorHTTPResponse {
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else {
            bytes.task.cancel()
            throw CursorProviderError.invalidResponse
        }
        let data: Data
        do {
            data = try await Self.boundedData(from: bytes, maximumSize: Self.maximumResponseSize)
        } catch {
            bytes.task.cancel()
            throw error
        }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { values, entry in
            guard let key = entry.key as? String else {
                return
            }
            values[key] = String(describing: entry.value)
        }
        return CursorHTTPResponse(
            statusCode: response.statusCode,
            headers: headers,
            body: data,
        )
    }

    static func boundedData<Bytes: AsyncSequence>(
        from bytes: Bytes,
        maximumSize: Int,
    ) async throws -> Data where Bytes.Element == UInt8 {
        var data = Data()
        data.reserveCapacity(min(maximumSize, 65536))
        for try await byte in bytes {
            guard data.count < maximumSize else {
                throw CursorProviderError.invalidResponse
            }
            data.append(byte)
        }
        return data
    }
}

private final class CursorRedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void,
    ) {
        completionHandler(nil)
    }
}
