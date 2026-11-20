import RealityKit
import SwiftUI

/// The 3D house. Drag to orbit, pinch to zoom, tap a lamp, floor, TV, curtain, coffee machine or door.
///
/// Like `BoardView` in WorkspaceAssistant, it only READS the `Home`: every change, from a tap or
/// (later) from the agent, goes through `Home`, and the scene redraws itself to match.
struct HouseView: View {
    @Environment(Home.self) private var home
    @State private var house = HouseScene()

    var body: some View {
        // Reading the snapshot here is what makes SwiftUI call `update` when the home changes.
        let snapshot = home.snapshot

        RealityView { content in
            house.build()
            content.add(house.root)
            content.camera = .virtual
            // The orbit controls pick their distance from the target's size: framing the garden
            // (not just the building) keeps the whole house on a portrait screen.
            content.cameraTarget = house.root

            // Start above and in front of the house, looking down into the rooms like a dollhouse.
            let camera = PerspectiveCamera()
            camera.camera.fieldOfViewInDegrees = 45
            camera.look(at: [0, 0, 0.6], from: [0, 17, 14], relativeTo: nil)
            content.add(camera)
        } update: { _ in
            house.apply(snapshot)
        }
        .realityViewCameraControls(.orbit)
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in home.tapped(entityNamed: value.entity.name) }
        )
    }
}

extension Home {
    /// Handles a tap on a named entity, in the orbit view and in AR alike.
    /// Entity names look like "light.kitchen", "floor.bedroom", "curtains.livingRoom", "tv", "coffee", "door".
    func tapped(entityNamed name: String) {
        let parts = name.split(separator: ".").map(String.init)
        let room = parts.count > 1 ? RoomID(rawValue: parts[1]) : nil
        withAnimation {
            switch (parts.first, room) {
            case ("light", let room?), ("floor", let room?): toggleLight(room)
            case ("curtains", let room?): toggleCurtains(room)
            case ("tv", _): toggleTV()
            case ("coffee", _): toggleCoffee()
            case ("door", _): toggleDoor()
            default: break
            }
        }
    }
}
