import Foundation

/// A stand-in for the on-device model, used only when Apple Intelligence isn't available
/// (for example a simulator on a Mac with Apple Intelligence turned off).
///
/// It is NOT AI. It spots a few keywords and calls the same Home commands the real tools call,
/// so the demo still works and the safety rules still apply. Tools you add need the real model.
@MainActor
enum SimulatedAgent {
    static func respond(to prompt: String, home: Home) async -> String {
        var results: [String] = []

        // "Close the curtains and turn on the TV" → one clause per action.
        for clause in clauses(in: prompt) {
            let words = tokens(in: clause)
            guard let result = await act(on: words, home: home) else { continue }
            results.append(result)
            await think()
        }

        guard !results.isEmpty else {
            return "I’m the simulated agent, so I only understand simple requests, like “movie night” or “turn on the bedroom light”."
        }
        return results.joined(separator: " ")
    }

    // MARK: - Keyword spotting

    private static func act(on words: [String], home: Home) async -> String? {
        let text = words.joined(separator: " ")

        // Modes first: they're the most fun.
        if text.contains("movie") || text.contains("film") { return await home.runMode(.movieNight, by: .agent) }
        if text.contains("goodnight") || text.contains("good night") || text.contains("bed time") || text.contains("bedtime") {
            return await home.runMode(.goodnight, by: .agent)
        }
        if text.contains("leaving") || text.contains("going out") || text.contains("bye") { return await home.runMode(.leavingHome, by: .agent) }
        if text.contains("morning") || text.contains("wake") { return await home.runMode(.goodMorning, by: .agent) }

        // Questions.
        if words.contains("status") || text.contains("left on") || text.hasPrefix("is ") || text.hasPrefix("what") {
            return "Here’s the house:\n" + home.statusReport()
        }

        let on = words.contains("on") || words.contains("open") || words.contains("start")
        let off = words.contains("off") || words.contains("close") || words.contains("stop")

        // The front door. The simulated agent obeys the same rule: it can lock, never unlock.
        if words.contains("door") || words.contains("lock") || words.contains("unlock") {
            return home.setDoorLocked(!words.contains("unlock") && !words.contains("open"), by: .agent)
        }
        if words.contains("tv") || words.contains("television") {
            return home.setAppliance(.tv, on: !off, by: .agent)
        }
        if words.contains("coffee") {
            return home.setAppliance(.coffeeMachine, on: !off, by: .agent)
        }

        let rooms = rooms(in: words)
        if words.contains(where: { $0.hasPrefix("curtain") || $0 == "blinds" }) {
            let targets = rooms.isEmpty ? [.livingRoom, .bedroom] : rooms
            return targets.map { home.setCurtains($0, open: !(off || words.contains("closed")), by: .agent) }.joined(separator: " ")
        }
        if words.contains(where: { ["cold", "freezing", "warm", "hot", "temperature", "degrees"].contains($0) }) {
            let celsius = number(in: words) ?? (words.contains("cold") || words.contains("freezing") ? 24 : 19)
            return (rooms.isEmpty ? [.livingRoom] : rooms).map { home.setTemperature($0, celsius: celsius, by: .agent) }.joined(separator: " ")
        }
        if words.contains("dim") || words.contains("darker") {
            return (rooms.isEmpty ? [.livingRoom] : rooms).map { home.setBrightness($0, percent: number(in: words) ?? 25, by: .agent) }.joined(separator: " ")
        }
        if words.contains(where: { $0.hasPrefix("light") || $0 == "lamp" }) || on || off {
            let targets = rooms.isEmpty || words.contains("all") || words.contains("everything") ? RoomID.allCases : rooms
            return targets.map { home.setLight($0, on: on && !off, by: .agent) }.joined(separator: " ")
        }
        return nil
    }

    private static func rooms(in words: [String]) -> [RoomID] {
        var found: [RoomID] = []
        if words.contains("living") || words.contains("lounge") || words.contains("sofa") { found.append(.livingRoom) }
        if words.contains("kitchen") { found.append(.kitchen) }
        if words.contains("bedroom") || words.contains("bed") { found.append(.bedroom) }
        if words.contains("bathroom") || words.contains("bath") { found.append(.bathroom) }
        if words.contains("hallway") || words.contains("hall") || words.contains("entrance") { found.append(.hallway) }
        return found
    }

    private static func number(in words: [String]) -> Int? {
        words.compactMap { Int($0) }.first
    }

    // MARK: - Text helpers

    private static func clauses(in prompt: String) -> [String] {
        var text = prompt.lowercased()
        for separator in [" and then ", " then ", " and ", ",", ";", "."] {
            text = text.replacingOccurrences(of: separator, with: "|")
        }
        return text.split(separator: "|").map(String.init)
    }

    private static func tokens(in text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// A short pause so each change lands one at a time, like the real agent.
    private static func think() async {
        try? await Task.sleep(for: .milliseconds(500))
    }
}
