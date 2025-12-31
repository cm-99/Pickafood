import SwiftUI
import CoreData

struct ProgressViewScreen: View {
    let image: UIImage
    @StateObject var viewModel: ProgressViewModel
    @ObservedObject var dashboardVM: DashboardViewModel
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    let pendingSampleID: String?
    
    @State private var showReviewSheet = false

    init(image: UIImage,
         viewModel: ProgressViewModel,
         dashboardVM: DashboardViewModel,
         pendingSampleID: String? = nil)
    {
        self.image = image
        self._viewModel = StateObject(wrappedValue: viewModel)
        self.dashboardVM = dashboardVM
        self.pendingSampleID = pendingSampleID
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Analiza posiłku")
                .font(.title).bold()

            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 260)
                    .cornerRadius(16)
                    .shadow(radius: 4)

                ScannerOverlay()
                    .allowsHitTesting(false)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            VStack(spacing: 8) {
                Text(viewModel.stage)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                ProgressView(value: viewModel.progress)
                    .progressViewStyle(.linear)
            }
            .padding(.horizontal)

            if let error = viewModel.errorMessage {
                Text(error).foregroundColor(.red)
            }

            Spacer()
        }
        .padding()
        .task { await viewModel.start() }
        .onChange(of: viewModel.isCompleted) { done in
            if done { showReviewSheet = true }
        }
        .onChange(of: viewModel.errorMessage) { err in
            if err != nil { showReviewSheet = false }
        }
        .alert(
            "Nie udało się przeprowadzić analizy",
            isPresented: Binding(
                get: { (viewModel.errorMessage ?? "").isEmpty == false },
                set: { shown in if !shown { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK") {
                viewModel.errorMessage = nil
                dismiss() // powrót do Dashboard
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(isPresented: $showReviewSheet) {
            if let server = viewModel.serverResult {
                RemoteResultReviewView(
                    taskID: viewModel.taskID,
                    sourceImage: image,
                    server: server,
                    pendingSampleID: pendingSampleID,
                    onAccept: { item in
                        dashboardVM.add(item)
                        showReviewSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            dismiss()
                        }
                    },
                    onReject: {
                        showReviewSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            dismiss()
                        }
                    }
                )
                .environment(\.managedObjectContext, viewContext)
            } else {
                VStack {
                    Text("Brak wyniku").padding()
                    Button("Zamknij") { showReviewSheet = false }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }
}

private struct ScannerOverlay: View {
    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let h = geo.size.height
                let period = 3.0
                let y = CGFloat(fmod(t, period) / period) * h

                Canvas { ctx, size in
                    let lineRect = CGRect(x: 0, y: y, width: size.width, height: 2)
                    var path = Path(CGRect(x: lineRect.minX, y: lineRect.minY, width: lineRect.width, height: lineRect.height))
                    ctx.stroke(path, with: .color(.white.opacity(0.9)), lineWidth: 2)
                    path = Path(CGRect(x: lineRect.minX, y: y-1, width: lineRect.width, height: 4))
                    ctx.fill(path, with: .radialGradient(
                        .init(colors: [.white.opacity(0.45), .clear]),
                        center: CGPoint(x: size.width/2, y: y),
                        startRadius: 1, endRadius: 120)
                    )
                }
            }
        }
    }
}


