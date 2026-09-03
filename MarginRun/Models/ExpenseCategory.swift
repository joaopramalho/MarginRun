import Foundation

enum ExpenseCategory: String, Codable, CaseIterable, Identifiable {
    case materials
    case labor
    case subcontractors
    case equipment
    case travel
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .materials: "Materials"
        case .labor: "Labor"
        case .subcontractors: "Subcontractors"
        case .equipment: "Equipment"
        case .travel: "Travel"
        case .other: "Other"
        }
    }
}
