import Foundation

/// What the contractor does.
///
/// Metadata only: nothing in MarginRun's financial model reads this. It exists
/// so a later release can personalise defaults and so the funnel can be read by
/// trade, and it is editable in Settings like every other preference.
nonisolated enum ContractorTrade: String, CaseIterable, Identifiable, Sendable {
    case generalContractor
    case remodeling
    case painting
    case landscaping
    case flooring
    case handyman
    case plumbing
    case electrical
    case roofing
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .generalContractor: "General Contractor"
        case .remodeling: "Remodeling"
        case .painting: "Painting"
        case .landscaping: "Landscaping"
        case .flooring: "Flooring"
        case .handyman: "Handyman"
        case .plumbing: "Plumbing"
        case .electrical: "Electrical"
        case .roofing: "Roofing"
        case .other: "Other"
        }
    }
}
