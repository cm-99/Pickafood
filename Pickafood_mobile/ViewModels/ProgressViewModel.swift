import Foundation
import UIKit

// ViewModel ekranu postępu analizy.
// Polluje `/task/{id}`, podmienia label, reaguje na „done/error”,
// a także obsługuje limity czasu na kontakt.
@MainActor
final class ProgressViewModel: ObservableObject {
    @Published var progress: Double = 0.0
    @Published var stage: String = "Oczekiwanie…"
    @Published var errorMessage: String?
    @Published var isCompleted: Bool = false
    @Published var serverResult: ServerResult?

    let taskID: String
    private var isPolling = false

    private let firstContactTimeout: TimeInterval = 5    // maks. czas na "pierwszy kontakt"
    private let idleTimeout: TimeInterval = 15           // maks. przerwa bez aktualizacji
    private let pollInterval: TimeInterval = 1.0         // interwał
    private let stageStallTimeout: TimeInterval = 15

    init(taskID: String) { self.taskID = taskID }

    func start() async {
        guard !isPolling else { return }
        isPolling = true
        defer { isPolling = false }

        var gotFirstContact = false
        let firstContactDeadline = Date().addingTimeInterval(firstContactTimeout)
        var lastServerUpdate = Date()
        
        var lastStage = ""
        var lastStageChange = Date()
        
        while !Task.isCancelled && !isCompleted {
            do {
                print("Progress waiting")
                var response_OK = false
                var st = StatusResponse()
                do {
                    st = try await APIClient.shared.status(taskID: taskID)
                    response_OK = true
                }
                catch{}
                
                if Date().timeIntervalSince(lastStageChange) > stageStallTimeout ||
                    Date().timeIntervalSince(lastServerUpdate) > idleTimeout {
                    errorMessage = "Przekroczono limit czasu na odpowiedź"
                    break
                }
                
                if !response_OK{
                    continue
                }
                
                print("Progress got response")
                gotFirstContact = true
                lastServerUpdate = Date()

                let newStage = st.label
                if newStage != lastStage {
                    lastStage = newStage
                    lastStageChange = Date()
                }
                
                let total = max(1, st.total)
                progress = min(1.0, max(0.0, Double(st.step) / Double(total)))
                stage = newStage
                
                if st.state == "done" || st.result_ready {
                    let res = try await APIClient.shared.result(taskID: taskID)
                    serverResult = res
                    isCompleted = true
                    break
                } else if st.state == "error" {
                    errorMessage = st.label
                    break
                }
            } catch {
                if !gotFirstContact, Date() > firstContactDeadline {
                    errorMessage = "Brak odpowiedzi serwera"
                    break
                }
            }

            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
    }

    func stop() {
        isPolling = false
    }
}
