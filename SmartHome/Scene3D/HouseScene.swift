import RealityKit
import UIKit

/// The 3D dollhouse, built entirely from simple shapes in code.
///
/// The house is 8 m wide (x: -4…4) and 6 m deep (z: -3…3), with the floor at y = 0.
/// The back and left walls are full height; the front, right and inner walls are cut low,
/// like a dollhouse, so you can look into every room from above.
///
/// `build()` makes the entities once. `apply(_:)` updates them whenever the `Home` changes.
@MainActor
final class HouseScene {
    /// Everything: the garden plus the building.
    let root = Entity()
    /// Just the house, without the garden. The orbit camera frames and circles this.
    let building = Entity()
    /// The lawn and the path. Hidden in AR, where the real table is the ground.
    private let garden = Entity()

    /// Show or hide the lawn around the house.
    var showsGarden: Bool {
        get { garden.isEnabled }
        set { garden.isEnabled = newValue }
    }

    private var roomLights: [RoomID: PointLightComponent] = [:]
    private var roomLightEntities: [RoomID: Entity] = [:]
    private var bulbs: [RoomID: ModelEntity] = [:]
    private var halos: [RoomID: ModelEntity] = [:]
    private var floorTiles: [RoomID: ModelEntity] = [:]
    private var curtains: [RoomID: Curtains] = [:]
    private var tvScreen = ModelEntity()
    private var coffeeLight = ModelEntity()
    private var doorPivot = Entity()
    private var doorLight = ModelEntity()
    private var last: HomeSnapshot?

    private struct Curtains {
        let left: ModelEntity
        let right: ModelEntity
        let closed: (left: Transform, right: Transform)
        let open: (left: Transform, right: Transform)
    }

    // MARK: - Colours

    private enum Palette {
        static let wall = UIColor(red: 0.94, green: 0.92, blue: 0.88, alpha: 1)
        static let wallTop = UIColor(red: 0.55, green: 0.50, blue: 0.46, alpha: 1)
        static let grass = UIColor(red: 0.42, green: 0.62, blue: 0.38, alpha: 1)
        static let glass = UIColor(red: 0.62, green: 0.80, blue: 0.95, alpha: 1)
        static let wood = UIColor(red: 0.55, green: 0.38, blue: 0.24, alpha: 1)
        static let dark = UIColor(red: 0.18, green: 0.18, blue: 0.20, alpha: 1)
        static let white = UIColor(red: 0.96, green: 0.96, blue: 0.96, alpha: 1)
        static let warmLight = UIColor(red: 1.0, green: 0.82, blue: 0.55, alpha: 1)
        static let bulbOff = UIColor(red: 0.70, green: 0.70, blue: 0.68, alpha: 1)

        static func floor(_ room: RoomID) -> UIColor {
            switch room {
            case .livingRoom: UIColor(red: 0.74, green: 0.55, blue: 0.37, alpha: 1)
            case .kitchen: UIColor(red: 0.86, green: 0.86, blue: 0.82, alpha: 1)
            case .bedroom: UIColor(red: 0.62, green: 0.66, blue: 0.80, alpha: 1)
            case .bathroom: UIColor(red: 0.68, green: 0.87, blue: 0.85, alpha: 1)
            case .hallway: UIColor(red: 0.62, green: 0.60, blue: 0.58, alpha: 1)
            }
        }
    }

    // MARK: - Layout

    /// Each room's floor: x from…to, z from…to.
    private static let floors: [RoomID: (x: ClosedRange<Float>, z: ClosedRange<Float>)] = [
        .livingRoom: (-4...0, -3...0),
        .kitchen: (0...4, -3...0),
        .bedroom: (-4...(-1), 0...3),
        .bathroom: (-1...1.5, 0...3),
        .hallway: (1.5...4, 0...3),
    ]

    private static func center(of room: RoomID) -> SIMD3<Float> {
        let f = floors[room]!
        return [(f.x.lowerBound + f.x.upperBound) / 2, 0, (f.z.lowerBound + f.z.upperBound) / 2]
    }

    // MARK: - Build

    func build() {
        root.addChild(building)

        buildGround()
        buildFloors()
        buildWalls()
        buildWindowsAndCurtains()
        buildFurniture()
        buildLamps()
        buildDoor()

        // A soft "moonlight" so rooms with the light off are dim, not black.
        let moon = DirectionalLight()
        moon.light.intensity = 700
        moon.light.color = UIColor(red: 0.75, green: 0.82, blue: 1.0, alpha: 1)
        moon.shadow = DirectionalLightComponent.Shadow(maximumDistance: 20, depthBias: 2)
        moon.look(at: .zero, from: [-4, 10, 6], relativeTo: nil)
        root.addChild(moon)
    }

    private func buildGround() {
        root.addChild(garden)
        garden.addChild(box([16, 0.02, 14], at: [0, -0.02, 0], Palette.grass))
        // A path to the front door.
        garden.addChild(box([0.9, 0.02, 2.5], at: [2.85, -0.005, 4.3], UIColor(red: 0.78, green: 0.74, blue: 0.66, alpha: 1)))
    }

    private func buildFloors() {
        for (room, f) in Self.floors {
            let size: SIMD3<Float> = [f.x.upperBound - f.x.lowerBound, 0.06, f.z.upperBound - f.z.lowerBound]
            let floor = box(size, at: Self.center(of: room) + [0, 0.03, 0], Palette.floor(room))
            makeTappable(floor, name: "floor.\(room.rawValue)")
            building.addChild(floor)
            floorTiles[room] = floor
        }
    }

    private func buildWalls() {
        let tall: Float = 2.4, low: Float = 0.45, inner: Float = 1.0
        // Outside: back and left are full height, front and right are cut low.
        wall(from: [-4, -3], to: [4, -3], height: tall)
        wall(from: [-4, -3], to: [-4, 3], height: tall)
        wall(from: [4, -3], to: [4, 3], height: low)
        wall(from: [-4, 3], to: [2.4, 3], height: low)
        wall(from: [3.3, 3], to: [4, 3], height: low)
        // Front door frame.
        wall(from: [2.4, 3], to: [2.4, 3], height: 2.15, thickness: 0.12)
        wall(from: [3.3, 3], to: [3.3, 3], height: 2.15, thickness: 0.12)
        building.addChild(box([1.02, 0.12, 0.12], at: [2.85, 2.15, 3], Palette.wall))
        // Inside, with gaps for doorways.
        wall(from: [-4, 0], to: [-2.8, 0], height: inner)
        wall(from: [-2.0, 0], to: [2.2, 0], height: inner)
        wall(from: [3.2, 0], to: [4, 0], height: inner)
        wall(from: [0, -3], to: [0, -1.6], height: inner)
        wall(from: [-1, 0], to: [-1, 3], height: inner)
        wall(from: [1.5, 0], to: [1.5, 1.2], height: inner)
        wall(from: [1.5, 2.0], to: [1.5, 3], height: inner)
    }

    private func buildWindowsAndCurtains() {
        // Living room: back wall. Kitchen: back wall, no curtains. Bedroom: left wall.
        window(center: [-1.0, 1.4, -2.94], width: 1.2, alongX: true)
        window(center: [2.0, 1.55, -2.94], width: 1.1, alongX: true)
        window(center: [-3.94, 1.4, 1.6], width: 1.2, alongX: false)

        curtains[.livingRoom] = makeCurtains(center: [-1.0, 1.4, -2.88], width: 1.4, alongX: true,
                                             color: UIColor(red: 0.80, green: 0.42, blue: 0.32, alpha: 1), room: .livingRoom)
        curtains[.bedroom] = makeCurtains(center: [-3.88, 1.4, 1.6], width: 1.4, alongX: false,
                                          color: UIColor(red: 0.60, green: 0.52, blue: 0.80, alpha: 1), room: .bedroom)
    }

    private func buildFurniture() {
        // Living room: sofa facing the TV, coffee table, TV on a stand.
        building.addChild(box([1.7, 0.42, 0.75], at: [-2.6, 0.27, -0.75], UIColor(red: 0.30, green: 0.45, blue: 0.62, alpha: 1)))
        building.addChild(box([1.7, 0.55, 0.18], at: [-2.6, 0.62, -0.42], UIColor(red: 0.27, green: 0.40, blue: 0.57, alpha: 1)))
        building.addChild(box([0.9, 0.32, 0.5], at: [-2.6, 0.22, -1.7], Palette.wood))
        building.addChild(box([1.3, 0.45, 0.4], at: [-2.6, 0.28, -2.7], Palette.dark))
        tvScreen = box([1.2, 0.68, 0.05], at: [-2.6, 0.9, -2.78], Palette.dark)
        makeTappable(tvScreen, name: "tv")
        building.addChild(tvScreen)

        // Kitchen: counter along the back wall, island, coffee machine.
        building.addChild(box([3.4, 0.88, 0.6], at: [2.0, 0.47, -2.65], Palette.white))
        building.addChild(box([3.45, 0.05, 0.64], at: [2.0, 0.93, -2.65], Palette.dark))
        building.addChild(box([1.4, 0.88, 0.75], at: [2.0, 0.47, -1.15], Palette.wood))
        let coffee = box([0.28, 0.38, 0.28], at: [3.3, 1.14, -2.7], UIColor(red: 0.75, green: 0.15, blue: 0.15, alpha: 1))
        makeTappable(coffee, name: "coffee")
        building.addChild(coffee)
        coffeeLight = sphere(radius: 0.045, at: [3.3, 1.18, -2.55], Palette.bulbOff)
        makeTappable(coffeeLight, name: "coffee")
        building.addChild(coffeeLight)

        // Bedroom: bed with a blanket and pillow, nightstand.
        building.addChild(box([1.5, 0.35, 2.0], at: [-3.0, 0.24, 1.75], Palette.wood))
        building.addChild(box([1.4, 0.16, 1.9], at: [-3.0, 0.5, 1.75], Palette.white))
        building.addChild(box([1.44, 0.06, 1.2], at: [-3.0, 0.6, 2.1], UIColor(red: 0.85, green: 0.55, blue: 0.60, alpha: 1)))
        building.addChild(box([1.0, 0.12, 0.35], at: [-3.0, 0.63, 0.98], Palette.white))
        building.addChild(box([0.45, 0.5, 0.4], at: [-1.6, 0.31, 0.45], Palette.wood))

        // Bathroom: bathtub with water, sink.
        building.addChild(box([1.7, 0.5, 0.8], at: [0.25, 0.31, 2.5], Palette.white))
        building.addChild(box([1.5, 0.02, 0.6], at: [0.25, 0.55, 2.5], Palette.glass))
        building.addChild(box([0.55, 0.85, 0.42], at: [-0.55, 0.48, 0.35], Palette.white))

        // Hallway: rug and shoe rack.
        building.addChild(box([0.9, 0.01, 1.5], at: [2.85, 0.065, 2.0], UIColor(red: 0.70, green: 0.25, blue: 0.25, alpha: 1)))
        building.addChild(box([0.35, 0.5, 0.9], at: [3.72, 0.31, 1.0], Palette.wood))
    }

    /// A standing lamp in every room (the bulb you can tap) and a point light that lights the room.
    private func buildLamps() {
        let spots: [RoomID: SIMD2<Float>] = [
            .livingRoom: [-0.6, -0.5],
            .kitchen: [0.5, -0.5],
            .bedroom: [-1.5, 2.6],
            .bathroom: [1.15, 0.4],
            .hallway: [3.7, 2.6],
        ]
        for (room, spot) in spots {
            building.addChild(cylinder(height: 0.04, radius: 0.16, at: [spot.x, 0.08, spot.y], Palette.dark))
            building.addChild(cylinder(height: 1.25, radius: 0.025, at: [spot.x, 0.68, spot.y], Palette.dark))
            let bulb = sphere(radius: 0.14, at: [spot.x, 1.38, spot.y], Palette.bulbOff)
            makeTappable(bulb, name: "light.\(room.rawValue)")
            building.addChild(bulb)
            bulbs[room] = bulb

            // A soft glow around the bulb, only visible while the light is on.
            var glow = UnlitMaterial(color: Palette.warmLight)
            glow.blending = .transparent(opacity: 0.3)
            let halo = ModelEntity(mesh: .generateSphere(radius: 0.32), materials: [glow])
            halo.position = bulb.position
            halo.isEnabled = false
            building.addChild(halo)
            halos[room] = halo

            let lightEntity = Entity()
            lightEntity.position = Self.center(of: room) + [0, 1.9, 0]
            let light = PointLightComponent(color: Palette.warmLight, intensity: 0, attenuationRadius: 3.8)
            lightEntity.components.set(light)
            building.addChild(lightEntity)
            roomLights[room] = light
            roomLightEntities[room] = lightEntity
        }
    }

    private func buildDoor() {
        doorPivot.position = [2.46, 0.06, 3.0]
        let panel = box([0.78, 2.02, 0.06], at: [0.39, 1.01, 0], UIColor(red: 0.45, green: 0.28, blue: 0.18, alpha: 1))
        makeTappable(panel, name: "door")
        doorPivot.addChild(panel)
        doorPivot.addChild(sphere(radius: 0.035, at: [0.68, 1.0, 0.05], UIColor(red: 0.85, green: 0.70, blue: 0.30, alpha: 1)))
        building.addChild(doorPivot)

        doorLight = sphere(radius: 0.06, at: [2.85, 2.35, 3.05], Palette.bulbOff)
        makeTappable(doorLight, name: "door")
        building.addChild(doorLight)
    }

    // MARK: - Update

    /// Makes the 3D house match the `Home`. Changes animate, except the very first time.
    func apply(_ home: HomeSnapshot) {
        guard home != last else { return }
        let animated = last != nil
        let duration: TimeInterval = animated ? 0.6 : 0

        for room in home.rooms {
            let level = Float(room.brightness)
            if var light = roomLights[room.id], let entity = roomLightEntities[room.id] {
                light.intensity = room.lightOn ? 22000 * level : 0
                entity.components.set(light)
                roomLights[room.id] = light
            }
            bulbs[room.id]?.model?.materials = [
                room.lightOn
                    ? UnlitMaterial(color: UIColor(red: 1.0, green: 0.9, blue: 0.5, alpha: 1).adjusted(brightness: CGFloat(0.6 + 0.4 * level)))
                    : SimpleMaterial(color: Palette.bulbOff, roughness: 0.4, isMetallic: false),
            ]
            halos[room.id]?.isEnabled = room.lightOn
            // Lit rooms glow warm; dark rooms look like night. Easy to read at a glance.
            let base = Palette.floor(room.id)
            floorTiles[room.id]?.model?.materials = [
                SimpleMaterial(color: room.lightOn ? base.blended(with: Palette.warmLight, amount: 0.25 * CGFloat(level))
                                                   : base.adjusted(brightness: 0.45),
                               roughness: 0.8, isMetallic: false),
            ]
            if let open = room.curtainsOpen, let c = curtains[room.id] {
                let target = open ? c.open : c.closed
                c.left.move(to: target.left, relativeTo: c.left.parent, duration: duration)
                c.right.move(to: target.right, relativeTo: c.right.parent, duration: duration)
            }
        }

        tvScreen.model?.materials = [
            home.tvOn ? UnlitMaterial(color: UIColor(red: 0.35, green: 0.65, blue: 1.0, alpha: 1))
                      : SimpleMaterial(color: Palette.dark, roughness: 0.2, isMetallic: false),
        ]
        coffeeLight.model?.materials = [
            home.coffeeOn ? UnlitMaterial(color: .orange) : SimpleMaterial(color: Palette.bulbOff, roughness: 0.4, isMetallic: false),
        ]

        // Locked: closed with a red light. Unlocked: ajar with a green light.
        var door = doorPivot.transform
        door.rotation = simd_quatf(angle: home.doorLocked ? 0 : .pi * 0.38, axis: [0, 1, 0])
        doorPivot.move(to: door, relativeTo: doorPivot.parent, duration: duration)
        doorLight.model?.materials = [UnlitMaterial(color: home.doorLocked ? .systemRed : .systemGreen)]

        last = home
    }

    // MARK: - Shape helpers

    private func box(_ size: SIMD3<Float>, at position: SIMD3<Float>, _ color: UIColor) -> ModelEntity {
        let entity = ModelEntity(mesh: .generateBox(size: size, cornerRadius: min(size.x, size.y, size.z) * 0.15),
                                 materials: [SimpleMaterial(color: color, roughness: 0.8, isMetallic: false)])
        entity.position = position
        return entity
    }

    private func sphere(radius: Float, at position: SIMD3<Float>, _ color: UIColor) -> ModelEntity {
        let entity = ModelEntity(mesh: .generateSphere(radius: radius),
                                 materials: [SimpleMaterial(color: color, roughness: 0.4, isMetallic: false)])
        entity.position = position
        return entity
    }

    private func cylinder(height: Float, radius: Float, at position: SIMD3<Float>, _ color: UIColor) -> ModelEntity {
        let entity = ModelEntity(mesh: .generateCylinder(height: height, radius: radius),
                                 materials: [SimpleMaterial(color: color, roughness: 0.5, isMetallic: true)])
        entity.position = position
        return entity
    }

    /// An axis-aligned wall between two floor points, with a darker cap on top.
    private func wall(from a: SIMD2<Float>, to b: SIMD2<Float>, height: Float, thickness: Float = 0.1) {
        let length = max(abs(b.x - a.x), abs(b.y - a.y)) + thickness
        let alongX = abs(b.x - a.x) >= abs(b.y - a.y)
        let size: SIMD3<Float> = alongX ? [length, height, thickness] : [thickness, height, length]
        let mid: SIMD3<Float> = [(a.x + b.x) / 2, height / 2, (a.y + b.y) / 2]
        building.addChild(box(size, at: mid, Palette.wall))
        building.addChild(box([size.x + 0.01, 0.03, size.z + 0.01], at: [mid.x, height, mid.z], Palette.wallTop))
    }

    private func window(center: SIMD3<Float>, width: Float, alongX: Bool) {
        let size: SIMD3<Float> = alongX ? [width, 0.9, 0.03] : [0.03, 0.9, width]
        building.addChild(ModelEntity(mesh: .generateBox(size: size), materials: [UnlitMaterial(color: Palette.glass)]).placed(at: center))
        let frame: SIMD3<Float> = alongX ? [width + 0.1, 0.06, 0.06] : [0.06, 0.06, width + 0.1]
        building.addChild(box(frame, at: center + [0, -0.48, 0], Palette.white))
    }

    /// Two panels that meet in the middle when closed and bunch up at the sides when open.
    private func makeCurtains(center: SIMD3<Float>, width: Float, alongX: Bool, color: UIColor, room: RoomID) -> Curtains {
        let half = width / 2
        let size: SIMD3<Float> = alongX ? [half, 1.2, 0.04] : [0.04, 1.2, half]
        let axis: SIMD3<Float> = alongX ? [1, 0, 0] : [0, 0, 1]
        let squash: SIMD3<Float> = alongX ? [0.3, 1, 1] : [1, 1, 0.3]

        func panel(side: Float) -> (ModelEntity, Transform, Transform) {
            let entity = box(size, at: .zero, color)
            makeTappable(entity, name: "curtains.\(room.rawValue)")
            let closed = Transform(translation: center + axis * (side * half / 2))
            let open = Transform(scale: squash, translation: center + axis * (side * (half - half * 0.15)))
            building.addChild(entity)
            return (entity, closed, open)
        }
        let (left, leftClosed, leftOpen) = panel(side: -1)
        let (right, rightClosed, rightOpen) = panel(side: 1)
        return Curtains(left: left, right: right, closed: (leftClosed, rightClosed), open: (leftOpen, rightOpen))
    }

    /// Lets a tap find this entity by name.
    private func makeTappable(_ entity: ModelEntity, name: String) {
        entity.name = name
        entity.generateCollisionShapes(recursive: false)
        entity.components.set(InputTargetComponent())
    }
}

private extension Entity {
    func placed(at position: SIMD3<Float>) -> Self {
        self.position = position
        return self
    }
}

private extension UIColor {
    func adjusted(brightness factor: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return UIColor(hue: h, saturation: s, brightness: b * factor, alpha: a)
    }

    func blended(with other: UIColor, amount t: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, alpha: 1)
    }
}
