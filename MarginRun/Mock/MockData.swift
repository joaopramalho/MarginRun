import Foundation
import SwiftData

enum MockData {
    static func seedIfEmpty(context: ModelContext) throws {
        let descriptor = FetchDescriptor<Job>()
        let existing = try context.fetch(descriptor)
        guard existing.isEmpty else { return }
        insertSampleJobs(into: context)
        try context.save()
    }

    static func insertSampleJobs(into context: ModelContext) {
        // Three completed jobs, not one. Insights only compares once there is
        // something to compare against: a single completed job takes the
        // "comparison pending" branch, so best/worst, biggest miss and the
        // cost pattern never render. The three below are also deliberately
        // *different* — one over budget, one under, one badly overrun — so the
        // comparison has a real shape instead of three near-identical rows.
        context.insert(kitchenRemodelJob())
        context.insert(bathroomRetileJob())
        context.insert(garageConversionJob())

        let fence = Job(
            name: "Backyard fence",
            customerName: "Rivera Family",
            contractValue: 4_800,
            targetMargin: 30,
            estimatedMaterials: 2_100,
            estimatedLabor: 1_200,
            estimatedSubcontractors: 0,
            estimatedEquipment: 150,
            estimatedOther: 50
        )
        context.insert(fence)
    }

    /// Matches the product example: $18,000 contract, $11,500 estimated, $12,900 actual.
    static func kitchenRemodelJob() -> Job {
        let job = Job(
            name: "Kitchen remodel",
            customerName: "Chen Residence",
            contractValue: 18_000,
            targetMargin: 35,
            estimatedMaterials: 5_000,
            estimatedLabor: 4_000,
            estimatedSubcontractors: 1_500,
            estimatedEquipment: 700,
            estimatedOther: 300
        )

        job.expenses = [
            Expense(category: .materials, amount: 5_800, vendor: "Home Depot", note: "Cabinets and hardware", job: job),
            Expense(category: .subcontractors, amount: 1_600, vendor: "Lopez Electric", note: "Electrical rough-in", job: job),
            Expense(category: .equipment, amount: 700, vendor: "Sunbelt Rentals", note: "Tile saw", job: job),
            Expense(category: .travel, amount: 200, vendor: "", note: "Jobsite trips", job: job),
            Expense(category: .other, amount: 100, vendor: "Dump fees", note: "", job: job),
        ]

        job.laborEntries = [
            LaborEntry(hours: 90, hourlyCost: 50, job: job)
        ]

        job.complete(at: .now.addingTimeInterval(-6 * 24 * 60 * 60))

        return job
    }

    /// Came in under every category. The "best completed job" in Insights, and
    /// the reason the comparison is not uniformly grim.
    ///
    /// $9,500 contract, $6,100 estimated, $5,690 actual.
    static func bathroomRetileJob() -> Job {
        let job = Job(
            name: "Bathroom retile",
            customerName: "Alvarez Residence",
            contractValue: 9_500,
            targetMargin: 30,
            estimatedMaterials: 2_800,
            estimatedLabor: 2_400,
            estimatedSubcontractors: 600,
            estimatedEquipment: 200,
            estimatedOther: 100
        )

        job.expenses = [
            Expense(category: .materials, amount: 2_650, vendor: "Floor & Decor", note: "Porcelain and grout", job: job),
            Expense(category: .subcontractors, amount: 600, vendor: "Nakamura Plumbing", note: "Valve relocation", job: job),
            Expense(category: .equipment, amount: 180, vendor: "Sunbelt Rentals", note: "Wet saw", job: job),
            Expense(category: .other, amount: 60, vendor: "Dump fees", note: "", job: job),
        ]

        job.laborEntries = [
            LaborEntry(hours: 44, hourlyCost: 50, job: job)
        ]

        job.complete(at: .now.addingTimeInterval(-13 * 24 * 60 * 60))

        return job
    }

    /// The one that got away. Labor ran 33% past estimate and took the margin
    /// with it — this is the job the "biggest miss vs estimate" row points at,
    /// and half of why Labor is the most over-budget category.
    ///
    /// $12,000 contract, $8,400 estimated, $10,480 actual.
    static func garageConversionJob() -> Job {
        let job = Job(
            name: "Garage conversion",
            customerName: "Okafor Residence",
            contractValue: 12_000,
            targetMargin: 30,
            estimatedMaterials: 4_200,
            estimatedLabor: 3_600,
            estimatedSubcontractors: 0,
            estimatedEquipment: 400,
            estimatedOther: 200
        )

        job.expenses = [
            Expense(category: .materials, amount: 4_900, vendor: "84 Lumber", note: "Framing and drywall", job: job),
            Expense(category: .equipment, amount: 520, vendor: "United Rentals", note: "Concrete grinder", job: job),
            Expense(category: .travel, amount: 160, vendor: "", note: "Jobsite trips", job: job),
            Expense(category: .other, amount: 100, vendor: "Permit office", note: "", job: job),
        ]

        job.laborEntries = [
            LaborEntry(hours: 96, hourlyCost: 50, job: job)
        ]

        job.complete(at: .now.addingTimeInterval(-21 * 24 * 60 * 60))

        return job
    }
}
