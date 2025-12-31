import SwiftUI

struct RemoteResultReviewView: View {
    let taskID: String
    let sourceImage: UIImage
    let server: ServerResult
    let pendingSampleID: String?
    var onAccept: (LocalMealHistoryItem) -> Void
    var onReject: () -> Void

    @State private var draftName: String = ""
    @State private var comps: [Editable] = []
    @State private var isEditing = false
    @State private var showValidationError = false

    @State private var originalName: String = ""
    @State private var originalComps: [Editable] = []

    init(taskID: String,
         sourceImage: UIImage,
         server: ServerResult,
         pendingSampleID: String? = nil,
         onAccept: @escaping (LocalMealHistoryItem) -> Void,
         onReject: @escaping () -> Void) {
        self.taskID = taskID
        self.sourceImage = sourceImage
        self.server = server
        self.pendingSampleID = pendingSampleID
        self.onAccept = onAccept
        self.onReject = onReject
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {

                Text(draftName.isEmpty ? "—" : draftName)
                    .font(.title).bold()
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                if isEditing {
                    TextField("Nazwa posiłku", text: $draftName)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)
                }

                summaryCard

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("SKŁADNIKI")
                            .font(.caption2)
                        Spacer()
                    }

                    if comps.isEmpty {
                        Text("Brak danych do wyświetlenia (sprawdź dekodowanie odpowiedzi serwera).")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach($comps) { $c in
                            ingredientBlock($c)
                            Divider()
                        }
                    }
                }
                .padding(.horizontal)

                if showValidationError {
                    Text("Masa każdego składnika musi być większa niż zero.")
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                }

                Spacer(minLength: 20)
            }
            .padding(.top)
        }
        .navigationTitle("Wynik analizy")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            draftName = defaultSummary(from: server.meal)
            comps = server.meal.map { Editable.fromServer($0) }
            originalName = draftName
            originalComps = comps
        }

        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {

                HStack(spacing: 12) {
                    if isEditing {
                        Button {
                            if validate() {
                                originalName = draftName
                                originalComps = comps
                                isEditing = false
                            }
                        } label: {
                            Label("Zapisz zmiany", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.brandPrimary)
                        
                        Button {
                            draftName = originalName
                            comps = originalComps
                            showValidationError = false
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
                            isEditing = true
                        } label: {
                            Label("Edytuj", systemImage: "pencil")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.brandPrimary)
                    }
                }
                .padding(.horizontal)

                HStack(spacing: 12) {
                    Button {
                        Task { await acceptAndSend() }
                    } label: {
                        Text("Zatwierdź posiłek").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brandPrimary)
                    
                    Button(role: .destructive) { onReject() } label: {
                        Text("Odrzuć posiłek").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(.brandPrimary)

                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .background(.ultraThinMaterial)
        }
    }
    
    private var summaryCard: some View {
        let t = totals
        return VStack(alignment: .leading, spacing: 18) {
            
            HStack(spacing: 10){
                Spacer()
                MetricTile(value: Int(t.cal), unit: "kcal", label: "kalorie")
                Spacer()
            }
            
            HStack(spacing: 12) {
                MetricTile(value: Int(t.pro),  unit: "g",    label: "białko")
                MetricTile(value: Int(t.fat),      unit: "g",    label: "tłuszcz")
                MetricTile(value: Int(t.car),    unit: "g",    label: "węglowodany")
            }
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
    }

    private func summaryCell(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.headline)
                .monospacedDigit()
                .multilineTextAlignment(.center)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func ingredientBlock(_ c: Binding<Editable>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if isEditing {
                HStack{
                    Spacer()
                    TextField("Nazwa składnika", text: c.name)
                        .font(.headline)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                    Spacer()
                }

                HStack(spacing: 8) {
                    Spacer()
                    Text("masa (g):")
                    DecimalField("0", value: c.mass, fractionDigits: 1)
                        .keyboardType(.decimalPad)
                        .frame(width: 90)
                        .textFieldStyle(.roundedBorder)
                    Spacer()
                }

                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Text("kcal/100g:")
                        DecimalField("0.00", value: c.baseCal100, fractionDigits: 2)
                            .frame(width: 80)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 6) {
                        Text("B/100g:")
                        DecimalField("0.00", value: c.basePro100, fractionDigits: 2)
                            .frame(width: 80)
                    }
                }
                .font(.caption)

                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Text("T/100g:")
                        DecimalField("0.00", value: c.baseFat100, fractionDigits: 2)
                            .frame(width: 80)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 6) {
                        Text("W/100g:")
                        DecimalField("0.00", value: c.baseCar100, fractionDigits: 2)
                            .frame(width: 80)
                    }
                }
                .font(.caption)

                HStack {
                    Spacer()
                    
                    Button {
                        if let idx = comps.firstIndex(where: { $0.id == c.wrappedValue.id }) {
                            comps.remove(at: idx)
                        }
                    } label: {
                        Label("", systemImage: "trash").foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }

            } else {
                
                HStack{
                    Spacer()
                    Text(c.wrappedValue.name)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                
                HStack {
                    Spacer()
                    MetricTile(
                        value: Int(c.wrappedValue.mass),
                        unit: "g",
                        label: "masa"
                    )
                    .frame(maxWidth: 140)
                    Spacer()
                }

                let abs = c.wrappedValue.absoluteMacros
                
                HStack(spacing: 12) {
                    MetricTile(value: Int(abs.cal), unit: "kcal", label: "kalorie")
                    MetricTile(value: Int(abs.pro),     unit: "g",    label: "białko")
                    MetricTile(value: Int(abs.fat),         unit: "g",    label: "tłuszcz")
                    MetricTile(value: Int(abs.car),       unit: "g",    label: "węglowodany")
                }

            }
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
    
    private func macroCell(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.headline)
                .monospacedDigit()
                .multilineTextAlignment(.center)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var totals: (cal: Double, pro: Double, fat: Double, car: Double) {
        var cal = 0.0, pro = 0.0, fat = 0.0, car = 0.0
        for e in comps {
            let a = e.absoluteMacros
            cal += a.cal; pro += a.pro; fat += a.fat; car += a.car
        }
        return (round2(cal), round2(pro), round2(fat), round2(car))
    }

    private func validate() -> Bool {
        if comps.contains(where: { $0.mass <= 0 }) {
            showValidationError = true
            return false
        }
        showValidationError = false
        return true
    }

    private var hasEdits: Bool {
        if draftName != originalName { return true }
        if comps.count != originalComps.count { return true }
        for (a, b) in zip(comps, originalComps) {
            if !a.isAlmostEqual(to: b) { return true }
        }
        return false
    }

    private func acceptAndSend() async {
        guard validate() else { return }

        if hasEdits {
            let reviewed = buildReviewedServerResult()
            do { try await APIClient.shared.submitReviewed(taskID: taskID, reviewed: reviewed) }
            catch { print("WARN submitReviewed:", error) }
        }

        let local = buildLocalItem()
        onAccept(local)

        if let pid = pendingSampleID,
           let sample = PendingDataManager.shared.samples.first(where: { $0.id == pid }) {
            await MainActor.run {
                PendingDataManager.shared.remove(sample, deleteFiles: true)
            }
        }
    }

    private func buildLocalItem() -> LocalMealHistoryItem {
        let thumb = saveThumbnail(sourceImage)
        let mapped = comps.map { e in
            MealComponent(
                id: UUID().uuidString,
                name: e.name,
                mass_g: e.mass,
                base_calories_per_100g: e.baseCal100,
                base_protein_per_100g: e.basePro100,
                base_fat_per_100g: e.baseFat100,
                base_carbs_per_100g: e.baseCar100
            )
        }
        let t = totals
        return LocalMealHistoryItem(
            id: UUID(), date: Date(), thumbnailName: thumb,
            summary: draftName.isEmpty ? defaultSummary(from: server.meal) : draftName,
            calories: t.cal, protein: t.pro, fat: t.fat, carbs: t.car,
            rawResult: MealResult(meal: mapped)
        )
    }

    private func buildReviewedServerResult() -> ServerResult {
        let entries: [ServerMealEntry] = comps.map { e in
            let abs = e.absoluteMacros
            let dict: [String: Double] = [
                "Kalorie (kcal/100g)" : abs.cal,
                "Tłuszcz"             : abs.fat,
                "Węglowodany"         : abs.car,
                "Białko"              : abs.pro
            ]
            return ServerMealEntry(name: e.name, weight_g: e.mass, nutrients: dict)
        }

        let t = totals
        let totalsDict: [String: Double] = [
            "weight_g"            : comps.reduce(0) { $0 + $1.mass },
            "Kalorie (kcal/100g)" : t.cal,
            "Tłuszcz"             : t.fat,
            "Węglowodany"         : t.car,
            "Białko"              : t.pro
        ]
        return ServerResult(meal: entries, total: totalsDict)
    }

    private func defaultSummary(from comps: [ServerMealEntry]) -> String {
        comps.map { $0.name }.prefix(3).joined(separator: ", ")
    }

    private func saveThumbnail(_ image: UIImage) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        let filename = UUID().uuidString + ".jpg"
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(filename)
        do { try data.write(to: url); return filename }
        catch { return nil }
    }

    private func round2(_ x: Double) -> Double { (x * 100).rounded() / 100 }
}

extension RemoteResultReviewView.Editable: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name &&
        lhs.mass.isClose(to: rhs.mass) &&
        lhs.baseCal100.isClose(to: rhs.baseCal100) &&
        lhs.basePro100.isClose(to: rhs.basePro100) &&
        lhs.baseFat100.isClose(to: rhs.baseFat100) &&
        lhs.baseCar100.isClose(to: rhs.baseCar100)
    }

    func isAlmostEqual(to other: Self) -> Bool { self == other }
}

private extension Double {
    func isClose(to other: Double, eps: Double = 1e-6) -> Bool {
        abs(self - other) <= eps
    }
}

extension RemoteResultReviewView {
    struct Editable: Identifiable {
        let id = UUID()
        var name: String
        var mass: Double
        var baseCal100: Double
        var basePro100: Double
        var baseFat100: Double
        var baseCar100: Double

        var absoluteMacros: (cal: Double, pro: Double, fat: Double, car: Double) {
            let f = max(0, mass) / 100.0
            return (
                (baseCal100 * f).rounded(toPlaces: 2),
                (basePro100 * f).rounded(toPlaces: 2),
                (baseFat100 * f).rounded(toPlaces: 2),
                (baseCar100 * f).rounded(toPlaces: 2)
            )
        }

        static func fromServer(_ sm: ServerMealEntry) -> Editable {
            let m = sm.weight_g
            let mac = pickMacros(sm.nutrients)
            func base100(_ abs: Double) -> Double { m > 0 ? (abs * 100.0 / m) : 0.0 }
            return Editable(
                name: sm.name, mass: m,
                baseCal100: base100(mac.cal),
                basePro100: base100(mac.pro),
                baseFat100: base100(mac.fat),
                baseCar100: base100(mac.car)
            )
        }

        static func pickMacros(_ d: [String: Double]) -> (cal: Double, pro: Double, fat: Double, car: Double) {
            func val(_ keys: [String]) -> Double {
                for k in keys { if let x = d[k] { return x } }
                let norm = d.reduce(into: [String: Double]()) { acc, kv in
                    let nk = kv.key.folding(options: .diacriticInsensitive, locale: .current).lowercased()
                    acc[nk] = kv.value
                }
                for k in keys {
                    let nk = k.folding(options: .diacriticInsensitive, locale: .current).lowercased()
                    if let x = norm[nk] { return x }
                }
                return 0
            }
            let cal = val(["Kalorie (kcal/100g)", "Kalorie", "kcal", "calories"])
            let pro = val(["Białko", "Bialko", "protein"])
            let fat = val(["Tłuszcz", "Tluszcz", "fat"])
            let car = val(["Węglowodany", "Weglowodany", "carbohydrates", "carbs"])
            return (cal, pro, fat, car)
        }
    }
}

private struct DecimalField: View {
    let placeholder: String
    @Binding var value: Double
    var fractionDigits: Int = 0

    init(_ placeholder: String, value: Binding<Double>, fractionDigits: Int = 0) {
        self.placeholder = placeholder
        self._value = value
        self.fractionDigits = fractionDigits
    }

    var body: some View {
        TextField(placeholder, text: Binding(
            get: { formatted(value) },
            set: { input in
                let norm = input.replacingOccurrences(of: ",", with: ".")
                if let v = Double(norm) {
                    let p = pow(10.0, Double(max(0, fractionDigits)))
                    value = (v * p).rounded() / p
                }
            })
        )
        .keyboardType(.decimalPad)
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(.trailing)
        .frame(minWidth: 70)
    }

    private func formatted(_ x: Double) -> String {
        if fractionDigits == 0 { return String(Int(x)) }
        return String(format: "%.\(fractionDigits)f", x)
    }
}

private extension Double {
    func rounded(toPlaces p: Int) -> Double {
        let m = pow(10.0, Double(p))
        return (self * m).rounded() / m
    }
}
