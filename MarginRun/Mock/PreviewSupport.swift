import SwiftData
import SwiftUI

enum PreviewSupport {
    static func container() -> ModelContainer {
        let schema = Schema([Job.self, Expense.self, LaborEntry.self, ExtraRevenue.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: configuration)
        MockData.insertSampleJobs(into: container.mainContext)
        return container
    }
}
