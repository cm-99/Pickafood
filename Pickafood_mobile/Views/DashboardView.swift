import SwiftUI
import PhotosUI
import CoreData
import CoreImage
import UIKit

// Główny ekran: historia posiłków oraz ich podsumowanie dla wybranego dnia i przyciski akcji.
struct DashboardView: View {
    @StateObject private var vm: DashboardViewModel
    @StateObject private var pendingMgr = PendingDataManager.shared

    @State private var pickerItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var showARCapture = false

    @State private var selectedDate: Date = Date()
    @State private var showingDatePicker = false

    let context: NSManagedObjectContext
    init(context: NSManagedObjectContext) {
        _vm = StateObject(wrappedValue: DashboardViewModel(context: context))
        self.context = context
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                HistoryList(vm: vm, date: selectedDate)
                    .padding(.bottom, 64)

                BottomActionBar(
                    onTakePhotoTapped: { showARCapture = true },
                    photoPickerItem: $pickerItem
                )
            }
            .navigationTitle(navigationTitle(for: selectedDate))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                     NavigationLink {
                         PendingListView(context: context)
                     } label: {
                         HStack(spacing: 6) {
                             Image(systemName: "tray").tint(.brandPrimary)
                             if !pendingMgr.samples.isEmpty {
                                 Text("\(pendingMgr.samples.count)")
                                     .font(.subheadline).monospacedDigit()
                             }
                         }
                     }
                 }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingDatePicker = true } label: { Image(systemName: "calendar").tint(.brandPrimary) }
                }
            }
            .onAppear { vm.fetchHistory() }
            .sheet(isPresented: $showARCapture) {
                ARCaptureScreen { payload in
                    Task {
                        showARCapture = false
                        selectedImage = payload.image
                        await vm.startAnalysis(with: payload)
                    }
                }
            }
            .sheet(isPresented: $showingDatePicker) {
                NavigationStack {
                    VStack {
                        DatePicker("Wybierz dzień", selection: $selectedDate, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .padding()
                            .tint(.brandPrimary)
                        Spacer()
                    }
                    .navigationTitle("Wybór daty")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Gotowe") { showingDatePicker = false }
                        }
                    }
                }
            }
            .onChange(of: pickerItem) { newItem in
                guard let item = newItem else { return }
                Task {
                    defer { pickerItem = nil }
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let rawImg = UIImage(data: data) else {
                        vm.startErrorMsg = "Nie udało się wczytać obrazu z galerii."
                        return
                    }
                    let uiImg = rawImg.normalizedUp()
                    selectedImage = uiImg
                    await vm.startAnalysisFromGallery(jpegData: data, image: uiImg)
                }
            }
            .navigationDestination(isPresented: $vm.shouldShowProgress) {
                if let img = selectedImage, let tid = vm.currentTaskID {
                    ProgressViewScreen(
                        image: img,
                        viewModel: ProgressViewModel(taskID: tid),
                        dashboardVM: vm
                    )
                } else {
                    Text("Brak danych do wyświetlenia.")
                }
            }
            .alert("Nie udało się rozpocząć analizy", isPresented: .init(
                get: { vm.startErrorMsg != nil },
                set: { _ in vm.startErrorMsg = nil }
            )) {
                Button("OK", role: .cancel) { vm.startErrorMsg = nil }
            } message: {
                Text(vm.startErrorMsg ?? "")
            }
        }
    }

    private func navigationTitle(for date: Date) -> String {
        if Calendar.current.isDateInToday(date)     { return "Dzisiaj" }
        if Calendar.current.isDateInYesterday(date) { return "Wczoraj" }
        let df = DateFormatter(); df.dateStyle = .medium
        return df.string(from: date)
    }
}

private struct HistoryList: View {
    @ObservedObject var vm: DashboardViewModel
    let date: Date
    var body: some View {
        List {
            Section { DaySummary(meals: mealsForDate)
            }
            Section(header: Text("Historia")) {
                ForEach(mealsForDate) { meal in
                    NavigationLink {
                        LocalResultView(historyItem: meal,
                                        viewModel: vm,
                                        onUpdate: { vm.fetchHistory() })
                    } label: {
                        HistoryRow(meal: meal)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { vm.delete(meal) } label: {
                            Label("Usuń", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
    private var mealsForDate: [LocalMealHistoryItem] {
        vm.history.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }
}

private struct DaySummary: View {
    let meals: [LocalMealHistoryItem]
    var body: some View {
        let sum = meals.reduce((0.0,0.0,0.0,0.0)) { acc, m in
            (acc.0 + m.calories, acc.1 + m.protein, acc.2 + m.fat, acc.3 + m.carbs)
        }
        VStack(alignment: .leading, spacing: 8) {
            Text("Zjedzono:").font(.title3).fontWeight(.medium)

            HStack(alignment: .top) {
                Spacer().frame(maxWidth: .infinity)

                VStack(spacing: 2) {
                    Text("\(Int(sum.0)) kcal")
                        .font(.system(size: 28, weight: .bold))
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                    Text("kalorie")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                Spacer().frame(maxWidth: .infinity)
            }

            HStack(alignment: .top) {
                VStack(spacing: 2) {
                    Text("\(Int(sum.1)) g")
                        .font(.headline)
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                    Text("białko")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 2) {
                    Text("\(Int(sum.2)) g")
                        .font(.headline)
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                    Text("tłuszcz")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 2) {
                    Text("\(Int(sum.3)) g")
                        .font(.headline)
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                    Text("węglowodany")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
    }
}

private struct HistoryRow: View {
    let meal: LocalMealHistoryItem
    var body: some View {
        HStack(spacing: 12) {
            if let fname = meal.thumbnailName,
               let img = loadThumb(named: fname) {
                Image(uiImage: img)
                    .resizable()
                    .frame(width: 54, height: 54)
                    .cornerRadius(10)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.summary).font(.headline)
                Text(dateFormatter.string(from: meal.date)).font(.caption)
                HStack(spacing: 1) {
                    MetricTile(value: Int(meal.calories),  unit: "kcal",    label: "kalorie")
                    MetricTile(value: Int(meal.protein),  unit: "g",    label: "białko")
                    MetricTile(value: Int(meal.fat),      unit: "g",    label: "tłuszcz")
                    MetricTile(value: Int(meal.carbs),    unit: "g",    label: "węglowodany")
                }.font(.caption2)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func loadThumb(named fileNameOrPath: String) -> UIImage? {
        if fileNameOrPath.contains("/") {
            return UIImage(contentsOfFile: fileNameOrPath)
        } else {
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(fileNameOrPath)
            return UIImage(contentsOfFile: url.path)
        }
    }
    
    private struct MetricTile: View {
        let value: Int
        let unit: String
        let label: String
        var body: some View {
            VStack() {
                Text("\(value) \(unit)")
                    .font(.system(size: 12, weight: .bold))
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                Text(label)
                    .font(.system(size: 8, weight: .light))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct BottomActionBar: View {
    let onTakePhotoTapped: () -> Void
    @Binding var photoPickerItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 10) {
            Text("Analizuj posiłek").font(.headline)
            HStack(spacing: 12) {
                Button(action: onTakePhotoTapped) {
                    Label {
                        Text("Zrób zdjęcie")
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.9) 
                            .allowsTightening(true)
                    } icon: {
                        Image(systemName: "camera")
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.brandPrimary)

                PhotosPicker(selection: $photoPickerItem, matching: .images, photoLibrary: .shared()) {
                        Label {
                            Text("Wybierz z galerii")
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .minimumScaleFactor(0.9)
                                .allowsTightening(true)
                        } icon: {
                            Image(systemName: "photo")
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brandPrimary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}

private let dateFormatter: DateFormatter = {
    let df = DateFormatter()
    df.dateStyle = .medium
    df.timeStyle = .short
    return df
}()
