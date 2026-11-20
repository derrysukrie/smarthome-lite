import Foundation
import FoundationModels
import Observation

/// The rooms in the house.
///
/// `@Generable` lets this enum be used directly as a tool argument:
/// the model can only ever pick one of these five rooms.
@Generable
enum RoomID: String, CaseIterable, Identifiable {
    case livingRoom, kitchen, bedroom, bathroom, hallway

    var id: String { rawValue }

    var name: String {
        switch self {
        case .livingRoom: "Living Room"
        case .kitchen: "Kitchen"
        case .bedroom: "Bedroom"
        case .bathroom: "Bathroom"
        case .hallway: "Hallway"
        }
    }

    var symbol: String {
        switch self {
        case .livingRoom: "sofa.fill"
        case .kitchen: "fork.knife"
        case .bedroom: "bed.double.fill"
        case .bathroom: "shower.fill"
        case .hallway: "door.left.hand.closed"
        }
    }
}

/// Devices that are simply on or off.
@Generable
enum Appliance: String, CaseIterable {
    case tv, coffeeMachine

    var name: String { self == .tv ? "TV" : "coffee machine" }
}

/// Ready-made moods: one request, several changes.
@Generable
enum HomeMode: String, CaseIterable {
    case movieNight, goodnight, leavingHome, goodMorning

    var name: String {
        switch self {
        case .movieNight: "Movie night"
        case .goodnight: "Goodnight"
        case .leavingHome: "Leaving home"
        case .goodMorning: "Good morning"
        }
    }
}

/// One room and the devices in it.
struct Room: Identifiable, Equatable {
    let id: RoomID
    var lightOn = false
    /// 0.1 (dim) to 1.0 (full).
    var brightness = 1.0
    /// Degrees Celsius.
    var temperature = 21.0
    /// `nil` when the room has no curtains.
    var curtainsOpen: Bool?
}

extension Room {
    /// How the house looks when the app starts: evening, a couple of lights on.
    static let start: [Room] = [
        Room(id: .livingRoom, lightOn: true, brightness: 0.8, curtainsOpen: true),
        Room(id: .kitchen, lightOn: true),
        Room(id: .bedroom, curtainsOpen: true),
        Room(id: .bathroom),
        Room(id: .hallway),
    ]
}

/// Who made a change: a tap in the house, or a tool call by the agent.
enum ChangedBy {
    case user, agent
}

/// Something the agent did, shown as a chip in the chat.
struct HomeAction: Identifiable, Hashable {
    let id = UUID()
    let symbol: String
    let summary: String
}

/// Everything the 3D scene needs to draw the house. `Equatable`, so the scene only updates when something changed.
struct HomeSnapshot: Equatable {
    var rooms: [Room]
    var tvOn: Bool
    var coffeeOn: Bool
    var doorLocked: Bool
}

/// The house's state, and the only place it changes.
///
/// Same idea as `Workspace` in WorkspaceAssistant: taps in the 3D house and the agent's tools call the
/// SAME command methods, only `by:` differs. Each command returns a short, truthful sentence: that
/// sentence is what the model reads back after calling a tool.
///
/// The safety rules live HERE, not in the prompt, so the model can't talk its way past them:
/// - only the user can unlock the front door,
/// - temperatures stay between 16 and 28 °C,
/// - the agent can make at most `maxAgentChangesPerTurn` changes per request.
@MainActor
@Observable
final class Home {
    static let temperatureRange = 16.0...28.0
    static let maxAgentChangesPerTurn = 15

    private(set) var rooms: [Room] = Room.start
    private(set) var tvOn = false
    private(set) var coffeeOn = false
    private(set) var doorLocked = true
    /// Everything the agent has done, in order.
    private(set) var actions: [HomeAction] = []
    private var agentChangesThisTurn = 0

    var snapshot: HomeSnapshot {
        HomeSnapshot(rooms: rooms, tvOn: tvOn, coffeeOn: coffeeOn, doorLocked: doorLocked)
    }

    func room(_ id: RoomID) -> Room {
        rooms.first { $0.id == id }!
    }

    // MARK: - Commands (shared by taps and tools)

    @discardableResult
    func setLight(_ id: RoomID, on: Bool, by: ChangedBy) -> String {
        if let refusal = overBudget(by) { return refusal }
        let index = index(of: id)
        guard rooms[index].lightOn != on else {
            return "The \(id.name.lowercased()) light is already \(on ? "on" : "off"). Nothing changed."
        }
        rooms[index].lightOn = on
        return record(on ? "lightbulb.fill" : "lightbulb", "Turned \(on ? "on" : "off") the \(id.name.lowercased()) light", by: by)
    }

    /// Dimming also switches the light on.
    @discardableResult
    func setBrightness(_ id: RoomID, percent: Int, by: ChangedBy) -> String {
        if let refusal = overBudget(by) { return refusal }
        let index = index(of: id)
        let level = min(max(Double(percent) / 100, 0.1), 1.0)
        guard !(rooms[index].lightOn && rooms[index].brightness == level) else {
            return "The \(id.name.lowercased()) light is already at \(Int(level * 100))%. Nothing changed."
        }
        rooms[index].brightness = level
        rooms[index].lightOn = true
        return record("light.max", "Set the \(id.name.lowercased()) light to \(Int(level * 100))%", by: by)
    }

    @discardableResult
    func setCurtains(_ id: RoomID, open: Bool, by: ChangedBy) -> String {
        if let refusal = overBudget(by) { return refusal }
        let index = index(of: id)
        guard let current = rooms[index].curtainsOpen else {
            let withCurtains = rooms.filter { $0.curtainsOpen != nil }.map(\.id.name).joined(separator: " and ")
            return "The \(id.name.lowercased()) has no curtains, so nothing changed. Only the \(withCurtains) have curtains."
        }
        guard current != open else {
            return "The \(id.name.lowercased()) curtains are already \(open ? "open" : "closed"). Nothing changed."
        }
        rooms[index].curtainsOpen = open
        return record(open ? "curtains.open" : "curtains.closed", "\(open ? "Opened" : "Closed") the \(id.name.lowercased()) curtains", by: by)
    }

    /// Temperatures are kept between 16 and 28 °C, whoever asks. The result says so honestly.
    @discardableResult
    func setTemperature(_ id: RoomID, celsius: Int, by: ChangedBy) -> String {
        if let refusal = overBudget(by) { return refusal }
        let index = index(of: id)
        let range = Self.temperatureRange
        let clamped = min(max(Double(celsius), range.lowerBound), range.upperBound)
        guard rooms[index].temperature != clamped else {
            return "The \(id.name.lowercased()) is already at \(Int(clamped)) °C. Nothing changed."
        }
        rooms[index].temperature = clamped
        let note = clamped == Double(celsius) ? "" : " (\(celsius) °C is outside the safe range of 16–28 °C)"
        return record("thermometer.medium", "Set the \(id.name.lowercased()) to \(Int(clamped)) °C\(note)", by: by)
    }

    @discardableResult
    func setAppliance(_ appliance: Appliance, on: Bool, by: ChangedBy) -> String {
        if let refusal = overBudget(by) { return refusal }
        let current = appliance == .tv ? tvOn : coffeeOn
        guard current != on else { return "The \(appliance.name) is already \(on ? "on" : "off"). Nothing changed." }
        switch appliance {
        case .tv: tvOn = on
        case .coffeeMachine: coffeeOn = on
        }
        let symbol = appliance == .tv ? (on ? "tv.fill" : "tv") : "cup.and.saucer.fill"
        return record(symbol, "Turned \(on ? "on" : "off") the \(appliance.name)", by: by)
    }

    /// 🔒 Safety rule: the agent may lock the front door, but only the user can unlock it.
    @discardableResult
    func setDoorLocked(_ locked: Bool, by: ChangedBy) -> String {
        if by == .agent && !locked {
            actions.append(HomeAction(symbol: "hand.raised.fill", summary: "Refused to unlock the front door"))
            return "Only the user can unlock the front door, so nothing changed. Tell the user to tap the door themselves."
        }
        if let refusal = overBudget(by) { return refusal }
        guard doorLocked != locked else { return "The front door is already \(locked ? "locked" : "unlocked"). Nothing changed." }
        doorLocked = locked
        return record(locked ? "lock.fill" : "lock.open.fill", "\(locked ? "Locked" : "Unlocked") the front door", by: by)
    }

    /// A mode is just several ordinary commands in a row, with a short pause so you can watch each one land.
    func runMode(_ mode: HomeMode, by: ChangedBy) async -> String {
        var results: [String] = []
        for step in steps(for: mode) {
            let result = step()
            results.append(result)
            if !result.contains("Nothing changed") {
                try? await Task.sleep(for: .milliseconds(350))
            }
        }
        let changed = results.filter { !$0.contains("Nothing changed") }
        guard !changed.isEmpty else { return "\(mode.name): everything was already set. Nothing changed." }
        return "\(mode.name): " + changed.joined(separator: " ")
    }

    private func steps(for mode: HomeMode) -> [() -> String] {
        let a = ChangedBy.agent
        switch mode {
        case .movieNight:
            return [
                { self.setBrightness(.livingRoom, percent: 20, by: a) },
                { self.setCurtains(.livingRoom, open: false, by: a) },
                { self.setLight(.kitchen, on: false, by: a) },
                { self.setAppliance(.tv, on: true, by: a) },
            ]
        case .goodnight:
            return RoomID.allCases.map { room in { self.setLight(room, on: false, by: a) } } + [
                { self.setCurtains(.livingRoom, open: false, by: a) },
                { self.setCurtains(.bedroom, open: false, by: a) },
                { self.setAppliance(.tv, on: false, by: a) },
                { self.setAppliance(.coffeeMachine, on: false, by: a) },
                { self.setDoorLocked(true, by: a) },
            ]
        case .leavingHome:
            return RoomID.allCases.map { room in { self.setLight(room, on: false, by: a) } } + [
                { self.setAppliance(.tv, on: false, by: a) },
                { self.setAppliance(.coffeeMachine, on: false, by: a) },
                { self.setDoorLocked(true, by: a) },
            ]
        case .goodMorning:
            return [
                { self.setCurtains(.bedroom, open: true, by: a) },
                { self.setCurtains(.livingRoom, open: true, by: a) },
                { self.setLight(.kitchen, on: true, by: a) },
                { self.setAppliance(.coffeeMachine, on: true, by: a) },
            ]
        }
    }

    // MARK: - Reading (changes nothing)

    /// A plain-text report the agent can read before it acts.
    func statusReport() -> String {
        var lines = rooms.map { room in
            var parts = [room.lightOn ? "light on (\(Int(room.brightness * 100))%)" : "light off", "\(Int(room.temperature)) °C"]
            if let open = room.curtainsOpen { parts.append("curtains \(open ? "open" : "closed")") }
            return "\(room.id.name): " + parts.joined(separator: ", ")
        }
        lines.append("TV: \(tvOn ? "on" : "off"). Coffee machine: \(coffeeOn ? "on" : "off"). Front door: \(doorLocked ? "locked" : "unlocked").")
        return lines.joined(separator: "\n")
    }

    // MARK: - Taps in the 3D house

    func toggleLight(_ id: RoomID) { setLight(id, on: !room(id).lightOn, by: .user) }

    func toggleCurtains(_ id: RoomID) {
        guard let open = room(id).curtainsOpen else { return }
        setCurtains(id, open: !open, by: .user)
    }

    func toggleTV() { setAppliance(.tv, on: !tvOn, by: .user) }
    func toggleCoffee() { setAppliance(.coffeeMachine, on: !coffeeOn, by: .user) }
    func toggleDoor() { setDoorLocked(!doorLocked, by: .user) }

    /// Puts the house back to the start.
    func reset() {
        rooms = Room.start
        tvOn = false
        coffeeOn = false
        doorLocked = true
        actions = []
    }

    /// Called by the agent at the start of every request, so the change limit is per request.
    func beginAgentTurn() {
        agentChangesThisTurn = 0
    }

    // MARK: - Helpers

    private func index(of id: RoomID) -> Int {
        rooms.firstIndex { $0.id == id }!
    }

    /// 🔢 Safety rule: a single request can't flip the whole house over and over.
    private func overBudget(_ by: ChangedBy) -> String? {
        guard by == .agent, agentChangesThisTurn >= Self.maxAgentChangesPerTurn else { return nil }
        return "The limit of \(Self.maxAgentChangesPerTurn) changes per request was reached, so nothing changed. Tell the user to ask again for the rest."
    }

    /// Returns the summary as a sentence for the model. Agent changes are also logged as chat chips.
    private func record(_ symbol: String, _ summary: String, by: ChangedBy) -> String {
        if by == .agent {
            agentChangesThisTurn += 1
            actions.append(HomeAction(symbol: symbol, summary: summary))
        }
        return summary + "."
    }
}
