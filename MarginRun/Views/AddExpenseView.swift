import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct AddExpenseView: View {
    let job: Job
    let source: ExpenseCreationSource

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var subscriptions: SubscriptionStore
    @EnvironmentObject private var analytics: AnalyticsService

    @State private var category: ExpenseCategory = .materials
    @State private var amountText = ""
    @State private var vendor = ""
    @State private var note = ""
    @State private var expenseDate = Date()
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var receiptImageData: Data?
    @State private var isShowingCamera = false
    @State private var isScanningReceipt = false
    /// What the scan actually did, shown as feedback rather than as a step.
    /// `nil` until a scan finishes.
    @State private var scanMessage: String?
    @State private var scanGeneration = UUID()
    @State private var isSaving = false
    @State private var receiptErrorMessage: String?
    @State private var saveErrorMessage: String?
    @State private var paywallFeature: ProFeature?
    /// Where the current photo came from, so `receipt_attached` can say whether
    /// people shoot receipts on site or pick them up later from the library.
    @State private var receiptSource: ReceiptSource?

    private var parsedAmount: Decimal? {
        let trimmed = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return MoneyInput.parse(trimmed)
    }

    private var canSave: Bool {
        if
            !isSaving,
            !isScanningReceipt,
            job.status == .active,
            let parsedAmount,
            parsedAmount > 0
        {
            return true
        }
        return false
    }

    private var cameraButtonTitle: String {
        receiptImageData == nil ? "Take photo" : "Retake photo"
    }

    private var libraryButtonTitle: String {
        receiptImageData == nil ? "Choose from library" : "Replace from library"
    }

    var body: some View {
        NavigationStack {
            Form {
                receiptSection
                expenseFieldsSection
            }
            .keyboardEscapes()
            .navigationTitle("Add Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                loadPhoto(from: newItem)
            }
            .onChange(of: receiptImageData) { _, newData in
                // Attaching stays free; only the automatic extraction is Pro.
                // Free users type the fields and confirm as usual.
                if let newData, subscriptions.isUnlocked(.receiptScan) {
                    scanReceipt(newData)
                }
            }
            .proPaywall(for: $paywallFeature) { feature in
                // Buying Pro with a photo already attached should scan that
                // photo, not make the customer remove and re-add it.
                guard feature == .receiptScan, let receiptImageData else { return }
                scanReceipt(receiptImageData)
            }
            .fullScreenCover(isPresented: $isShowingCamera) {
                CameraImagePicker(imageData: $receiptImageData)
                    .ignoresSafeArea()
            }
            .alert(
                "Couldn’t save expense",
                isPresented: Binding(
                    get: { saveErrorMessage != nil },
                    set: { if !$0 { saveErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage ?? "The expense could not be saved.")
            }
        }
    }

    private var expenseFieldsSection: some View {
        Section("Expense") {
            Picker("Category", selection: $category) {
                ForEach(ExpenseCategory.allCases) { item in
                    Text(item.title).tag(item)
                }
            }

            CurrencyTextField(title: "Amount", text: $amountText)
            TextField("Vendor", text: $vendor)
            DatePicker("Date", selection: $expenseDate, displayedComponents: .date)
                .accessibilityIdentifier("expenseDatePicker")
            TextField("Note", text: $note)
        }
    }

    private var receiptSection: some View {
        Section {
            receiptPreview
            cameraButton

            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Label(libraryButtonTitle, systemImage: "photo.on.rectangle")
            }
            .accessibilityIdentifier("receiptLibraryButton")

            if !subscriptions.isUnlocked(.receiptScan), receiptImageData != nil {
                ProUpsellRow(
                    feature: .receiptScan,
                    title: "Scan this receipt automatically",
                    detail: "Pro fills in the vendor, total, and date from the photo."
                ) {
                    subscriptions.requirePro(.receiptScan, presenting: $paywallFeature)
                }
                .accessibilityIdentifier("receiptScanUpsell")
            }

            if isScanningReceipt {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Scanning receipt…")
                }
                .foregroundStyle(.secondary)
            } else if let scanMessage, receiptImageData != nil {
                // Feedback, not a gate. Saving is the human confirmation, so
                // the customer is told what was filled and left to review it.
                Text(scanMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("receiptScanMessage")
            }

            if let receiptErrorMessage {
                Text(receiptErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Receipt")
                .accessibilityIdentifier("receiptSectionHeader")
        } footer: {
            Text("MarginRun suggests the vendor, total, and date. Review before saving. Photos stay on this device.")
                .accessibilityIdentifier("receiptGuidanceFooter")
        }
    }

    @ViewBuilder
    private var receiptPreview: some View {
        if let receiptImageData, let receiptImage = UIImage(data: receiptImageData) {
            HStack(spacing: 14) {
                Image(uiImage: receiptImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Receipt attached")
                    }
                    .fontWeight(.medium)
                    .foregroundStyle(.green)

                    Button("Remove photo", role: .destructive) {
                        scanGeneration = UUID()
                        self.receiptImageData = nil
                        selectedPhotoItem = nil
                        receiptSource = nil
                        isScanningReceipt = false
                        scanMessage = nil
                        receiptErrorMessage = nil
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var cameraButton: some View {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            Button {
                receiptErrorMessage = nil
                receiptSource = .camera
                isShowingCamera = true
            } label: {
                Label(cameraButtonTitle, systemImage: "camera")
            }
        }
    }

    private func save() {
        guard job.status == .active, let parsedAmount, parsedAmount > 0 else { return }
        isSaving = true
        var savedReceiptFileName: String?

        do {
            if let receiptImageData {
                savedReceiptFileName = try ReceiptStorage.save(imageData: receiptImageData)
            }

            let expense = Expense(
                category: category,
                amount: parsedAmount,
                vendor: vendor.trimmingCharacters(in: .whitespacesAndNewlines),
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                receiptFileName: savedReceiptFileName,
                createdAt: expenseDate,
                job: job
            )
            modelContext.insert(expense)

            do {
                try modelContext.save()
            } catch {
                modelContext.delete(expense)
                throw error
            }

            // Reported after the save, never before: an expense that failed to
            // persist is not an expense the contractor added.
            if savedReceiptFileName != nil {
                analytics.track(.receiptAttached(source: receiptSource ?? .library))
            }
            analytics.trackExpenseAdded(
                category: category,
                hasReceipt: savedReceiptFileName != nil,
                source: source
            )
            dismiss()
        } catch {
            if let savedReceiptFileName {
                try? ReceiptStorage.delete(fileName: savedReceiptFileName)
            }
            saveErrorMessage = error.localizedDescription
            isSaving = false
        }
    }

    private func loadPhoto(from item: PhotosPickerItem?) {
        guard let item else { return }
        receiptErrorMessage = nil
        receiptSource = .library

        Task {
            do {
                guard
                    let data = try await item.loadTransferable(type: Data.self),
                    UIImage(data: data) != nil
                else {
                    throw ReceiptStorageError.invalidImage
                }
                receiptImageData = data
            } catch {
                selectedPhotoItem = nil
                receiptErrorMessage = error.localizedDescription
            }
        }
    }

    private func scanReceipt(_ imageData: Data) {
        let generation = UUID()
        scanGeneration = generation
        isScanningReceipt = true
        scanMessage = nil
        receiptErrorMessage = nil

        analytics.track(.receiptOCRStarted)

        Task {
            do {
                let result = try await ReceiptOCRService.scan(imageData: imageData)
                guard scanGeneration == generation, receiptImageData == imageData else { return }

                if let vendor = result.vendor { self.vendor = vendor }
                if let total = result.total { amountText = NSDecimalNumber(decimal: total).stringValue }
                if let date = result.date { expenseDate = date }

                // How many of the three fields the scanner actually filled — the
                // number is what tells us whether the feature is worth paying
                // for. The extracted values themselves never leave the device.
                let fieldsExtracted = [result.vendor != nil, result.total != nil, result.date != nil]
                    .filter { $0 }
                    .count
                analytics.track(
                    .receiptOCRCompleted(
                        outcome: fieldsExtracted > 0 ? .extracted : .nothingFound,
                        fieldsExtracted: fieldsExtracted
                    )
                )

                // Says what happened without asking for anything. A scan that
                // found nothing is the case worth naming — otherwise a blank
                // form after a photo reads as the feature having failed.
                scanMessage = fieldsExtracted > 0
                    ? "MarginRun filled the fields it could detect"
                    : "Nothing was filled automatically — enter the details manually"
            } catch {
                guard scanGeneration == generation, receiptImageData == imageData else { return }
                receiptErrorMessage = error.localizedDescription
                scanMessage = nil
                analytics.track(.receiptOCRCompleted(outcome: .failed, fieldsExtracted: 0))
            }

            guard scanGeneration == generation, receiptImageData == imageData else { return }
            isScanningReceipt = false
        }
    }
}
