import SwiftUI
import CoreData
import UIKit

struct PendingListView: View {
    @StateObject private var mgr = PendingDataManager.shared
    
    @State private var alertMessage: String?
    @State private var uploadingIDs: Set<String> = []
    
    let context: NSManagedObjectContext
    init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    // Nawigacja do Progress
    @State private var goToProgress = false
    @State private var currentTaskID: String?
    @State private var selectedSample: PendingSample?

    var body: some View {
        NavigationStack {
            mainContent
                .alert("Błąd wysyłki", isPresented: Binding(
                    get: { alertMessage != nil },
                    set: { show in if !show { alertMessage = nil } }
                )) {
                    Button("OK", role: .cancel) { alertMessage = nil }
                } message: {
                    Text(alertMessage ?? "")
                }
                .background(progressNavigationLink)
                .toolbar{topToolbar}
        }
    }

private var progressNavigationLink: some View {
    NavigationLink(isActive: $goToProgress) {
        if let taskID = currentTaskID, let sample = selectedSample {
            ProgressViewScreen(
                image: UIImage(contentsOfFile: sample.rgbPath) ?? UIImage(),
                viewModel: ProgressViewModel(taskID: taskID),
                dashboardVM: DashboardViewModel(context: context),
                pendingSampleID: sample.id
            )
        } else {
            EmptyView()
        }
    } label: {
        EmptyView()
    }
}

    @ViewBuilder
        private var mainContent: some View {
            if mgr.samples.isEmpty {
                EmptyStateView()
            } else {
                SamplesListView(
                    samples: mgr.samples,
                    uploadingIDs: uploadingIDs,
                    onUpload: { s in uploadSample(s) },
                    onDelete: { s in mgr.remove(s, deleteFiles: true) },
                    onDeleteIndices: { indexSet in
                        indexSet
                            .map { mgr.samples[$0] }
                            .forEach { mgr.remove($0, deleteFiles: true) }
                    }
                )
            }
        }

        private var topToolbar: some ToolbarContent {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !mgr.samples.isEmpty {
                    Button {
                        Task { await uploadAll() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.circle")
                            Text("Wyślij wszystko")
                        }
                    }
                    .disabled(!uploadingIDs.isEmpty)
                }
            }
        }

    private struct EmptyStateView: View {
        var body: some View {
            VStack(spacing: 12) {
                Image(systemName: "tray")
                    .font(.system(size: 52, weight: .light))
                    .foregroundColor(.secondary)
                Text("Brak próbek oczekujących na wysyłkę")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text("Zrób zdjęcie w trybie offline, a pojawi się tutaj.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 40)
        }
    }

    private struct SamplesListView: View {
        let samples: [PendingSample]
        let uploadingIDs: Set<String>
        let onUpload: (PendingSample) -> Void
        let onDelete: (PendingSample) -> Void
        let onDeleteIndices: (IndexSet) -> Void

        var body: some View {
            List {
                ForEach(samples) { s in
                    PendingRow(
                        sample: s,
                        isUploading: uploadingIDs.contains(s.id),
                        onUpload: { onUpload(s) },
                        onDelete: { onDelete(s) }
                    )
                }
                .onDelete(perform: onDeleteIndices)
            }
            .listStyle(.insetGrouped)
        }
    }
    
    private func uploadSample(_ sample: PendingSample) {
        guard !uploadingIDs.contains(sample.id) else { return }
        uploadingIDs.insert(sample.id)

        Task {
            await mgr.upload(
                sample,
                onPresentProgress: { taskID in
                    Task { @MainActor in
                        self.currentTaskID = taskID
                        self.selectedSample = sample
                        self.goToProgress = true
                        self.uploadingIDs.remove(sample.id)
                    }
                },
                onError: { msg in
                    Task { @MainActor in
                        if msg.contains("403") || msg.localizedCaseInsensitiveContains("forbidden") {
                            self.alertMessage = "Nie udało się nawiązać połączenia z serwerem."
                        } else if msg.localizedCaseInsensitiveContains("timed out") {
                            self.alertMessage = "Przekroczono czas oczekiwania na serwer."
                        } else {
                            self.alertMessage = msg
                        }
                        self.uploadingIDs.remove(sample.id)
                    }
                }
            )
        }
    }

    private func uploadAll() async {
        for s in mgr.samples {
            if uploadingIDs.contains(s.id) { continue }
            uploadingIDs.insert(s.id)
            await mgr.upload(s, onPresentProgress: { taskID in
                if self.currentTaskID == nil {
                    self.currentTaskID = taskID
                    self.selectedSample = s
                    self.goToProgress = true
                }
                self.uploadingIDs.remove(s.id)
            }, onError: { msg in
                self.alertMessage = msg
                self.uploadingIDs.remove(s.id)
            })
        }
    }
}

private struct PendingRow: View {
    let sample: PendingSample
    let isUploading: Bool
    let onUpload: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            thumb
                .resizable()
                .frame(width: 60, height: 60)
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.1)))
                .shadow(radius: 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(filename(sample.rgbPath))
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 12) {
                    Label("\(sample.width)×\(sample.height)", systemImage: "photo")
                    Label(dateString(sample.createdAt), systemImage: "calendar")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            if isUploading {
                ProgressView().frame(width: 24, height: 24)
            } else {
                Button(action: onUpload) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                }
                .buttonStyle(.plain)
            }

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private var thumb: Image {
        if let t = sample.thumbnailPath,
           let ui = UIImage(contentsOfFile: t) {
            return Image(uiImage: ui)
        }
        if let ui = UIImage(contentsOfFile: sample.rgbPath) {
            return Image(uiImage: ui)
        }
        return Image(systemName: "photo")
    }

    private func filename(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    private func dateString(_ d: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: d)
    }
}
