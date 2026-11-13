import Foundation

public enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case decodingError(Error)
    case networkError(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid request URL."
        case .invalidResponse:
            return "Invalid server response."
        case .httpError(let code):
            return "Server error (\(code))."
        case .decodingError(let error):
            return "Failed to parse data: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network connection failed: \(error.localizedDescription)"
        }
    }
}
