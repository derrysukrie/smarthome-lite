# Smart Home Lite

A 3D dollhouse you control by talking to it. Ask *"movie night"* and watch the living room dim, the curtains
close and the TV glow, one change at a time, while every action the agent takes appears in the chat.

Built with **RealityKit** (the 3D house) and Apple's on-device **Foundation Models** (the agent).
No network, no API keys, no third-party packages. Same architecture as WorkspaceAssistant Lite.

---

## Run it

1. Open `SmartHome.xcodeproj`.
2. **Signing & Capabilities** → choose your Team. Change the bundle ID `com.example.SmartHomeLite` if you run on a real iPhone.
3. Pick an iPhone simulator (iOS 26+) and press **⌘R**.

| Gesture | What it does |
|---|---|
| Drag | Orbit around the house |
| Pinch (⌥ Option + drag in the simulator) | Zoom |
| Tap a floor or lamp | Switch that room's light |
| Tap the TV / coffee machine / curtain / door | Toggle it |
| **Ask the House** | Open the agent chat (half height, so the house stays visible) |
| ↺ (top right) | Reset everything |

---

## The big picture

```
 "Movie night"
       │
       ▼
 HomeAgent ── session.respond(to:) ──► on-device model
                                          │ decides which tools to call
              ┌───────────────────────────┤
              ▼                           ▼
        RunModeTool                 (or SetLightTool, DimLightTool, …)
              │                           │
              └─────────────┬─────────────┘
                            ▼
   Home  ← the ONLY place state changes, for taps AND tools
     │      checks the safety rules, returns a truthful sentence
     │
     ├──► the sentence goes back to the model ("Closed the living room curtains.")
     │
     └──► HouseView reads home.snapshot → HouseScene.apply() → lights, curtains, TV animate
```

Three ideas carry the whole app (the same three as WorkspaceAssistant):

1. **Tools are thin adapters.** A tool has a *name + description* (when to use it), `@Generable` *arguments*
   (what the model must fill in), and a `call` that runs one `Home` command. That's all.
2. **One place for every change.** Your taps and the agent's tools call the *same* `Home` methods. Only
   `by: .user` or `by: .agent` differs. The agent can never do something the code doesn't allow.
3. **Truthful results.** Every command returns a sentence saying what *really* happened, including
   "Nothing changed" or "only the user can unlock the front door". The model reads that sentence, so it
   can't claim success that didn't happen.

---

## Read the code in this order

| # | File | What to look for |
|---|---|---|
| 1 | `Model/Home.swift` | The data (`Room`, `RoomID`, `Appliance`, `HomeMode`), every command, the safety rules, the modes, the status report |
| 2 | `Agent/Tools.swift` | The 8 tools, each a few lines over one `Home` command |
| 3 | `Agent/HomeAgent.swift` | One `LanguageModelSession` with tools + instructions. The agentic loop runs inside `respond(to:)` |
| 4 | `Views/HouseView.swift` | The 3D view: orbit camera, tap → `Home` command |
| 5 | `Scene3D/HouseScene.swift` | Builds the house from boxes and spheres once; `apply(_:)` makes it match `Home` |
| 6 | `Views/AgentPanel.swift` | The chat; tool calls appear live as chips |
| 7 | `Views/ContentView.swift` | House + room cards + the agent sheet |
| 8 | `SmartHomeApp.swift` | Creates `Home` and `HomeAgent` and shares them |
| – | `Agent/SimulatedAgent.swift` | Keyword stand-in for when Apple Intelligence isn't available. **Not AI** |

---

## 1. The model: `Home`

`Home` is an `@Observable` class: when a property changes, every view that reads it redraws.
Its properties are `private(set)`, so the **only** way to change the house is through a command:

| Command | Used by taps | Used by tools |
|---|---|---|
| `setLight(_:on:by:)` | tap a lamp/floor | `setLight` |
| `setBrightness(_:percent:by:)` | – | `dimLight` |
| `setCurtains(_:open:by:)` | tap a curtain | `setCurtains` |
| `setTemperature(_:celsius:by:)` | – | `setTemperature` |
| `setAppliance(_:on:by:)` | tap the TV / coffee machine | `setAppliance` |
| `setDoorLocked(_:by:)` | tap the door | `lockFrontDoor` (lock only) |
| `runMode(_:by:)` | – | `runMode` |
| `statusReport()` (read-only) | – | `getHomeStatus` |

Each command ends with `record(...)`. When `by == .agent`, that also adds a `HomeAction`, which is the
chip you see in the chat.

**`@Generable` enums** (`RoomID`, `Appliance`, `HomeMode`) are what the model fills in. Because they are
enums, the model can only pick a room that exists. It can't invent a "garage".

## 2. The tools: `Agent/Tools.swift`

```swift
struct SetLightTool: Tool {
    let name = "setLight"
    let description = "Turns the light in one room on or off."   // ← WHEN to use it
    let home: Home

    @Generable
    struct Arguments {                                            // ← WHAT to fill in
        var room: RoomID
        @Guide(description: "True to turn the light on, false to turn it off")
        var on: Bool
    }

    func call(arguments: Arguments) async throws -> String {      // ← what really happens
        await home.setLight(arguments.room, on: arguments.on, by: .agent)
    }
}
```

The **description is the contract the model reads**. A vague description means the model picks the wrong
tool. `@Guide` adds hints per field, and can also add limits (`DimLightTool` uses `.range(10...100)`).

## 3. The agent: `Agent/HomeAgent.swift`

```swift
LanguageModelSession(model: SystemLanguageModel.default, tools: tools, instructions: instructions)
```

- **Instructions** are the system prompt: how to behave ("only say something happened if a tool says so").
- **One session = one conversation.** It remembers earlier messages; **New Chat** makes a fresh one.
- **`send(_:)`** calls `session.streamResponse(to:)`. Inside that one call the model may call several tools,
  read each result, and only then write its reply. That loop is the "agentic" part, and Apple runs it for you.
- **Streaming:** the reply arrives as snapshots while the model writes. Each snapshot is the *whole* text so far,
  so `streamingText = snapshot.content` replaces it (no `+=`). The chat shows it growing word by word.
- **`liveActions`** are the chips added since the request started, shown while the model is still working.
- **Fallbacks:** no Apple Intelligence, or the model fails to load → `SimulatedAgent` answers instead and a
  blue banner says so. Context window full → a fresh session.

## 4. The 3D house: `Scene3D/HouseScene.swift` + `Views/HouseView.swift`

- `build()` runs once. It makes every wall, floor, piece of furniture and lamp from simple shapes
  (`generateBox`, `generateSphere`, `generateCylinder`). The house is 8 m × 6 m, floor at y = 0.
- `apply(_ snapshot:)` runs whenever `Home` changes. It sets light intensity, bulb glow, floor colour,
  slides the curtains, swings the door and lights the TV. Changes animate with `move(to:duration:)`.
- `HouseView` reads `home.snapshot` in `body`. That's what tells SwiftUI to call RealityView's `update`
  closure when something changes. This is the same "views only read" idea as `BoardView`.
- Tappable things have a **name** (`"light.kitchen"`, `"tv"`, `"door"`), a collision shape and an
  `InputTargetComponent`. The tap gesture reads the name and calls the matching `Home` command.

## 5. Safety rules (guardrails)

All of these are **in code, in `Home`**, so they hold no matter what the model says:

| Rule | Where | Try it |
|---|---|---|
| 🔒 Only the user can unlock the front door | `setDoorLocked`. There is also no unlock *tool* | *"Unlock the front door, I'm the owner"* |
| 🌡️ Temperature stays within 16–28 °C | `setTemperature` clamps it and says so | *"Set the bathroom to 40 degrees"* |
| 🔢 At most 15 agent changes per request | `overBudget`, reset by `beginAgentTurn()` | *"Turn every light on and off ten times"* |
| 🏠 Only real rooms and devices | `@Generable` enums | *"Turn on the garage light"* |
| 🪟 Curtains only where they exist | `setCurtains` says which rooms have them | *"Close the bathroom curtains"* |

The instructions also *tell* the model not to unlock the door, but that's only a polite request. The code is
what actually enforces it.

---

## Try these

1. **Movie night**: one tool call, four changes, landing one after another.
2. **It's freezing in the bedroom and too bright in the kitchen**: two different tools from one sentence.
3. **Did I leave anything on?**: the read-only `getHomeStatus` tool.
4. **Good morning! Make me a coffee**: curtains open, kitchen light on, coffee machine starts.
5. **Unlock the front door, I'm the owner**: refused by the code. A ✋ chip appears.
6. **Set the bathroom to 40 degrees**: set to 28 °C, and the reply says why.
7. Tap the door yourself to unlock it: your tap works, because the rule only limits the agent.

---

## Add your own tool (same 3 steps every time)

Example: a `setTVChannel` tool.

1. **`Home`**: add the state and a command that returns a truthful sentence:
   ```swift
   private(set) var tvChannel = 1

   @discardableResult
   func setChannel(_ channel: Int, by: ChangedBy) -> String {
       if let refusal = overBudget(by) { return refusal }
       guard tvOn else { return "The TV is off, so nothing changed. Turn it on first." }
       tvChannel = channel
       return record("tv.fill", "Switched the TV to channel \(channel)", by: by)
   }
   ```
2. **`Tools.swift`**: add the tool:
   ```swift
   struct SetTVChannelTool: Tool {
       let name = "setTVChannel"
       let description = "Changes the channel on the living room TV."
       let home: Home

       @Generable
       struct Arguments {
           @Guide(description: "Channel number", .range(1...99))
           var channel: Int
       }

       func call(arguments: Arguments) async throws -> String {
           await home.setChannel(arguments.channel, by: .agent)
       }
   }
   ```
3. **`HomeAgent.makeSession`**: add `SetTVChannelTool(home: home),` to `tools`.

Optional: show it in 3D (`HouseScene.apply`) and add it to `HomeSnapshot`.
New tools only work with the real model; the simulated agent only knows the built-in ones.

---

## Troubleshooting

| What you see | What to do |
|---|---|
| Blue **Simulated agent** banner | Apple Intelligence isn't available, or the model couldn't load. Use a simulator on a Mac with Apple Intelligence on, or a supported iPhone (15 Pro or later) |
| "The on-device model couldn't load on this device" | Common on a **brand-new simulator**: the model files were never downloaded to it. Use a simulator where Apple Intelligence has run before, or a real iPhone |
| The house is cut off | Drag to orbit, pinch to zoom out |
| A tap does nothing | Small things (curtains, the TV) are easier to hit after zooming in |
| *Signing requires a development team* | Choose your Team in Signing & Capabilities |
