import Foundation

enum JobStatus: String, Codable, CaseIterable, Identifiable {
    case active
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: "Active"
        case .completed: "Completed"
        }
    }
}
