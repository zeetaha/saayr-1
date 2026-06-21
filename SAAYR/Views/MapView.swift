import SwiftUI
import MapKit
import Combine
import Kingfisher

struct MapView: View {

    @EnvironmentObject var languageManager: LanguageManager

    @StateObject private var locationManager = LocationManager()
    @StateObject private var weatherManager = WeatherManager()

    @State private var region = MKCoordinateRegion()
    @State private var locations: [NearbyLocationResponse] = []
    @State private var selectedLocation: NearbyLocationResponse?

    // Fog of War
    @State private var fogZones: [Zone] = []
    @State private var fogLoaded = false
    @State private var pendingUnlock: ZoneUnlockInfo? = nil
    @State private var showUnlockPopup = false
    
    @State private var lastFetchCenter: CLLocationCoordinate2D?
    @State private var trackingMode: MapUserTrackingMode = .follow
    
    var equatableCenter: MapCenter {
        MapCenter(
            latitude: region.center.latitude,
            longitude: region.center.longitude
        )
    }
    
    @State var errorMessage: String = ""
    @State var successMessage: String = ""
    @State private var showAlert: Bool = false
    @State private var showSuccessAlert: Bool = false // Separate success indicator
    @State private var checkInSuccess: Bool? = true // nil: pending, true: success, false: failure
    
    
    // MARK: Check-In State
    @State private var isCheckingIn = false
    @State private var isValidating = false
    @State private var elapsedTime = 0
    @State private var progress: Double = 0
    let checkInDuration = 10   // example 5 sec for demo; can be 120
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    
    
    var body: some View {
        ZStack {
            
            // MARK: Map
            Map(
                coordinateRegion: $region,
                interactionModes: .all,
                showsUserLocation: true,
                userTrackingMode: $trackingMode,
                annotationItems: locations
            ) { item in
                MapAnnotation(coordinate: item.coordinate) {
                    MerchantMarkerView(
                        merchant: .init(
                            id: item.id, name: item.name,
                            category: item.category,
                            emoji: "📍",
                            xpReward: item.xp_reward,
                            coordinate: item.coordinate,
                            can_checkin: item.can_checkin,
                            imageUrl: WebService.resolvedImageUrl(item.image_url)
                        ),
                        isInRange: true,
                        isActive: selectedLocation?.id == item.id,
                        isPartner: item.is_partner
                    )
                    .onTapGesture {
                        // Block switching pins while a check-in is in progress
                        guard !isCheckingIn else { return }
                        selectedLocation = item
                    }
                }
            }
            .ignoresSafeArea()

           

            // MARK: Fog of War
            if fogLoaded {
                FogOverlayView(zones: fogZones, region: region)
                    .transition(.opacity)
                    .animation(.easeIn(duration: 0.5), value: fogLoaded)
            }

            // MARK: Weather Overlay
            WeatherOverlayView(condition: weatherManager.condition)
            
            // MARK: HeaderCard - Only show after API response
            if !locations.isEmpty && !showSuccessAlert && !showAlert{
                VStack {
                    HeaderCard(nearbyCount: locations.count, weatherData: weatherManager.data)
                    Spacer()
                }
                .animation(.easeIn, value: locations.count)
            }
            
            if showSuccessAlert {
                VStack {
                    Text(successMessage)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.green)
                        .cornerRadius(8)
                        .padding(.horizontal)
                        .padding(.top, 12) // Safe area padding
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(1)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                                withAnimation {
                                    showSuccessAlert = false
                                    showAlert = false
                                }
                            }
                        }
                    Spacer()
                }
                
            }
            
            // Error Banner
            else if showAlert {
                VStack{
                    Text(errorMessage)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.red)
                        .cornerRadius(8)
                        .padding(.horizontal)
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(1)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                                withAnimation {
                                    showSuccessAlert = false
                                    showAlert = false
                                }
                            }
                        }
                    Spacer()
                }
            }
            
            
            
            
            // MARK: Check-In Progress Card
            if isCheckingIn, let location = selectedLocation {
                CheckInProgressCard(
                    merchant: .init(
                        id: location.id, name: location.name,
                        category: location.category,
                        emoji: "📍",
                        xpReward: location.xp_reward,
                        coordinate: location.coordinate,
                        can_checkin: location.can_checkin,
                        imageUrl: WebService.resolvedImageUrl(location.image_url)
                    ),
                    progress: progress,
                    remaining: checkInDuration - elapsedTime
                ) {
                    resetCheckIn()
                }
            }
            
            
            
            // MARK: Current Location Button
            if !isCheckingIn {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            if let location = locationManager.location {
                                withAnimation {
                                    moveToUser(location)
                                    trackingMode = .follow
                                }
                            }
                        } label: {
                            Image(systemName: "location.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.blue)
                                .frame(width: 48, height: 48)
                                .background(Color.white)
                                .clipShape(Circle())
                                .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, selectedLocation != nil ? 180 : 32)
                    }
                }
            }

            // MARK: Bottom Check-In
            if !isCheckingIn, let location = selectedLocation {
                BottomCheckInCard(
                    merchant: location.asMerchant,
                    isLoading: isValidating
                ) {
                    startCheckIn(location)
                }
            }

            // MARK: Zone Unlock Popup
            if showUnlockPopup, let info = pendingUnlock {
                ZoneUnlockPopup(
                    info: info,
                    isEnglish: languageManager.currentLanguage == .english
                ) { zoneCenter in
                    withAnimation(.easeInOut) {
                        showUnlockPopup = false
                        pendingUnlock = nil
                        region = MKCoordinateRegion(
                            center: zoneCenter,
                            span: .init(latitudeDelta: 0.15, longitudeDelta: 0.15)
                        )
                    }
                    fetchFogZones()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(100)
            }

        }
        .onAppear {
            locationManager.requestPermission()
            fetchFogZones()
        }
        .onReceive(locationManager.$location.compactMap { $0 }) { location in
            moveToUser(location)
            fetchNearby(location.coordinate)
            weatherManager.update(coordinate: location.coordinate)
        }
        
        .onChange(of: equatableCenter) { newCenter in
            handleMapDrag(
                CLLocationCoordinate2D(
                    latitude: newCenter.latitude,
                    longitude: newCenter.longitude
                )
            )
        }
        .onReceive(timer) { _ in
            guard isCheckingIn else { return }
            
            elapsedTime += 1
            progress = Double(elapsedTime) / Double(checkInDuration)
            
            if elapsedTime >= checkInDuration {
                completeCheckIn()
            }
        }
    }
    
    // MARK: Helpers
    
    private func handleMapDrag(_ newCenter: CLLocationCoordinate2D) {
        guard let lastCenter = lastFetchCenter else { return }
        
        let old = CLLocation(latitude: lastCenter.latitude, longitude: lastCenter.longitude)
        let new = CLLocation(latitude: newCenter.latitude, longitude: newCenter.longitude)
        let distanceKM = old.distance(from: new) / 1000
        
        if distanceKM >= 5 {
            fetchNearby(newCenter)
        }
    }
    
    private func moveToUser(_ location: CLLocation) {
        region = MKCoordinateRegion(
            center: location.coordinate,
            span: .init(latitudeDelta: 0.5, longitudeDelta: 0.5)
        )
    }
    
    private func fetchNearby(_ coordinate: CLLocationCoordinate2D) {
        lastFetchCenter = coordinate

        LocationAPI.shared.fetchNearby(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        ) { newItems, unlockInfo in
            let existingIDs = Set(locations.map { $0.id })
            let filtered = newItems.filter { !existingIDs.contains($0.id) }
            locations.append(contentsOf: filtered)

            if let unlock = unlockInfo {
                fetchFogZones()
                pendingUnlock = unlock
                withAnimation { showUnlockPopup = true }
            }
        }
    }

    private func fetchFogZones() {
        ServiceModel.shared.fetchZones { result in
            DispatchQueue.main.async {
                fogLoaded = true
                if case .success(let zones) = result { fogZones = zones }
            }
        }
    }
    
    // MARK: Check-In Actions
    // Step 1: validate with dryRun: false, then show progress card on success
    private func startCheckIn(_ location: NearbyLocationResponse) {
        guard let userLocation = locationManager.location?.coordinate else { return }
        selectedLocation = location
        isValidating = true

        LocationAPI.shared.checkIn(locationId: location.id, userCoordinate: userLocation, dryRun: true) { result in
            isValidating = false
            switch result {
            case .success:
                withAnimation {
                    isCheckingIn = true
                    elapsedTime = 0
                    progress = 0
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
                showAlert = true
                showSuccessAlert = false
                selectedLocation = nil
            }
        }
    }
    
    // Reset check-in state
    private func resetCheckIn() {
        withAnimation {
            isCheckingIn = false
            selectedLocation = nil
            elapsedTime = 0
            progress = 0
        }
    }
    
    // Step 2: called when timer finishes — actual check-in with dryRun: true
    private func completeCheckIn() {
        guard let location = selectedLocation,
              let userLocation = locationManager.location?.coordinate else {
            resetCheckIn()
            return
        }

        LocationAPI.shared.checkIn(locationId: location.id, userCoordinate: userLocation, dryRun: false) { result in
            switch result {
            case .success(let response):
                print("🎉 Check-in success:", response.message)
                successMessage = response.message
                showSuccessAlert = true
                showAlert = false
                checkInSuccess = true
                // TODO: show popup / update XP / level
            case .failure(let error):
                print("❌ Check-in failed:", error.localizedDescription)
                errorMessage = error.localizedDescription
                showAlert = true
                showSuccessAlert = false
                checkInSuccess = false
            }
            
            // Finally reset the UI
            resetCheckIn()
        }
    }
    
}

struct HeaderCard: View {
    let nearbyCount: Int
    var weatherData: WeatherData? = nil

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.green)
                    .frame(width: 40, height: 40)

                Image(systemName: "map")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Map")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.black)

                Text(nearbyCount > 0 ?
                     "\(nearbyCount) merchant\(nearbyCount > 1 ? "s" : "") nearby" :
                        "No merchants nearby")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }

            Spacer()

            if let weather = weatherData {
                WeatherMiniWidget(data: weather)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }
}


struct MerchantMarkerView: View {
    let merchant: MerchantLocation
    let isInRange: Bool
    let isActive: Bool
    let isPartner: Bool
    
    @State private var pulse = false
    
    var markerColor: Color {
        isPartner ? .purple : .green
    }
    
    var body: some View {
        ZStack {
            if isInRange && !isActive {
                Circle()
                    .fill(markerColor.opacity(0.3))
                    .frame(width: 60, height: 60)
                    .scaleEffect(pulse ? 1.6 : 1)
                    .opacity(pulse ? 0 : 0.6)
                    .animation(
                        .easeOut(duration: 2).repeatForever(autoreverses: false),
                        value: pulse
                    )
            }
            
            RoundedRectangle(cornerRadius: 14)
                .fill(isActive ? markerColor : .white)
                .frame(width: 48, height: 48)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isInRange ? markerColor : Color.gray, lineWidth: 3)
                )
                .shadow(radius: 6)

            if let urlStr = merchant.imageUrl, let url = URL(string: urlStr) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Text(merchant.emoji)
                    .font(.system(size: 24))
            }
        }
        .onAppear { pulse = true }
        .scaleEffect(isActive ? 1.15 : 1)
    }
}
struct CheckInProgressCard: View {
    let merchant: MerchantLocation
    let progress: Double
    let remaining: Int
    let onCancel: () -> Void
    
    var body: some View {
        VStack {
            VStack(spacing: 16) {
                HStack {
                    if let urlStr = merchant.imageUrl, let url = URL(string: urlStr) {
                        KFImage(url)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        Text(merchant.emoji)
                            .font(.largeTitle)
                    }

                    VStack(alignment: .leading) {
                        Text(merchant.name)
                            .fontWeight(.bold)
                            .foregroundColor(.white)

                        Text("Checking in...")
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    Spacer()
                }
                
                ProgressView(value: progress)
                    .progressViewStyle(
                        LinearProgressViewStyle(tint: .white)
                    )
                
                HStack {
                    Text("\(Int(progress * 100))%")
                    Spacer()
                    Text("\(remaining / 60):\(String(format: "%02d", remaining % 60))")
                }
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
                
                Button("Cancel Check-in", action: onCancel)
                    .foregroundColor(.white)
            }
            .padding()
            .background(Color.green)
            .cornerRadius(24)
            .padding()
            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

struct BottomCheckInCard: View {
    let merchant: MerchantLocation
    var isLoading: Bool = false
    let onCheckIn: () -> Void
    
    var body: some View {
        VStack {
            Spacer()
            
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    // Merchant image or fallback emoji
                    if let urlStr = merchant.imageUrl, let url = URL(string: urlStr) {
                        KFImage(url)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Text(merchant.emoji)
                            .font(.system(size: 48))
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        // Merchant Name
                        HStack(spacing: 8) {
                            Text(merchant.name)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.black)
                            
                            // Partner Badge
                            if merchant.category.lowercased() == "café" || merchant.category.lowercased() == "fast food" {
                                Text("Partner")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.green)
                                    )
                            }
                        }
                        
                        // Category
                        Text(merchant.category)
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                        
                        // In-Range Indicator
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .resizable()
                                .frame(width: 16, height: 16)
                                .foregroundColor(.green)
                            Text("In Range")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.green)
                        }
                    }
                    
                    Spacer()
                }
                
                Button(action: {
                    onCheckIn()
                }) {
                    HStack(spacing: 8) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "location.fill")
                            Text("Check In (+\(merchant.xpReward) XP)")
                                .font(.system(size: 16, weight: .bold))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(merchant.can_checkin && !isLoading ? Color.green : Color.gray)
                    .cornerRadius(16)
                }
                .disabled(!merchant.can_checkin || isLoading)
                
            }
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(24)
            .padding(.horizontal)
            .padding(.bottom)
        }
    }
}


struct MerchantLocation: Identifiable {
    let id: Int
    let name: String
    let category: String
    let emoji: String
    let xpReward: Int
    let coordinate: CLLocationCoordinate2D
    let can_checkin: Bool
    let imageUrl: String?
}
extension NearbyLocationResponse {
    var asMerchant: MerchantLocation {
        MerchantLocation(
            id: id,
            name: name,
            category: category,
            emoji: "📍",
            xpReward: xp_reward,
            coordinate: coordinate,
            can_checkin: can_checkin,
            imageUrl: WebService.resolvedImageUrl(image_url)
        )
    }
}


struct MerchantWithDistance: Identifiable {
    let id = UUID()           // Make it Identifiable
    let merchant: MerchantLocation
    let distance: Double
}

// MARK: - Fog Overlay

struct FogOverlayView: View {
    let zones: [Zone]
    let region: MKCoordinateRegion

    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            // Full-screen dark rectangle
            path.addRect(CGRect(x: -200, y: -200, width: size.width + 400, height: size.height + 400))
            // Punch a transparent hole for each unlocked zone (even-odd rule)
            for zone in zones where zone.is_unlocked {
                let pts = zone.boundary_polygon.map {
                    mapPoint(lat: $0.lat, lng: $0.lng, region: region, size: size)
                }
                guard let first = pts.first else { continue }
                path.move(to: first)
                pts.dropFirst().forEach { path.addLine(to: $0) }
                path.closeSubpath()
            }
            ctx.fill(path, with: .color(.black.opacity(0.72)), style: FillStyle(eoFill: true))
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    // Linear lat/lng → screen-pixel conversion (accurate enough at city scale)
    private func mapPoint(lat: Double, lng: Double, region: MKCoordinateRegion, size: CGSize) -> CGPoint {
        let minLat = region.center.latitude  - region.span.latitudeDelta  / 2
        let maxLat = region.center.latitude  + region.span.latitudeDelta  / 2
        let minLng = region.center.longitude - region.span.longitudeDelta / 2
        let maxLng = region.center.longitude + region.span.longitudeDelta / 2
        let latRange = maxLat - minLat
        let lngRange = maxLng - minLng
        guard latRange != 0, lngRange != 0 else { return .zero }
        return CGPoint(
            x: (lng - minLng) / lngRange * size.width,
            y: (1.0 - (lat - minLat) / latRange) * size.height
        )
    }
}

// MARK: - Zone Unlock Popup

struct ZoneUnlockPopup: View {
    let info: ZoneUnlockInfo
    let isEnglish: Bool
    let onExplore: (CLLocationCoordinate2D) -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            FogLiftParticles()
            VStack(spacing: 24) {
                // Icon
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color(hex: "#F97316"), Color(hex: "#EF4444")],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 80, height: 80)
                    Text("🗺️").font(.system(size: 38))
                }

                VStack(spacing: 10) {
                    Text(isEnglish ? info.headline_en : info.headline_ar)
                        .font(.system(size: 21, weight: .bold))
                        .foregroundColor(.black)
                        .multilineTextAlignment(.center)
                    Text(isEnglish ? info.body_en : info.body_ar)
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                Button {
                    let coord = CLLocationCoordinate2D(
                        latitude:  Double(info.center_lat) ?? 0,
                        longitude: Double(info.center_lng) ?? 0
                    )
                    onExplore(coord)
                } label: {
                    Text(isEnglish ? info.cta_en : info.cta_ar)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(LinearGradient(
                            colors: [Color(hex: "#F97316"), Color(hex: "#EF4444")],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .cornerRadius(14)
                }
            }
            .padding(28)
            .background(Color.white)
            .cornerRadius(24)
            .shadow(color: .black.opacity(0.25), radius: 24, x: 0, y: 10)
            .padding(.horizontal, 32)
        }
    }
}

// MARK: - Fog Lift Particles

struct FogLiftParticles: View {
    private static let streams: [(x: Double, delay: Double)] = [
        (0.15, 0.0), (0.30, 0.4), (0.45, 0.9), (0.55, 0.2),
        (0.65, 0.7), (0.80, 1.1), (0.90, 0.5)
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                for (si, s) in Self.streams.enumerated() {
                    let baseX = size.width * s.x
                    let sif = Double(si)
                    for slot in 0..<10 {
                        let sf = Double(slot)
                        let phase = (t * 0.22 + s.delay + sf / 10)
                            .truncatingRemainder(dividingBy: 1.0)
                        let y = size.height - phase * size.height * 1.05
                        let x = baseX + sin(t * 0.45 + sf * 0.9 + sif * 0.6) * 28
                        let r = 8.0 + phase * 65.0
                        let alpha = min(phase / 0.08, 1.0) * (1.0 - max((phase - 0.25) / 0.75, 0.0)) * 0.28
                        guard alpha > 0.005 else { continue }
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                            with: .color(Color.white.opacity(alpha))
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

#Preview {
    MapView()
        .environmentObject(LanguageManager())
        .environmentObject(UserManager())
}
