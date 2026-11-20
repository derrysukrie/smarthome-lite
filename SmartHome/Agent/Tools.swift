import FoundationModels

// The agent's eight tools.
//
// A tool is a function the model may decide to call. You give it:
//   • a name and a description  → how the model knows WHEN to use it
//   • @Generable Arguments      → what the model must fill in (it can't invent other fields)
//   • call(arguments:)          → your Swift code, which returns what really happened
//
// Each tool is a thin adapter over one Home command. The safety rules are in Home, not here.

struct SetLightTool: Tool {
    let name = "setLight"
    let description = "Turns the light in one room on or off."
    let home: Home

    @Generable
    struct Arguments {
        var room: RoomID
        @Guide(description: "True to turn the light on, false to turn it off")
        var on: Bool
    }

    func call(arguments: Arguments) async throws -> String {
        await home.setLight(arguments.room, on: arguments.on, by: .agent)
    }
}

struct DimLightTool: Tool {
    let name = "dimLight"
    let description = "Sets how bright the light in one room is. Also turns the light on."
    let home: Home

    @Generable
    struct Arguments {
        var room: RoomID
        @Guide(description: "Brightness in percent, from 10 (very dim) to 100 (full)", .range(10...100))
        var percent: Int
    }

    func call(arguments: Arguments) async throws -> String {
        await home.setBrightness(arguments.room, percent: arguments.percent, by: .agent)
    }
}

struct SetCurtainsTool: Tool {
    let name = "setCurtains"
    let description = "Opens or closes the curtains in a room. Only the living room and bedroom have curtains."
    let home: Home

    @Generable
    struct Arguments {
        var room: RoomID
        @Guide(description: "True to open the curtains, false to close them")
        var open: Bool
    }

    func call(arguments: Arguments) async throws -> String {
        await home.setCurtains(arguments.room, open: arguments.open, by: .agent)
    }
}

struct SetTemperatureTool: Tool {
    let name = "setTemperature"
    let description = "Sets the temperature of one room in degrees Celsius. Cold means about 18, warm about 24."
    let home: Home

    @Generable
    struct Arguments {
        var room: RoomID
        @Guide(description: "Temperature in degrees Celsius")
        var celsius: Int
    }

    func call(arguments: Arguments) async throws -> String {
        await home.setTemperature(arguments.room, celsius: arguments.celsius, by: .agent)
    }
}

struct SetApplianceTool: Tool {
    let name = "setAppliance"
    let description = "Turns the TV (in the living room) or the coffee machine (in the kitchen) on or off."
    let home: Home

    @Generable
    struct Arguments {
        var appliance: Appliance
        @Guide(description: "True to turn it on, false to turn it off")
        var on: Bool
    }

    func call(arguments: Arguments) async throws -> String {
        await home.setAppliance(arguments.appliance, on: arguments.on, by: .agent)
    }
}

/// There is deliberately no "unlockDoor" tool. Even if the model tried another way in,
/// Home.setDoorLocked refuses an unlock that comes from the agent.
struct LockFrontDoorTool: Tool {
    let name = "lockFrontDoor"
    let description = "Locks the front door. The agent can never unlock it: only the user can."
    let home: Home

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await home.setDoorLocked(true, by: .agent)
    }
}

struct RunModeTool: Tool {
    let name = "runMode"
    let description = """
        Runs a ready-made mood that changes several things at once. \
        movieNight: dim lights, close curtains, TV on. goodnight: everything off, curtains closed, door locked. \
        leavingHome: everything off, door locked. goodMorning: curtains open, kitchen light and coffee on.
        """
    let home: Home

    @Generable
    struct Arguments {
        var mode: HomeMode
    }

    func call(arguments: Arguments) async throws -> String {
        await home.runMode(arguments.mode, by: .agent)
    }
}

/// Read-only: the agent can look before it acts ("did I leave anything on?").
struct GetHomeStatusTool: Tool {
    let name = "getHomeStatus"
    let description = "Returns the current state of every room and device. Changes nothing. Use it to answer questions about the house."
    let home: Home

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await home.statusReport()
    }
}
