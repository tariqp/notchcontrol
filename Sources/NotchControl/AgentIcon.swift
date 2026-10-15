import SwiftUI

/// Vector glyph for a coding agent. Drawn here, not loaded from any other app.
struct AgentIcon: View {
    let agent: String
    var size: CGFloat = 16

    var body: some View {
        Group {
            switch agent.lowercased() {
            case "claude":
                Starburst(rays: 8)
                    .fill(Color(red: 0.85, green: 0.47, blue: 0.34))
            case "gemini":
                FourPointStar()
                    .fill(LinearGradient(colors: [Color(red: 0.31, green: 0.55, blue: 0.98), Color(red: 0.62, green: 0.38, blue: 0.93)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            case "copilot":
                Monogram(text: "Co", background: Color(red: 0.42, green: 0.36, blue: 0.9))
            case "codex", "openai":
                Monogram(text: "Cx", background: Color(white: 0.15), foreground: .white, border: true)
            case "cursor":
                Image(systemName: "cube.fill").resizable().scaledToFit().foregroundStyle(.white)
            case "opencode":
                Monogram(text: ">_", background: Color(white: 0.2), foreground: .green, border: true)
            case "amp":
                Monogram(text: "A", background: Color(red: 0.93, green: 0.3, blue: 0.25))
            case "devin":
                Monogram(text: "D", background: Color(red: 0.2, green: 0.5, blue: 0.95))
            default:
                Image(systemName: "cpu.fill").resizable().scaledToFit().foregroundStyle(.white.opacity(0.8))
            }
        }
        .frame(width: size, height: size)
    }
}

/// Icon plus status: pulses while working, orange ring while waiting, green tick when done.
struct AgentStatusIcon: View {
    let agent: String
    let status: String
    var size: CGFloat = 18

    private var working: Bool { status == "Working" }
    private var waiting: Bool { status.hasPrefix("Waiting") }

    var body: some View {
        ZStack {
            if waiting {
                Circle().stroke(Color.orange, lineWidth: 1.5)
                    .frame(width: size + 6, height: size + 6)
                    .shadow(color: .orange.opacity(0.7), radius: 4)
            }
            Pulse(active: working) {
                AgentIcon(agent: agent, size: size)
            }
            if status == "Done" {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(.white, .green)
                    .offset(x: size * 0.42, y: size * 0.42)
            } else if status == "Failed" {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(.white, .red)
                    .offset(x: size * 0.42, y: size * 0.42)
            }
        }
        .frame(width: size + 8, height: size + 8)
    }
}

/// Gentle breathing animation driven by a timeline, so it never gets stuck.
struct Pulse<Content: View>: View {
    let active: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        if active {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let wave = sin(t * 2.6)
                content()
                    .scaleEffect(1 + 0.1 * wave)
                    .opacity(0.8 + 0.2 * wave)
                    .shadow(color: .white.opacity(0.25 + 0.2 * wave), radius: 3)
            }
        } else {
            content()
        }
    }
}

struct Monogram: View {
    let text: String
    let background: Color
    var foreground: Color = .white
    var border: Bool = false

    var body: some View {
        GeometryReader { g in
            ZStack {
                RoundedRectangle(cornerRadius: g.size.width * 0.28).fill(background)
                if border {
                    RoundedRectangle(cornerRadius: g.size.width * 0.28).stroke(Color.white.opacity(0.35), lineWidth: 1)
                }
                Text(text)
                    .font(.system(size: g.size.width * 0.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(foreground)
                    .minimumScaleFactor(0.5)
            }
        }
    }
}

/// Rays of alternating length radiating from the centre, with rounded tips.
struct Starburst: Shape {
    var rays: Int = 8

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let w = r * 0.3
        for i in 0..<rays {
            let angle = Double(i) * (2 * .pi / Double(rays))
            let length = i % 2 == 0 ? r : r * 0.78
            let ray = Path(roundedRect: CGRect(x: -w / 2, y: -length, width: w, height: length + w * 0.4), cornerRadius: w / 2)
            let t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: angle)
            path.addPath(ray.applying(t))
        }
        path.addEllipse(in: CGRect(x: c.x - w * 0.8, y: c.y - w * 0.8, width: w * 1.6, height: w * 1.6))
        return path
    }
}

struct FourPointStar: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let inner = r * 0.22
        p.move(to: CGPoint(x: c.x, y: c.y - r))
        p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + inner, y: c.y - inner))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + inner, y: c.y + inner))
        p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - inner, y: c.y + inner))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - inner, y: c.y - inner))
        p.closeSubpath()
        return p
    }
}
