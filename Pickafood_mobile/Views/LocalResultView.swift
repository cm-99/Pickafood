import SwiftUI

// Podgląd wyniku zapisanego lokalnie (CoreData). Pozwala wejść w edycję
// (zmiana nazwy, mas, usuwanie składników) i zapisać korekty w bazie.
struct LocalResultView: View {
    let historyItem: LocalMealHistoryItem
    var onUpdate: (() -> Void)? = nil
    @ObservedObject var viewModel: DashboardViewModel

    @State private var draft: LocalMealHistoryItem
    @State private var isEditing = false
    @State private var showValidationError = false
    @State private var validationMessage = ""
    @State private var draftBackup: LocalMealHistoryItem?

    init(historyItem: LocalMealHistoryItem, viewModel: DashboardViewModel, onUpdate: (() -> Void)? = nil) {
        self.historyItem = historyItem
        self.viewModel = viewModel
        self.onUpdate = onUpdate
        _draft = State(initialValue: historyItem)
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack{
                    VStack(alignment: .leading, spacing: 18) {
                        HStack{
                            Spacer()
                            Text(draft.summary.isEmpty ? "Posiłek" : draft.summary)
                                .font(.title)
                                .fontWeight(.semibold)
                                .multilineTextAlignment(.center)
                                .padding(.top, 6)
                            Spacer()
                        }
                        
                        VStack(spacing: 10) {
                            HStack{
                                Spacer()
                                MetricTile(value: Int(totalCalories), unit: "kcal", label: "kalorie")
                                Spacer()
                            }
                            HStack(spacing: 12) {
                                MetricTile(value: Int(totalProtein),  unit: "g",    label: "białko")
                                MetricTile(value: Int(totalFat),      unit: "g",    label: "tłuszcz")
                                MetricTile(value: Int(totalCarbs),    unit: "g",    label: "węglowodany")
                            }
                        }
                        .padding(.top, 2)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.brandPrimary.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.brandPrimary.opacity(0.25), lineWidth: 1)
                    )
                    
                    HStack {
                        Text("SKŁADNIKI")
                            .font(.caption2)
                        Spacer()
                    }
                    
                    ForEach(draft.rawResult.meal.indices, id: \.self) { idx in
                        let c = draft.rawResult.meal[idx]

                        VStack(spacing: 10) {
                            Text(c.name)
                                .font(.headline)
                                .multilineTextAlignment(.center)

                            if isEditing {
                                HStack(spacing: 8) {
                                    Text("masa (g):")
                                    TextField("masa",
                                              value: $draft.rawResult.meal[idx].mass_g,
                                              formatter: numberFormatter)
                                        .keyboardType(.decimalPad)
                                        .frame(width: 90)
                                        .textFieldStyle(.roundedBorder)
                                }
                            }

                            HStack {
                                Spacer()
                                MetricTile(
                                    value: Int(draft.rawResult.meal[idx].mass_g.rounded()),
                                    unit: "g",
                                    label: "masa"
                                )
                                .frame(maxWidth: 140) // kompaktowa szerokość kafelka
                                Spacer()
                            }

                            HStack(spacing: 12) {
                                MetricTile(value: Int(c.calories_kcal), unit: "kcal", label: "kalorie")
                                MetricTile(value: Int(c.protein_g),     unit: "g",    label: "białko")
                                MetricTile(value: Int(c.fat_g),         unit: "g",    label: "tłuszcz")
                                MetricTile(value: Int(c.carbs_g),       unit: "g",    label: "węglowodany")
                            }

                            // Usuwanie składnika w trybie edycji
                            if isEditing {
                                Button {
                                    draft.rawResult.meal.remove(at: idx)
                                } label: {
                                    Label("", systemImage: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 8)

                        Divider()
                    }

                    if showValidationError {
                        Text(validationMessage).foregroundColor(.red)
                    }

                    Spacer(minLength: 90)
                }
                .padding([.horizontal, .top])
            }

            VStack {
                Spacer()
                HStack(spacing: 12) {
                    if isEditing {
                        Button {
                            if validateAll() {
                                saveEdits()
                                isEditing = false
                            }
                        } label: {
                            Label {
                                Text("Zapisz zmiany")
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .minimumScaleFactor(0.9)
                                    .allowsTightening(true)
                            } icon: {
                                Image(systemName: "checkmark.circle.fill")
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.brandPrimary)
                        
                        Button {
                            restoreEdits()
                            isEditing = false
                        } label: {
                            Label {
                                Text("Anuluj")
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .minimumScaleFactor(0.9)
                                    .allowsTightening(true)
                            } icon: {
                                Image(systemName: "xmark").foregroundColor(.red)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .tint(.brandPrimary)

                    } else {
                        Button {
                            beginEditing()
                            isEditing = true
                        } label: {
                            Label {
                                Text("Edytuj")
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .minimumScaleFactor(0.9)
                                    .allowsTightening(true)
                            } icon: {
                                Image(systemName: "pencil")
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.brandPrimary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .background(Color(UIColor.systemBackground).opacity(0.98))
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .navigationTitle(mealType(for: historyItem.date))
        .navigationBarTitleDisplayMode(.inline)
    }

    var totalCalories: Double { draft.rawResult.meal.reduce(0) { $0 + $1.calories_kcal } }
    var totalProtein: Double  { draft.rawResult.meal.reduce(0) { $0 + $1.protein_g } }
    var totalFat: Double      { draft.rawResult.meal.reduce(0) { $0 + $1.fat_g } }
    var totalCarbs: Double    { draft.rawResult.meal.reduce(0) { $0 + $1.carbs_g } }

    func validateAll() -> Bool {
        for c in draft.rawResult.meal where c.mass_g <= 0 {
            showValidationError = true
            validationMessage = "Masa każdego składnika musi być większa niż zero."
            return false
        }
        showValidationError = false
        return true
    }

    func saveEdits() {
        var updated = draft
        updated.calories = totalCalories
        updated.protein  = totalProtein
        updated.fat      = totalFat
        updated.carbs    = totalCarbs
        viewModel.update(updated)
        isEditing = false
        onUpdate?()
    }
    
    private func mealType(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        if hour < 12 { return "Śniadanie" }
        if hour < 17 { return "Obiad" }
        return "Kolacja"
    }
    
    private func beginEditing() {draftBackup = draft }
    private func restoreEdits() {
        if let b = draftBackup {
            draft = b
            draftBackup = nil
        }
    }
    private struct MetricTile: View {
        let value: Int
        let unit: String
        let label: String
        var body: some View {
            VStack(spacing: 2) {
                Text("\(value) \(unit)")
                    .font(.headline)
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private let numberFormatter: NumberFormatter = {
    let nf = NumberFormatter()
    nf.numberStyle = .decimal
    nf.maximumFractionDigits = 1
    nf.decimalSeparator = Locale.current.decimalSeparator ?? "."
    return nf
}()
