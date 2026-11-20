import SwiftUI

/// The 3D house, with a strip of room cards underneath and the agent one tap away
/// in a half-height sheet, so you can watch the house change while it works.
struct ContentView: View {
    @Environment(Home.self) private var home
    @State private var showAgent = false

    var body: some View {
        NavigationStack {
            HouseView()
                // While the chat is open, squeeze the 3D view into the top half so the sheet never hides the house.
                .padding(.bottom, showAgent ? 330 : 0)
                .animation(.smooth, value: showAgent)
                .ignoresSafeArea(edges: .bottom)
                .background(
                    LinearGradient(colors: [Color(red: 0.12, green: 0.14, blue: 0.26), Color(red: 0.30, green: 0.26, blue: 0.40)],
                                   startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea()
                )
                .safeAreaInset(edge: .bottom) { roomStrip }
                .navigationTitle("Smart Home")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    Button("Reset", systemImage: "arrow.counterclockwise") {
                        withAnimation { home.reset() }
                    }
                }
        }
        .sheet(isPresented: $showAgent) {
            AgentPanel()
                .presentationDetents([.fraction(0.45), .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.45)))
        }
    }

    private var roomStrip: some View {
        VStack(spacing: 0) {
            cards
            Button { showAgent = true } label: {
                Label("Ask the House", systemImage: "sparkles")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
    }

    private var cards: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(home.rooms) { room in
                    RoomCard(room: room)
                }
                DeviceCard(title: "TV", symbol: home.tvOn ? "tv.fill" : "tv", isOn: home.tvOn)
                DeviceCard(title: "Coffee", symbol: "cup.and.saucer.fill", isOn: home.coffeeOn)
                DeviceCard(title: home.doorLocked ? "Locked" : "Unlocked",
                           symbol: home.doorLocked ? "lock.fill" : "lock.open.fill", isOn: !home.doorLocked)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }
}

/// One room: name, light and temperature. Tapping it switches the light, like tapping the room in 3D.
struct RoomCard: View {
    @Environment(Home.self) private var home
    let room: Room

    var body: some View {
        Button {
            withAnimation { home.toggleLight(room.id) }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Label(room.id.name, systemImage: room.id.symbol)
                    .font(.caption.weight(.semibold))
                HStack(spacing: 8) {
                    Image(systemName: room.lightOn ? "lightbulb.fill" : "lightbulb")
                        .foregroundStyle(room.lightOn ? .yellow : .secondary)
                        .contentTransition(.symbolEffect(.replace))
                    Text("\(Int(room.temperature))°")
                    if let open = room.curtainsOpen {
                        Image(systemName: open ? "curtains.open" : "curtains.closed")
                    }
                }
                .font(.caption)
            }
            .padding(10)
            .frame(minWidth: 110, alignment: .leading)
            .background(room.lightOn ? Color.yellow.opacity(0.18) : Color.primary.opacity(0.06), in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

struct DeviceCard: View {
    let title: String
    let symbol: String
    let isOn: Bool

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .foregroundStyle(isOn ? .orange : .secondary)
                .contentTransition(.symbolEffect(.replace))
            Text(title).font(.caption)
        }
        .padding(10)
        .frame(minWidth: 70)
        .background(isOn ? Color.orange.opacity(0.15) : Color.primary.opacity(0.06), in: .rect(cornerRadius: 12))
    }
}
