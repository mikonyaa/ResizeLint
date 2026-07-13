import SwiftUI

struct ContentView: View {
    @State private var mode: DemoMode = .legacy
    @State private var scenario: ResizeScenario = .gallery
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HeroHeader(mode: mode)
                    modeControls
                    scenarioPicker
                    demoSurface
                    FindingCard(mode: mode, scenario: scenario, reduceTransparency: reduceTransparency)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .background(background)
            .navigationTitle("ResizeLab")
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(mode.color)
    }

    private var modePicker: some View {
        Picker("Implementation", selection: $mode) {
            ForEach(DemoMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("mode-picker")
        .accessibilityHint("Switch between the fragile and responsive implementations")
    }

    @ViewBuilder private var modeControls: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 10) {
                ForEach(DemoMode.allCases) { item in
                    Button {
                        mode = item
                    } label: {
                        HStack {
                            Text(item.title)
                                .font(.headline)
                            Spacer()
                            if mode == item {
                                Image(systemName: "checkmark.circle.fill")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(item == mode ? item.color.opacity(0.18) : Color.secondary.opacity(0.08))
                        .clipShape(.rect(cornerRadius: 16))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(item == mode ? item.color : .clear, lineWidth: 1.5)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("mode-\(item.rawValue)")
                    .accessibilityAddTraits(item == mode ? .isSelected : [])
                }
            }
        } else {
            modePicker
        }
    }

    private var scenarioPicker: some View {
        LazyVGrid(columns: scenarioColumns, spacing: 10) {
            ForEach(ResizeScenario.allCases) { item in
                Button {
                    scenario = item
                } label: {
                    Label(item.title, systemImage: item.symbol)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .background(item == scenario ? mode.color.opacity(0.18) : Color.secondary.opacity(0.08))
                        .clipShape(.rect(cornerRadius: 16))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(item == scenario ? mode.color : .clear, lineWidth: 1.5)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("scenario-\(item.rawValue)")
                .accessibilityLabel("\(item.title) scenario")
                .accessibilityAddTraits(item == scenario ? .isSelected : [])
            }
        }
    }

    private var scenarioColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 10),
            count: dynamicTypeSize.isAccessibilitySize ? 1 : 2
        )
    }

    private var demoSurface: some View {
        Group {
            if mode == .legacy {
                LegacyDemoView(scenario: scenario)
            } else {
                AdaptiveDemoView(scenario: scenario)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 330)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: ResizeLabPalette.ink.opacity(0.10), radius: 18, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("demo-surface")
        .accessibilityLabel("\(mode.title) \(scenario.title) demonstration")
    }

    private var background: some View {
        LinearGradient(
            colors: [mode.color.opacity(0.10), Color(uiColor: .systemBackground), ResizeLabPalette.signal.opacity(0.06)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

private struct HeroHeader: View {
    let mode: DemoMode
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 8) {
                    Circle().fill(mode.color).frame(width: 9, height: 9)
                    Text("LIVE RESIZE STUDY")
                        .font(.caption.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(.secondary)
                }
            }
            Text(dynamicTypeSize.isAccessibilitySize ? "Same content, different assumptions." : "Same content.\nDifferent assumptions.")
                .font(.system(dynamicTypeSize.isAccessibilitySize ? .title2 : .largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)
            Text(dynamicTypeSize.isAccessibilitySize ? "Compare how each layout responds." : "Change the implementation and compare how each layout responds to its container.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 10)
    }
}

private struct FindingCard: View {
    let mode: DemoMode
    let scenario: ResizeScenario
    let reduceTransparency: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(mode == .legacy ? scenario.ruleID : "PASS")
                .font(.system(.caption, design: .monospaced, weight: .bold))
                .foregroundStyle(mode.color)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(mode.color.opacity(0.14))
                .clipShape(.capsule)
            VStack(alignment: .leading, spacing: 5) {
                Text(mode == .legacy ? "ResizeLint catches this" : "Container-driven layout")
                    .font(.headline)
                Text(mode == .legacy ? scenario.legacyExplanation : scenario.adaptiveExplanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background {
            if reduceTransparency {
                Color(uiColor: .secondarySystemBackground)
            } else {
                Rectangle().fill(.thinMaterial)
            }
        }
        .clipShape(.rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("finding-card")
    }
}

#Preview("Compact") {
    ContentView()
        .frame(width: 320, height: 720)
}

#Preview("Square") {
    ContentView()
        .frame(width: 700, height: 700)
}

#Preview("Wide") {
    ContentView()
        .frame(width: 1_000, height: 700)
}
