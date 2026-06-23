import SwiftUI
import CoreLocation
import Combine
import Kingfisher

struct MapView: View {

    @EnvironmentObject var languageManager: LanguageManager

    @StateObject private var locationManager = FilteredLocationManager()
    @StateObject private var dwellMonitor = DwellMonitor()
    @StateObject private var signalCollector = SignalCollector()
    @StateObject private var weatherManager = WeatherManager()

    @State private var locations: [NearbyLocationResponse] = []
    @State private var selectedLocation: NearbyLocationResponse?

    // Fog of War
    @State private var fogZones: [Zone] = []
    @State private var fogLoaded = false
    @State private var pendingUnlock: ZoneUnlockInfo? = nil
    @State private var showUnlockPopup = false

    @State private var lastFetchCenter: CLLocationCoordinate2D?

    // Mapbox camera control
    @State private var focusOn: MapCameraFocus?
    @State private var visibleRegion = VisibleMapRegion(
        centerLat: 24.7136, centerLng: 46.6753,   // Riyadh default
        latDelta: 0.5, lngDelta: 0.5
    )

    @State var errorMessage: String = ""
    @State var successMessage: String = ""
    @State private var showAlert: Bool = false
    @State private var showSuccessAlert: Bool = false

    // MARK: Check-In State
    @State private var isDwelling = false
    @State private var isValidating = false

    /// Last location we auto-centered the camera on (avoid fighting manual pans).
    @State private var lastAutoCenter: CLLocationCoordinate2D?
    /// Last location we fetched nearby merchants for.
    @State private var lastFetchCoord: CLLocationCoordinate2D?

    private let fraudStore = FraudEvidenceStore()
    
    var body: some View {
        ZStack {
            
            // MARK: Map (Mapbox)
            MapboxMapContainer(
                locations: $locations,
                selectedLocation: $selectedLocation,
                focusOn: $focusOn,
                merchantPolygon: selectedLocation?.boundary_polygon,
                isCheckingIn: isDwelling,
                onCameraChanged: { cameraState in
                    // Update visible region for fog overlay
                    visibleRegion = VisibleMapRegion(
                        centerLat: cameraState.center.latitude,
                        centerLng: cameraState.center.longitude,
                        latDelta: cameraState.north - cameraState.south,
                        lngDelta: cameraState.east - cameraState.west
                    )
                    // Trigger nearby fetch when dragged far enough
                    handleMapDrag(cameraState.center)
                },
                onTapLocation: { location in
                    selectedLocation = location
                }
            )
            .ignoresSafeArea()

            // MARK: Fog of War
            if fogLoaded {
                FogOverlayView(zones: fogZones, visibleRegion: visibleRegion)
                    .transition(.opacity)
                    .animation(.easeIn(duration: 0.5), value: fogLoaded)
            }

            // MARK: Weather Overlay
            WeatherOverlayView(condition: weatherManager.condition)
            
            // MARK: HeaderCard
            if !locations.isEmpty && !showSuccessAlert && !showAlert{
                VStack {
                    HeaderCard(nearbyCount: locations.count, weatherData: weatherManager.data)
                    Spacer()
                }
                .animation(.easeIn, value: locations.count)
            }
            
            // MARK: Success Banner
            if showSuccessAlert {
                VStack {
                    Text(successMessage)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.green)
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
            
            // MARK: Error Banner
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
            if isDwelling, let location = selectedLocation {
                CheckInProgressCard(
                    merchant: .init(
                        id: location.id, name: location.name,
                        category: location.category,
                        emoji: "📍",
                        xpReward: location.xp_reward,
                        coordinate: location.coordinate,
                        can_checkin: location.can_checkin,
                        imageUrl: WebService.resolvedImageUrl(location.image_url),
                        kingUserId: location.king_user_id,
                        kingFalconName: location.king_falcon_name,
                        boundaryPolygon: location.boundary_polygon
                    ),
                    progress: dwellMonitor.progress,
                    remaining: dwellMonitor.secondsRemaining,
                    status: statusText(for: dwellMonitor.state)
                ) {
                    cancelDwell()
                }
            }
            
            // MARK: Current Location Button
            if !isDwelling {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            if let location = locationManager.currentLocation {
                                // Force camera to user location regardless of distance threshold
                                lastAutoCenter = location.coordinate
                                withAnimation {
                                    moveToUser(location)
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
            if !isDwelling, let location = selectedLocation {
                BottomCheckInCard(
                    merchant: location.asMerchant,
                    isLoading: isValidating
                ) {
                    beginCheckIn(location)
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
                        focusOn = MapCameraFocus(
                            latitude: zoneCenter.latitude,
                            longitude: zoneCenter.longitude,
                            zoom: 12
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
            AntiCheatAPI.fetchThresholds()
        }
        .onReceive(locationManager.$currentLocation.compactMap { $0 }) { location in
            let coord = location.coordinate

            // Auto-center only on first fix or when user has moved > 200m
            // (prevents fighting manual map pans while still following the user).
            if let last = lastAutoCenter {
                let lastLoc = CLLocation(latitude: last.latitude, longitude: last.longitude)
                let newLoc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                if newLoc.distance(from: lastLoc) > 200 {
                    moveToUser(location)
                    lastAutoCenter = coord
                }
            } else {
                moveToUser(location)
                lastAutoCenter = coord
            }

            // Fetch nearby merchants only when moved > 5 km
            if let lastFetch = lastFetchCoord {
                let lastFetchLoc = CLLocation(latitude: lastFetch.latitude, longitude: lastFetch.longitude)
                let newLoc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                if newLoc.distance(from: lastFetchLoc) > 5000 {
                    fetchNearby(coord)
                    lastFetchCoord = coord
                }
            } else {
                fetchNearby(coord)
                lastFetchCoord = coord
            }

            weatherManager.update(coordinate: coord)

            // Feed location into dwell monitor during active check-in
            if isDwelling {
                dwellMonitor.updateUserLocation(location)
            }
        }
        .onReceive(dwellMonitor.$progress) { newProgress in
            // progress is already @Published on dwellMonitor, read by CheckInProgressCard
        }
        .onReceive(dwellMonitor.$state) { state in
            switch state {
            case .verifiedDwell:
                // Dwell completed — start collecting proof bundle
                guard let location = selectedLocation else { return }
                signalCollector.startCollection(
                    for: location.id,
                    dwellMonitor: dwellMonitor,
                    locationManager: locationManager
                )

            case .submitted:
                // Bundle was assembled — submit to server
                if let bundle = signalCollector.bundle {
                    submitProofBundle(bundle)
                }

            case .failed(let reason):
                errorMessage = reason
                showAlert = true
                showSuccessAlert = false
                cancelDwell()

            case .idle:
                break

            default:
                break
            }
        }
        .onReceive(signalCollector.$bundle) { bundle in
            guard let bundle, dwellMonitor.state == .submitted else { return }
            submitProofBundle(bundle)
        }
    }

    // MARK: Helpers

    private func statusText(for state: DwellState) -> String {
        switch state {
        case .scanning:       return "Approaching merchant..."
        case .dwelling:       return "Verifying visit..."
        case .verifiedDwell:  return "Location verified! Checking in..."
        case .collecting:     return "Finalizing check-in..."
        case .submitted:      return "Complete!"
        case .failed:         return "Check-in unavailable"
        case .idle:           return ""
        }
    }

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
        focusOn = MapCameraFocus(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            zoom: 15
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

    // MARK: - Check-In Flow (Anti-Cheat)

    private func beginCheckIn(_ location: NearbyLocationResponse) {
        guard locationManager.currentLocation != nil else {
            errorMessage = "Unable to determine your location. Please try again."
            showAlert = true
            return
        }

        selectedLocation = location
        isValidating = true

        // Step 1: Lightweight server pre-check (dryRun)
        LocationAPI.shared.checkIn(
            locationId: location.id,
            userCoordinate: .init(latitude: location.latitude, longitude: location.longitude),
            dryRun: true
        ) { result in
            isValidating = false

            switch result {
            case .success:
                // Step 2: Begin real dwell monitoring
                withAnimation {
                    isDwelling = true
                }
                dwellMonitor.beginMonitoring(
                    merchantCenter: location.coordinate,
                    merchantRadiusMeters: Double(location.radius_meters),
                    locationManager: locationManager
                )

            case .failure(let error):
                errorMessage = error.localizedDescription
                showAlert = true
                showSuccessAlert = false
                selectedLocation = nil
            }
        }
    }

    private func cancelDwell() {
        dwellMonitor.cancel()
        signalCollector.cancel()
        withAnimation {
            isDwelling = false
            selectedLocation = nil
        }
    }

    private func submitProofBundle(_ bundle: ProofBundle) {
        AntiCheatAPI.verifyCheckIn(bundle: bundle) { result in
            switch result {
            case .success(let verification):
                handleVerification(verification)

            case .failure(let error):
                // Queue offline and retry later
                fraudStore.savePending(bundle: bundle)
                errorMessage = "Check-in queued. Will retry when connected."
                showAlert = true
                showSuccessAlert = false
                cancelDwell()
            }
        }
    }

    private func handleVerification(_ result: VerificationResult) {
        // Save pre-check-in king info before cancelDwell clears selectedLocation
        let oldKingId = selectedLocation?.king_user_id
        let locId = selectedLocation?.id
        let locName = selectedLocation?.name ?? ""

        switch result.verdict {
        case "approved":
            successMessage = result.reason_codes.first ?? "Check-in successful!"
            showSuccessAlert = true
            showAlert = false
            print("✅ Check-in approved: \(result.confidence_score) confidence, +\(result.xp_earned) XP")

            // Check if the user was dethroned (old king was the current user, now someone else)
            if oldKingId == UserModel.shared.user?.id, let lid = locId {
                checkDethroned(locationId: lid, locationName: locName)
            }

        case "shadow_queue":
            successMessage = "Visit recorded! Rewards pending review."
            showSuccessAlert = true
            showAlert = false
            print("⏳ Check-in shadow-queued: \(result.confidence_score) confidence")
            for flag in result.fraud_flags {
                print("   ⚑ \(flag.signal): \(flag.severity) — \(flag.description)")
            }

        case "rejected":
            let reasons = result.reason_codes.joined(separator: ", ")
            errorMessage = reasons.isEmpty ? "Check-in could not be verified." : reasons
            showAlert = true
            showSuccessAlert = false
            print("❌ Check-in rejected: \(result.confidence_score) confidence")
            for flag in result.fraud_flags {
                print("   ⚑ \(flag.signal): \(flag.severity) — \(flag.description)")
            }

        default:
            errorMessage = "Unexpected response. Please try again."
            showAlert = true
            showSuccessAlert = false
        }

        cancelDwell()
    }

    private func checkDethroned(locationId: Int, locationName: String) {
        // Re-fetch nearby to get fresh king info
        guard let coord = locationManager.currentLocation?.coordinate else { return }

        LocationAPI.shared.fetchNearby(
            latitude: coord.latitude,
            longitude: coord.longitude
        ) { items, _ in
            guard let updated = items.first(where: { $0.id == locationId }),
                  updated.king_user_id != UserModel.shared.user?.id,
                  updated.king_falcon_name != nil
            else { return }

            // User was dethroned — show alert
            let msg = String(
                format: languageManager.text("map.dethroned"),
                locationName
            )
            errorMessage = msg
            showAlert = true
        }
    }
    
}

// MARK: - Header Card

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

// MARK: - Merchant Marker

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

            // Crown indicator for the king's pin
            if merchant.kingFalconName != nil {
                Text("👑")
                    .font(.system(size: 14))
                    .position(x: 40, y: 6)
            }
        }
        .onAppear { pulse = true }
        .scaleEffect(isActive ? 1.15 : 1)
    }

}

// MARK: - Check-In Progress Card

struct CheckInProgressCard: View {
    let merchant: MerchantLocation
    let progress: Double
    let remaining: Int
    let status: String
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

                        Text(status)
                            .font(.caption)
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
                    if remaining > 0 {
                        Text("\(remaining / 60):\(String(format: "%02d", remaining % 60))")
                    }
                }
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))

                if remaining > 0 {
                    Button("Cancel Check-in", action: onCancel)
                        .foregroundColor(.white)
                }
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

// MARK: - Bottom Check-In Card

struct BottomCheckInCard: View {
    let merchant: MerchantLocation
    var isLoading: Bool = false
    let onCheckIn: () -> Void
    
    var body: some View {
        VStack {
            Spacer()
            
            VStack(spacing: 16) {
                // King banner (👑 large + bold above everything)
                if let kingName = merchant.kingFalconName {
                    HStack(spacing: 8) {
                        Text("👑")
                            .font(.system(size: 22))
                        Text(kingName)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(Color(red: 0.85, green: 0.65, blue: 0.12))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(red: 0.85, green: 0.65, blue: 0.12).opacity(0.08))
                    .cornerRadius(12)
                }

                HStack(spacing: 16) {
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
                        HStack(spacing: 8) {
                            Text(merchant.name)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.black)
                            
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
                        
                        Text(merchant.category)
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                        
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

// MARK: - MerchantLocation model

struct MerchantLocation: Identifiable {
    let id: Int
    let name: String
    let category: String
    let emoji: String
    let xpReward: Int
    let coordinate: CLLocationCoordinate2D
    let can_checkin: Bool
    let imageUrl: String?

    // King / ownership
    let kingUserId: Int?
    let kingFalconName: String?

    // Polygon boundary (for rendering)
    let boundaryPolygon: [PolygonPoint]?
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
            imageUrl: WebService.resolvedImageUrl(image_url),
            kingUserId: king_user_id,
            kingFalconName: king_falcon_name,
            boundaryPolygon: boundary_polygon
        )
    }
}

struct MerchantWithDistance: Identifiable {
    let id = UUID()
    let merchant: MerchantLocation
    let distance: Double
}

// MARK: - Fog Overlay

struct FogOverlayView: View {
    let zones: [Zone]
    let visibleRegion: VisibleMapRegion

    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            path.addRect(CGRect(x: -200, y: -200, width: size.width + 400, height: size.height + 400))
            for zone in zones where zone.is_unlocked {
                let pts = zone.boundary_polygon.map {
                    mapPoint(lat: $0.lat, lng: $0.lng, size: size)
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

    private func mapPoint(lat: Double, lng: Double, size: CGSize) -> CGPoint {
        let minLat = visibleRegion.centerLat - visibleRegion.latDelta / 2
        let maxLat = visibleRegion.centerLat + visibleRegion.latDelta / 2
        let minLng = visibleRegion.centerLng - visibleRegion.lngDelta / 2
        let maxLng = visibleRegion.centerLng + visibleRegion.lngDelta / 2
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
