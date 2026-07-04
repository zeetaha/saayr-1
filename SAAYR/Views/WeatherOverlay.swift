import SwiftUI
import CoreLocation
import Combine

// MARK: - Condition

enum WeatherCondition: Equatable {
    case clear, cloudy, rain, drizzle, thunderstorm, fog, dust, night
}

// MARK: - Weather Data

struct WeatherData {
    let tempC: Double
    let feelsLikeC: Double
    let humidity: Int
    let windKph: Double
    let description: String
    let condition: WeatherCondition

    var conditionEmoji: String {
        switch condition {
        case .clear:        return "☀️"
        case .cloudy:       return "⛅"
        case .rain:         return "🌧️"
        case .drizzle:      return "🌦️"
        case .thunderstorm: return "⛈️"
        case .fog:          return "🌫️"
        case .dust:         return "🌪️"
        case .night:        return "🌙"
        }
    }
}

// MARK: - Manager

class WeatherManager: ObservableObject {
    @Published var condition: WeatherCondition = .clear
    @Published var data: WeatherData? = nil

    private var lastCoord: CLLocationCoordinate2D?
    private var lastFetch: Date?
    private let minInterval: TimeInterval = 600     // re-fetch at most every 10 min
    private let minDistanceM: Double     = 5_000    // or if moved >5 km

    func update(coordinate: CLLocationCoordinate2D) {
        if let last = lastFetch, Date().timeIntervalSince(last) < minInterval,
           let lc = lastCoord,
           CLLocation(latitude: lc.latitude, longitude: lc.longitude)
               .distance(from: CLLocation(latitude: coordinate.latitude,
                                          longitude: coordinate.longitude)) < minDistanceM {
            return
        }
        lastFetch = Date()
        lastCoord = coordinate

        let key = WebService.openWeatherApiKey
        guard !key.isEmpty else { return }

        let urlStr = "https://api.openweathermap.org/data/2.5/weather"
            + "?lat=\(coordinate.latitude)&lon=\(coordinate.longitude)&appid=\(key)&units=metric"
        guard let url = URL(string: urlStr) else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard
                let data,
                let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let weather = (json["weather"] as? [[String: Any]])?.first,
                let id      = weather["id"] as? Int
            else { return }

            let sys     = json["sys"] as? [String: Any]
            let sunrise = sys?["sunrise"] as? TimeInterval ?? 0
            let sunset  = sys?["sunset"]  as? TimeInterval ?? 0
            let now     = Date().timeIntervalSince1970
            let isNight = now < sunrise || now > sunset
            let cond    = Self.classify(id: id, isNight: isNight)

            let main      = json["main"] as? [String: Any]
            let tempC     = main?["temp"]       as? Double ?? 0
            let feelsLike = main?["feels_like"] as? Double ?? 0
            let humidity  = main?["humidity"]   as? Int    ?? 0
            let wind      = json["wind"] as? [String: Any]
            let windKph   = (wind?["speed"] as? Double ?? 0) * 3.6
            let desc      = (weather["description"] as? String ?? "").capitalized

            DispatchQueue.main.async {
                self?.condition = cond
                self?.data = WeatherData(
                    tempC: tempC,
                    feelsLikeC: feelsLike,
                    humidity: humidity,
                    windKph: windKph,
                    description: desc,
                    condition: cond
                )
            }
        }.resume()
    }

    // Maps OpenWeatherMap condition codes → WeatherCondition
    // Full code list: https://openweathermap.org/weather-conditions
    private static func classify(id: Int, isNight: Bool) -> WeatherCondition {
        switch id {
        case 200...232:                        return .thunderstorm
        case 300...321:                        return .drizzle
        case 500...531:                        return .rain
        case 701, 711, 721:                    return .fog
        case 731, 751, 761, 762, 771, 781:     return .dust   // sand/dust/tornado
        case 741:                              return .fog
        case 800:                              return isNight ? .night : .clear
        case 801...804:                        return isNight ? .night : .cloudy
        default:                               return isNight ? .night : .clear
        }
    }
}

// MARK: - Weather Mini Widget (embedded in map header)

struct WeatherMiniWidget: View {
    let data: WeatherData

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            HStack(spacing: 4) {
                Text(data.conditionEmoji)
                    .font(.system(size: 22))
                Text("\(Int(data.tempC.rounded()))°C")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.black)
            }
            Text(data.description)
                .font(.system(size: 10))
                .foregroundColor(.gray)
                .lineLimit(1)
            HStack(spacing: 10) {
                HStack(spacing: 3) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 9))
                        .foregroundColor(Color(red: 0.3, green: 0.6, blue: 1.0))
                    Text("\(data.humidity)%")
                }
                HStack(spacing: 3) {
                    Image(systemName: "wind")
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                    Text("\(Int(data.windKph.rounded())) km/h")
                }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.gray)
        }
    }
}

// MARK: - Container

struct WeatherOverlayView: View {
    let condition: WeatherCondition

    var body: some View {
        ZStack { overlayContent }
            .allowsHitTesting(false)
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 1.2), value: condition)
    }

    @ViewBuilder
    private var overlayContent: some View {
        switch condition {
        case .cloudy:        CloudyOverlay()
        case .rain:          RainOverlay(intensity: 1.0)
        case .drizzle:       RainOverlay(intensity: 0.4)
        case .thunderstorm:  ThunderstormOverlay()
        case .fog:           FogOverlay()
        case .dust:          DustOverlay()
        case .night:         NightOverlay()
        default:             Color.clear
        }
    }
}

// MARK: - Cloudy
// Fluffy cloud shapes drift slowly left → right across the top ~20% of the screen.
// Nothing covers the rest of the map.

struct CloudyOverlay: View {
    // (yFrac, speed pts/s, size scale, opacity, x phase offset)
    private let specs: [(y: Double, spd: Double, sc: Double, a: Double, off: Double)] = [
        (0.04, 13, 1.10, 0.20,   0),
        (0.13,  9, 0.80, 0.15, 240),
        (0.07, 17, 0.90, 0.17, 430),
        (0.19, 11, 0.65, 0.12, 150),
        (0.10, 20, 0.55, 0.09, 340),
    ]
    // Puff shapes: (dx, dy, radius) relative to cloud centre
    private let puffs: [(Double, Double, Double)] = [
        (0, 0, 40), (-30, 9, 28), (30, 9, 28), (-15, -16, 33), (15, -16, 33), (-46, 16, 20), (46, 16, 20)
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                for s in specs {
                    let lane = size.width + 360.0
                    let cx   = ((t * s.spd + s.off).truncatingRemainder(dividingBy: lane)) - 180
                    let cy   = size.height * s.y
                    for (dx, dy, r) in puffs {
                        let pr = r * s.sc
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: cx + dx * s.sc - pr,
                                                   y: cy + dy * s.sc - pr,
                                                   width: pr * 2, height: pr * 2)),
                            with: .color(.white.opacity(s.a))
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

// MARK: - Rain
// Sparse diagonal streaks falling from the top. Low opacity so the map stays readable.

struct RainOverlay: View {
    let intensity: Double   // 0…1

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
            Canvas { ctx, size in
                let t     = tl.date.timeIntervalSinceReferenceDate
                let count = Int(38 * intensity) + 8
                for i in 0..<count {
                    let f     = Double(i)
                    let x     = (f * 173.7 + 17.3).truncatingRemainder(dividingBy: size.width)
                    let speed = 380 + (f * 67.3).truncatingRemainder(dividingBy: 160)
                    let y     = (t * speed + f * 53.7).truncatingRemainder(dividingBy: size.height + 18) - 18
                    let alpha = (0.07 + (f * 0.04).truncatingRemainder(dividingBy: 0.09)) * intensity
                    var path  = Path()
                    path.move(to: CGPoint(x: x,      y: y))
                    path.addLine(to: CGPoint(x: x - 2.5, y: y - 16))
                    ctx.stroke(path,
                               with: .color(Color(red: 0.60, green: 0.78, blue: 1.0).opacity(alpha)),
                               lineWidth: 1.0)
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

// MARK: - Thunderstorm
// Dark cloud band at the very top + rain + occasional white flash.

struct ThunderstormOverlay: View {
    @State private var flashOpacity: Double = 0

    var body: some View {
        ZStack {
            // Storm cloud gradient — fades out after top 30% of screen
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.07, blue: 0.22).opacity(0.50),
                    Color(red: 0.07, green: 0.07, blue: 0.22).opacity(0.14),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.30)
            )
            .ignoresSafeArea()

            RainOverlay(intensity: 1.0)

            Color.white.opacity(flashOpacity).ignoresSafeArea()
        }
        .allowsHitTesting(false)
        .onAppear { scheduleFlash() }
    }

    private func scheduleFlash() {
        let delay = Double.random(in: 4...11)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.easeIn(duration: 0.04))  { flashOpacity = 0.42 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) {
                withAnimation(.easeOut(duration: 0.18)) { flashOpacity = 0 }
            }
            scheduleFlash()
        }
    }
}

// MARK: - Fog
// Wisps creep in from the left and right edges and pool along the bottom.
// Centre of the map stays clear.

struct FogOverlay: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 10)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate

                // Bottom pool — long flat ellipses
                for i in 0..<8 {
                    let f  = Double(i)
                    let xc = (f / 7.0) * size.width + sin(t * 0.2 + f * 0.9) * 22
                    let yc = size.height * 0.82 + cos(t * 0.15 + f * 0.6) * 12
                    let w  = size.width * 0.38 + (f * 14).truncatingRemainder(dividingBy: size.width * 0.18)
                    let h  = 38 + (f * 8).truncatingRemainder(dividingBy: 28)
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: xc - w / 2, y: yc - h / 2, width: w, height: h)),
                        with: .color(.white.opacity(0.11))
                    )
                }

                // Left-side tendrils
                for i in 0..<5 {
                    let f  = Double(i)
                    let yc = size.height * (0.25 + f * 0.13)
                    let xOff = sin(t * 0.22 + f * 1.1) * 16
                    let w  = size.width * 0.28 + (f * 10).truncatingRemainder(dividingBy: size.width * 0.08)
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: -w * 0.45 + xOff, y: yc - 22, width: w, height: 44)),
                        with: .color(.white.opacity(0.08))
                    )
                }

                // Right-side tendrils
                for i in 0..<5 {
                    let f  = Double(i)
                    let yc = size.height * (0.20 + f * 0.14)
                    let xOff = sin(t * 0.28 + f * 0.8) * 16
                    let w  = size.width * 0.25 + (f * 9).truncatingRemainder(dividingBy: size.width * 0.08)
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: size.width - w * 0.55 + xOff, y: yc - 22, width: w, height: 44)),
                        with: .color(.white.opacity(0.08))
                    )
                }
            }
            .blur(radius: 20)
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

// MARK: - Dust / Sandstorm
// Sandy particles drift right → left, concentrated at the edges.
// Subtle warm haze only at the top — does not paint the whole map.

struct DustOverlay: View {
    var body: some View {
        ZStack {
            // Haze only at the very top (top 30%)
            LinearGradient(
                colors: [
                    Color(red: 0.88, green: 0.66, blue: 0.22).opacity(0.28),
                    Color(red: 0.90, green: 0.70, blue: 0.28).opacity(0.08),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.30)
            )

            TimelineView(.animation(minimumInterval: 1 / 20)) { tl in
                Canvas { ctx, size in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    for i in 0..<65 {
                        let f     = Double(i)
                        let speed = 20 + (f * 3.9).truncatingRemainder(dividingBy: 25)
                        let startX = (f * 57.3).truncatingRemainder(dividingBy: size.width)
                        // Drift right → left
                        let x     = size.width - ((t * speed + startX).truncatingRemainder(dividingBy: size.width + 80))
                        let y     = (f * 89.7).truncatingRemainder(dividingBy: size.height)
                        // Edge fade: full opacity at edges, invisible at centre
                        let centreNorm = abs(x - size.width * 0.5) / (size.width * 0.5)
                        let edgeFade  = max(0, centreNorm - 0.15) / 0.85
                        let r = 2.5 + (f * 1.9).truncatingRemainder(dividingBy: 7)
                        let a = (0.06 + (f * 0.04).truncatingRemainder(dividingBy: 0.11)) * edgeFade
                        guard a > 0.004 else { continue }
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                            with: .color(Color(red: 0.82, green: 0.58, blue: 0.22).opacity(a))
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

// MARK: - Night
// Dark vignette only at the top edge + stars confined to the upper quarter.
// The rest of the map is untouched.

struct NightOverlay: View {
    var body: some View {
        ZStack {
            // Top-edge vignette only
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.04, blue: 0.18).opacity(0.40),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.28)
            )
            .ignoresSafeArea()

            // Stars only in the top 25% — fade out as they approach the map
            Canvas { ctx, size in
                let topBand = size.height * 0.25
                for i in 0..<50 {
                    let f    = Double(i)
                    let x    = (f * 137.5).truncatingRemainder(dividingBy: size.width)
                    let y    = (f * 73.1).truncatingRemainder(dividingBy: topBand)
                    let fade = 1.0 - (y / topBand)       // bright at top, gone at bottom of band
                    let r    = 0.7 + (f * 0.24).truncatingRemainder(dividingBy: 1.2)
                    let a    = (0.55 + (f * 0.12).truncatingRemainder(dividingBy: 0.35)) * fade * 0.75
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                        with: .color(.white.opacity(a))
                    )
                }
            }
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

// MARK: - Preview / Test Harness

#Preview("Weather Conditions") {
    WeatherConditionTestView()
}

private struct WeatherConditionTestView: View {
    private let cases: [(WeatherCondition, String)] = [
        (.clear,        "☀️  Clear"),
        (.cloudy,       "⛅  Cloudy"),
        (.rain,         "🌧️  Rain"),
        (.drizzle,      "🌦️  Drizzle"),
        (.thunderstorm, "⛈️  Thunder"),
        (.fog,          "🌫️  Fog"),
        (.dust,         "🌪️  Dust"),
        (.night,        "🌙  Night"),
    ]
    @State private var selected = 0

    var body: some View {
        ZStack {
            // Simulates the map tile background colour
            Color(red: 0, green: 0, blue: 0).ignoresSafeArea()

            WeatherOverlayView(condition: cases[selected].0)
                .animation(.easeInOut(duration: 0.8), value: selected)

            // Condition label at the top
            VStack {
                Text(cases[selected].1)
                    .font(.system(size: 18, weight: .semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.top, 60)
                Spacer()
            }

            // Pill buttons at the bottom
            VStack {
                Spacer()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(cases.indices, id: \.self) { i in
                            Button {
                                withAnimation { selected = i }
                            } label: {
                                Text(cases[i].1)
                                    .font(.system(size: 13, weight: .medium))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .background(
                                        selected == i
                                            ? Color.blue
                                            : Color.white.opacity(0.85)
                                    )
                                    .foregroundColor(selected == i ? .white : .black)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(.ultraThinMaterial)
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }
}
