import Foundation
import FoundationModels
import Observation

/// The agent: one on-device `LanguageModelSession` that holds the conversation and the tools.
///
/// The agentic loop lives inside `session.respond(to:)`. For one request the model may call several
/// tools, read what each one returned, and only then write its reply. We just watch it happen.
@MainActor
@Observable
final class HomeAgent {
    struct Message: Identifiable {
        enum Role { case user, agent, problem }
        let id = UUID()
        let role: Role
        let text: String
        var actions: [HomeAction] = []
    }

    let home: Home
    private(set) var messages: [Message] = []
    private(set) var isWorking = false
    /// The reply so far, growing word by word while the model writes it.
    private(set) var streamingText = ""
    private var firstActionOfTurn = 0
    private var session: LanguageModelSession
    /// Set when the model says it's available but then fails to load (e.g. a fresh simulator
    /// whose model files were never downloaded). From then on the simulated agent answers.
    private var modelLoadFailure: String?

    init(home: Home) {
        self.home = home
        session = Self.makeSession(for: home)
    }

    // MARK: - Session

    private static func makeSession(for home: Home) -> LanguageModelSession {
        let tools: [any Tool] = [
            SetLightTool(home: home),
            DimLightTool(home: home),
            SetCurtainsTool(home: home),
            SetTemperatureTool(home: home),
            SetApplianceTool(home: home),
            LockFrontDoorTool(home: home),
            RunModeTool(home: home),
            GetHomeStatusTool(home: home),
        ]
        let instructions = """
        You are the assistant of a smart home. You change the house ONLY by calling tools.
        Rooms: living room, kitchen, bedroom, bathroom, hallway. The TV is in the living room, \
        the coffee machine in the kitchen, the front door in the hallway.
        - Call a tool for every change the user asks for. One request may need several tools.
        - For a mood like "movie night", "goodnight", "I'm leaving" or "good morning", use runMode.
        - If you need to know the current state, call getHomeStatus first.
        - Read every tool result. Only say something happened if a tool result says it did.
        - You can never unlock the front door. If asked, say the user must tap the door themselves.
        - Reply in one short, friendly sentence.
        """
        return LanguageModelSession(model: SystemLanguageModel.default, tools: tools, instructions: instructions)
    }

    /// Forgets the conversation. The house is not touched.
    func newConversation() {
        messages.removeAll()
        session = Self.makeSession(for: home)
    }

    /// Loads the model early so the first reply is faster.
    func prewarm() {
        if unavailableReason == nil { session.prewarm() }
    }

    // MARK: - Talking to the model

    /// What the tools have done so far in the current request, shown live while the model works.
    var liveActions: [HomeAction] {
        isWorking ? Array(home.actions.dropFirst(firstActionOfTurn)) : []
    }

    func send(_ text: String) async {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isWorking else { return }
        messages.append(Message(role: .user, text: prompt))
        home.beginAgentTurn()
        firstActionOfTurn = home.actions.count
        isWorking = true
        defer { isWorking = false }

        // No Apple Intelligence (e.g. a simulator on a Mac without it)? Use the keyword stand-in.
        if unavailableReason != nil {
            let reply = await SimulatedAgent.respond(to: prompt, home: home)
            messages.append(Message(role: .agent, text: reply, actions: liveActions))
            return
        }

        do {
            // Streaming: read snapshots as the model writes. Each snapshot holds the full text so far,
            // so we replace (not append). Tool calls happen first, inside the stream; the text comes after.
            streamingText = ""
            defer { streamingText = "" }
            for try await snapshot in session.streamResponse(to: prompt) {
                streamingText = snapshot.content
            }
            messages.append(Message(role: .agent, text: streamingText, actions: liveActions))
        } catch let error as LanguageModelSession.GenerationError {
            var text = error.localizedDescription
            switch error {
            case .exceededContextWindowSize:
                // The on-device model has a small context window. Start fresh and let the user retry.
                session = Self.makeSession(for: home)
                text = "This conversation got too long for the on-device model, so I started a fresh one. Please try again."
            case .guardrailViolation:
                text = "I can’t help with that. Try asking about the lights, curtains, temperature or devices."
            default:
                break
            }
            messages.append(Message(role: .problem, text: text, actions: liveActions))
        } catch {
            // Not a generation error: the model itself couldn't run. Switch to the stand-in and
            // still answer this request, rather than leaving the user with a raw error.
            modelLoadFailure = "The on-device model couldn’t load on this device."
            let reply = await SimulatedAgent.respond(to: prompt, home: home)
            messages.append(Message(role: .agent, text: reply, actions: liveActions))
        }
    }

    // MARK: - Availability

    /// `nil` when Apple Intelligence is ready, otherwise what to tell the user.
    var unavailableReason: String? {
        if let modelLoadFailure { return modelLoadFailure }
        return switch SystemLanguageModel.default.availability {
        case .available:
            nil
        case .unavailable(.deviceNotEligible):
            "This device doesn’t support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            "Turn on Apple Intelligence in Settings to use the agent."
        case .unavailable(.modelNotReady):
            "Apple Intelligence is still downloading. Try again in a few minutes."
        case .unavailable:
            "Apple Intelligence isn’t available right now."
        }
    }
}
