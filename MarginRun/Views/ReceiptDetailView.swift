import PhotosUI
import SwiftData
import SwiftUI
import UIKit

private struct ReceiptImageDraft: Identifiable {
    let id = UUID()
    let data: Data
}

struct ReceiptDetailView: View {
    let expense: Expense
    let allowsEditing: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var imageStatusMessage: String?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var capturedImageData: Data?
    @State private var isShowingCamera = false
    @State private var replacementDraft: ReceiptImageDraft?
    @State private var replacementErrorMessage: String?
    @State private var reloadToken = UUID()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    receiptImage
                    receiptDetails

                    if allowsEditing {
                        replacementControls
                    }
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: reloadToken) { loadImage() }
            .onChange(of: selectedPhotoItem) { _, item in loadPhoto(from: item) }
            .onChange(of: capturedImageData) { _, data in
                if let data { replacementDraft = ReceiptImageDraft(data: data) }
            }
            .fullScreenCover(isPresented: $isShowingCamera) {
                CameraImagePicker(imageData: $capturedImageData)
                    .ignoresSafeArea()
            }
            .sheet(item: $replacementDraft) { draft in
                ReceiptReplacementReviewView(expense: expense, imageData: draft.data) {
                    capturedImageData = nil
                    selectedPhotoItem = nil
                    reloadToken = UUID()
                }
            }
            .alert(
                "Couldn’t load photo",
                isPresented: Binding(
                    get: { replacementErrorMessage != nil },
                    set: { if !$0 { replacementErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(replacementErrorMessage ?? "The selected image could not be loaded.")
            }
        }
    }

    @ViewBuilder
    private var receiptImage: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, minHeight: 260, maxHeight: 520)
                .background(Color.black.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            ContentUnavailableView(
                "Receipt unavailable",
                systemImage: "doc.text.image",
                description: Text(imageStatusMessage ?? "The receipt image could not be opened.")
            )
            .frame(maxWidth: .infinity, minHeight: 280)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var receiptDetails: some View {
        VStack(spacing: 0) {
            detailRow("Vendor", expense.vendor.isEmpty ? "Not provided" : expense.vendor)
            Divider()
            detailRow("Amount", MoneyFormat.usd(expense.amount))
            Divider()
            detailRow("Date", expense.createdAt.formatted(date: .abbreviated, time: .omitted))
            Divider()
            detailRow("Category", expense.category.title)
            Divider()
            detailRow("Note", expense.note.isEmpty ? "No note" : expense.note)
        }
        .padding(.horizontal)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
        .padding(.vertical, 14)
    }

    private var replacementControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Replace receipt")
                .font(.headline)

            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    isShowingCamera = true
                } label: {
                    Label("Take new photo", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Label("Choose from library", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private func loadImage() {
        guard let fileName = expense.receiptFileName else {
            image = nil
            imageStatusMessage = "This expense has no receipt attached."
            return
        }

        image = ReceiptStorage.image(fileName: fileName)
        if image == nil {
            imageStatusMessage = ReceiptStorage.fileExists(fileName: fileName)
                ? "The local JPEG is corrupted. Replace it to restore this receipt."
                : "The local JPEG is missing. Replace it to restore this receipt."
        } else {
            imageStatusMessage = nil
        }
    }

    private func loadPhoto(from item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            do {
                guard
                    let data = try await item.loadTransferable(type: Data.self),
                    UIImage(data: data) != nil
                else {
                    throw ReceiptStorageError.invalidImage
                }
                replacementDraft = ReceiptImageDraft(data: data)
            } catch {
                selectedPhotoItem = nil
                replacementErrorMessage = error.localizedDescription
            }
        }
    }
}

private struct ReceiptReplacementReviewView: View {
    let expense: Expense
    let imageData: Data
    let onReplaced: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var category: ExpenseCategory
    @State private var amountText: String
    @State private var vendor: String
    @State private var note: String
    @State private var expenseDate: Date
    @State private var isScanning = true
    @State private var isSaving = false
    @State private var scanMessage: String?
    @State private var saveErrorMessage: String?

    init(expense: Expense, imageData: Data, onReplaced: @escaping () -> Void) {
        self.expense = expense
        self.imageData = imageData
        self.onReplaced = onReplaced
        _category = State(initialValue: expense.category)
        _amountText = State(initialValue: NSDecimalNumber(decimal: expense.amount).stringValue)
        _vendor = State(initialValue: expense.vendor)
        _note = State(initialValue: expense.note)
        _expenseDate = State(initialValue: expense.createdAt)
    }

    private var parsedAmount: Decimal? {
        MoneyInput.parse(amountText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var canConfirm: Bool {
        !isScanning && !isSaving && (parsedAmount ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let image = UIImage(data: imageData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 240)
                    }

                    if isScanning {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Scanning receipt…")
                        }
                        .foregroundStyle(.secondary)
                    } else {
                        Label(
                            scanMessage ?? "Review every field before confirming",
                            systemImage: "checkmark.circle"
                        )
                        .foregroundStyle(.secondary)
                    }
                }

                Section("Receipt details") {
                    TextField("Vendor", text: $vendor)
                    CurrencyTextField(title: "Amount", text: $amountText)
                    DatePicker("Date", selection: $expenseDate, displayedComponents: .date)
                    Picker("Category", selection: $category) {
                        ForEach(ExpenseCategory.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    TextField("Note", text: $note)
                }
            }
            .keyboardEscapes()
            .navigationTitle("Review Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Confirm") { replaceReceipt() }
                        .disabled(!canConfirm)
                }
            }
            .task { await scanReceipt() }
            .alert(
                "Couldn’t replace receipt",
                isPresented: Binding(
                    get: { saveErrorMessage != nil },
                    set: { if !$0 { saveErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage ?? "The receipt could not be replaced.")
            }
        }
    }

    private func scanReceipt() async {
        do {
            let result = try await ReceiptOCRService.scan(imageData: imageData)
            if let detectedVendor = result.vendor { vendor = detectedVendor }
            if let detectedTotal = result.total {
                amountText = NSDecimalNumber(decimal: detectedTotal).stringValue
            }
            if let detectedDate = result.date { expenseDate = detectedDate }
            scanMessage = "MarginRun filled the fields it could detect"
        } catch {
            scanMessage = "Nothing was filled automatically — enter the details manually"
        }
        isScanning = false
    }

    private func replaceReceipt() {
        guard let parsedAmount, parsedAmount > 0 else { return }
        isSaving = true

        let oldCategory = expense.category
        let oldAmount = expense.amount
        let oldVendor = expense.vendor
        let oldNote = expense.note
        let oldDate = expense.createdAt
        let oldFileName = expense.receiptFileName
        var newFileName: String?

        do {
            let savedFileName = try ReceiptStorage.save(imageData: imageData)
            newFileName = savedFileName

            expense.category = category
            expense.amount = parsedAmount
            expense.vendor = vendor.trimmingCharacters(in: .whitespacesAndNewlines)
            expense.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
            expense.createdAt = expenseDate
            expense.receiptFileName = savedFileName
            try modelContext.save()

            try ExpenseReceiptCleanup.deleteReceipt(fileName: oldFileName)
            onReplaced()
            dismiss()
        } catch {
            expense.category = oldCategory
            expense.amount = oldAmount
            expense.vendor = oldVendor
            expense.note = oldNote
            expense.createdAt = oldDate
            expense.receiptFileName = oldFileName
            try? modelContext.save()
            if let newFileName { try? ReceiptStorage.delete(fileName: newFileName) }

            saveErrorMessage = "The original receipt was kept. \(error.localizedDescription)"
            isSaving = false
        }
    }
}
