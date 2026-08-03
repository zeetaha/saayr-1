import SwiftUI
import CoreLocation
import Combine
import Kingfisher

struct MapView: View {

    @EnvironmentObject var languageManager: LanguageManager

    @StateObject private var locationManager = FilteredLocationManager()
    @StateObject private var weatherManager = WeatherManager()
    /// Which landmarks are still a mystery, and the reveal when one is entered.
    @StateObject private var discoveries = LandmarkDiscoveryService()

    @State private var locations: [NearbyLocationResponse] = []
    @State private var selectedLocation: NearbyLocationResponse?
    /// Detail for landmarks this player has found, keyed by landmark id. Comes
    /// from `discovered_landmarks` in the nearby response — the location object
    /// itself carries no description until the landmark is discovered.
    @State private var landmarkDetails: [Int: DiscoveredLandmark] = [:]

    // Fog of War
    @State private var fogZones: [Zone] = []
    @State private var pendingUnlock: ZoneUnlockInfo? = nil
    @State private var showUnlockPopup = false

    @State private var lastFetchCenter: CLLocationCoordinate2D?
    /// Radius the last nearby fetch covered, so zooming out past it can pull in
    /// the merchants the wider view now exposes.
    @State private var lastFetchRadiusKM: Int = 0

    // Mapbox camera control
    @State private var focusOn: MapCameraFocus?
    @State private var visibleRegion = VisibleMapRegion(
        centerLat: 24.7136, centerLng: 46.6753,   // Riyadh default
        latDelta: 0.5, lngDelta: 0.5
    )

    /// Latest camera zoom, so the +/- buttons step from wherever the user is.
    @State private var currentZoom: Double = 15
    /// Zoom the last diagnostic line was printed at (DEBUG logging only).
    @State private var lastLoggedZoom: Double = .nan

    #if DEBUG
    /// Where the test landmark was planted. Set once, from the first fix.
    @State private var debugLandmarkAnchor: CLLocationCoordinate2D?
    #endif

    private static let minZoom: Double = 3
    private static let maxZoom: Double = 20

    /// Where the map sits until a fix arrives.
    static let riyadh = CLLocationCoordinate2D(latitude: 24.7136, longitude: 46.6753)

    @State var errorMessage: String = ""
    @State var successMessage: String = ""
    @State private var showAlert: Bool = false
    @State private var showSuccessAlert: Bool = false

    // MARK: Check-In State
    @State private var isDwelling = false
    @State private var isValidating = false
    @State private var isSubmittingFinalCheckIn = false
    @State private var checkInProgress: Double = 0.0
    @State private var checkInRemainingSeconds: Int = 0
    @State private var checkInTimer: Timer? = nil
    @State private var nearbyFetchWorkItem: DispatchWorkItem? = nil
    @State private var lastNearbyFetchDate: Date? = nil

    /// Last location we auto-centered the camera on (avoid fighting manual pans).
    @State private var lastAutoCenter: CLLocationCoordinate2D?

    private let fraudStore = FraudEvidenceStore()

    /// Merchants the player is allowed to see: only those inside an unlocked
    /// zone. Everything else sits on ground the map has blacked out, so a pin
    /// there would point at somewhere they can't go.
    private var visibleLocations: [NearbyLocationResponse] {
        let real = ZoneVisibility.inUnlockedZones(locations, zones: fogZones)

        #if DEBUG
        // Appended after the zone filter on purpose: the test landmark should
        // show up whether or not the surrounding zone is unlocked.
        if let fixture = debugLandmark { return real + [fixture] }
        #endif

        return real
    }

    #if DEBUG
    /// The fake landmark, planted once near wherever the player first appears
    /// so it doesn't drift around as new fixes arrive.
    private var debugLandmark: NearbyLocationResponse? {
        guard LandmarkTestFixture.isEnabled, let anchor = debugLandmarkAnchor else { return nil }
        return LandmarkTestFixture.landmark(near: anchor)
    }
    #endif

    /// Whether the pin the player tapped is a landmark they haven't reached.
    private var isSelectionLocked: Bool {
        selectedLocation.map(discoveries.isLocked) ?? false
    }

    /// The area to walk into for the tapped mystery pin. Showing where it is
    /// gives nothing away about what it is, and without it the pin is an
    /// instruction with no target — landmarks without a boundary polygon get
    /// their geofence circle drawn instead.
    private var selectedMysteryArea: [PolygonPoint]? {
        guard let location = selectedLocation, discoveries.isLocked(location) else { return nil }
        return LandmarkGeofence.boundaryRing(of: location)
    }

    var body: some View {
        ZStack {
            
            // MARK: Map (Mapbox)
            MapboxMapContainer(
                locations: visibleLocations,
                selectedLocation: $selectedLocation,
                focusOn: $focusOn,
                merchantPolygon: isSelectionLocked ? nil : selectedLocation?.boundary_polygon,
                mysteryArea: selectedMysteryArea,
                lockedLandmarkKeys: discoveries.lockedKeys(in: visibleLocations),
                zones: fogZones,
                isArabic: languageManager.currentLanguage == .arabic,
                isCheckingIn: isDwelling,
                onCameraChanged: { cameraState in
                    currentZoom = cameraState.zoom
                    // Update visible region for fog overlay
                    visibleRegion = VisibleMapRegion(
                        centerLat: cameraState.center.latitude,
                        centerLng: cameraState.center.longitude,
                        latDelta: cameraState.north - cameraState.south,
                        lngDelta: cameraState.east - cameraState.west
                    )
                    logMapDiagnostics(zoom: cameraState.zoom)
                    // Widen the merchant fetch when the view grows, then trigger
                    // a nearby fetch if the camera was dragged far enough.
                    handleZoomChange()
                    handleMapDrag(cameraState.center)
                },
                onTapLocation: { location in
                    selectedLocation = location
                }
            )
            .ignoresSafeArea()

            // The fog of war and the revealed zones are drawn by
            // MapboxMapContainer as map layers, so they stay anchored to the
            // streets through pan, zoom, rotation and tilt.

            // MARK: Weather Overlay
            WeatherOverlayView(condition: weatherManager.condition)
            
            // MARK: HeaderCard
            // Counts what's actually pinned, so the header can't claim more
            // merchants than the map is showing.
            if !visibleLocations.isEmpty && !showSuccessAlert && !showAlert{
                VStack {
                    HeaderCard(nearbyCount: visibleLocations.count, weatherData: weatherManager.data)
                    Spacer()
                }
                .animation(.easeIn, value: visibleLocations.count)
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
                        category: location.category ?? "",
                        emoji: "📍",
                        xpReward: location.xp_reward,
                        coordinate: location.coordinate,
                        can_checkin: location.can_checkin,
                        imageUrl: WebService.resolvedImageUrl(location.image_url),
                        kingUserId: location.king_user_id,
                        kingFalconName: location.king_falcon_name,
                        boundaryPolygon: location.boundary_polygon, type: location.type
                    ),
                    progress: checkInProgress,
                    remaining: checkInRemainingSeconds,
                    status: statusText()
                ) {
                    cancelDwell()
                }
            }
            
            // MARK: Map Controls (zoom + recenter)
            if !isDwelling {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {

                            // Zoom in / out
                            VStack(spacing: 0) {
                                mapControlButton(
                                    systemName: "plus",
                                    isEnabled: currentZoom < Self.maxZoom
                                ) {
                                    stepZoom(by: 1)
                                }

                                Divider().frame(width: 28)

                                mapControlButton(
                                    systemName: "minus",
                                    isEnabled: currentZoom > Self.minZoom
                                ) {
                                    stepZoom(by: -1)
                                }
                            }
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)

                            #if DEBUG
                            // Tap: reveal the nearest mystery pin without
                            // walking to it. Long press: put every landmark
                            // back to undiscovered so it can be run again.
                            if LandmarkTestFixture.isEnabled {
                                Button {
                                    debugRevealNearestLandmark()
                                } label: {
                                    Image(systemName: "wand.and.stars")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(Color(hex: "#7C3AED"))
                                        .frame(width: 48, height: 48)
                                        .background(Color.white)
                                        .clipShape(Circle())
                                        .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
                                }
                                .simultaneousGesture(
                                    LongPressGesture().onEnded { _ in
                                        withAnimation { discoveries.debugResetDiscoveries() }
                                    }
                                )
                            }
                            #endif

                            // Recenter on the user
                            Button {
                                recenterOnUser()
                            } label: {
                                Image(systemName: hasLocationFix ? "location.fill" : "location.slash")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(hasLocationFix ? .blue : .gray)
                                    .frame(width: 48, height: 48)
                                    .background(Color.white)
                                    .clipShape(Circle())
                                    .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
                            }
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, selectedLocation != nil ? 180 : 32)
                    }
                }
            }

            // MARK: Bottom Check-In
            if !isDwelling, let location = selectedLocation {
                // A landmark that hasn't been reached shows nothing about
                // itself — not even a check-in button, since reaching it is
                // the whole interaction.
                if discoveries.isLocked(location) {
                    MysteryLandmarkCard(
                        landmark: location,
                        userLocation: cameraLocation?.coordinate,
                        isEnglish: languageManager.currentLanguage == .english,
                        onClose: { withAnimation(.easeInOut) { selectedLocation = nil } }
                    )
                } else if location.isLandmark {
                    // Discovered landmark: its story, and no check-in button —
                    // a landmark is found once, not visited repeatedly.
                    DiscoveredLandmarkCard(
                        landmark: location,
                        detail: landmarkDetails[location.id],
                        discoveredAt: discoveries.discoveryDate(for: location),
                        isEnglish: languageManager.currentLanguage == .english,
                        onClose: { withAnimation(.easeInOut) { selectedLocation = nil } }
                    )
                } else {
                    BottomCheckInCard(
                        merchant: location.asMerchant,
                        isLoading: isValidating,
                        onCheckIn: { beginCheckIn(location) },
                        onClose: { withAnimation(.easeInOut) { selectedLocation = nil } }
                    )
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

            // MARK: Landmark Reveal
            if let reveal = discoveries.reveal {
                LandmarkRevealPopup(
                    reveal: reveal,
                    isEnglish: languageManager.currentLanguage == .english
                ) {
                    withAnimation(.easeInOut) {
                        // Leaves the now-discovered landmark selected, so the
                        // check-in card it just became is right there.
                        selectedLocation = reveal.landmark
                        discoveries.dismissReveal()
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(110)
            }

        }
        .onAppear {
            locationManager.requestPermission()
            // `requestPermission` only fires the authorization callback (and so
            // `startUpdating`) when the status is still undetermined, so kick
            // updates directly for the already-authorized case.
            locationManager.startUpdating()
            fetchFogZones()

            // Restores what this player has already revealed, then reconciles
            // with the server: pulls its record, replays anything it never
            // acknowledged.
            discoveries.load()
        }
        // Discovery runs off the filtered fix, not the raw one: entering a
        // landmark awards XP, so it has to clear the same anti-cheat bar as a
        // check-in rather than trusting whatever the OS last reported.
        .onReceive(locationManager.$currentLocation.compactMap { $0 }) { location in
            withAnimation(.easeInOut) {
                discoveries.evaluate(
                    userLocation: location,
                    isSimulated: locationManager.isSimulated,
                    locations: visibleLocations
                )
            }
        }
        // Driven by the raw fix, not the filtered one: following the user and
        // listing nearby merchants shouldn't stall because a fix was too coarse
        // to check in with.
        .onReceive(locationManager.$lastRawLocation.compactMap { $0 }) { location in
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

            #if DEBUG
            if debugLandmarkAnchor == nil { debugLandmarkAnchor = coord }
            #endif

            weatherManager.update(coordinate: coord)
            scheduleNearbyFetch(coord)
        }
    }

    // MARK: Helpers

    private func statusText() -> String {
        if isSubmittingFinalCheckIn {
            return "Submitting check-in..."
        }
        if isDwelling {
            return "Verifying visit..."
        }
        return ""
    }

    /// Prints how many merchants are loaded versus actually pinned as the zoom
    /// changes, so a "pins vanished" report can be pinned on the data (the count
    /// drops) or on the map's own culling (the count holds while pins go).
    /// Throttled to half a zoom level — the camera callback fires per frame.
    private func logMapDiagnostics(zoom: Double) {
        #if DEBUG
        guard lastLoggedZoom.isNaN || abs(zoom - lastLoggedZoom) >= 0.5 else { return }
        lastLoggedZoom = zoom
        print(String(
            format: "🗺️ zoom %.1f — %d fetched, %d pinned, %d zones, radius %dkm",
            zoom, locations.count, visibleLocations.count, fogZones.count, fetchRadiusKM
        ))
        #endif
    }

    #if DEBUG
    /// Reveals the closest undiscovered landmark, so the reveal can be tested
    /// without moving the device or the simulator's location.
    private func debugRevealNearestLandmark() {
        let anchor = cameraLocation?.coordinate ?? Self.riyadh
        let locked = visibleLocations.filter(discoveries.isLocked)

        guard let nearest = locked.min(by: {
            LandmarkGeofence.distance(from: anchor, to: $0)
                < LandmarkGeofence.distance(from: anchor, to: $1)
        }) else {
            errorMessage = "No undiscovered landmarks in view."
            showAlert = true
            return
        }

        withAnimation(.easeInOut) { discoveries.debugDiscover(nearest) }
    }
    #endif

    /// Radius to ask the API for: whatever the camera can currently see, so a
    /// zoomed-out view is populated with merchants instead of only the ones
    /// within walking distance of the last fetch centre.
    private var fetchRadiusKM: Int {
        let latKM = visibleRegion.latDelta * 111.0
        let lngKM = visibleRegion.lngDelta * 111.0 * cos(visibleRegion.centerLat * .pi / 180)
        let halfSpan = max(latKM, lngKM) / 2
        return Int(min(max(halfSpan.rounded(.up), 5), 50))
    }

    /// Zooming out doesn't move the centre, so `handleMapDrag` never fires for
    /// it — but the view can now show far more ground than the last fetch
    /// covered. Refetch once the visible radius has meaningfully outgrown it.
    private func handleZoomChange() {
        let radius = fetchRadiusKM
        guard Double(radius) > Double(max(lastFetchRadiusKM, 1)) * 1.5 else { return }

        scheduleNearbyFetch(
            CLLocationCoordinate2D(
                latitude: visibleRegion.centerLat,
                longitude: visibleRegion.centerLng
            ),
            ignoringDistance: true
        )
    }

    private func handleMapDrag(_ newCenter: CLLocationCoordinate2D) {
        guard let lastCenter = lastFetchCenter else {
            scheduleNearbyFetch(newCenter)
            return
        }

        let old = CLLocation(latitude: lastCenter.latitude, longitude: lastCenter.longitude)
        let new = CLLocation(latitude: newCenter.latitude, longitude: newCenter.longitude)
        let distanceKM = old.distance(from: new) / 1000

        if distanceKM >= 5 {
            scheduleNearbyFetch(newCenter)
        }
    }

    /// Where to point the camera. Falls back to the raw fix so a position the
    /// anti-cheat filter rejected can still be looked at — it just can't be
    /// checked in from.
    private var cameraLocation: CLLocation? {
        locationManager.currentLocation ?? locationManager.lastRawLocation
    }

    /// Whether we have a position good enough to recenter on.
    private var hasLocationFix: Bool {
        cameraLocation != nil
    }

    /// Why there's no usable position, phrased for the person holding the phone.
    private var locationUnavailableMessage: String {
        switch locationManager.authorizationStatus {
        case .denied, .restricted:
            return "Location access is off. Enable it in Settings to check in."
        case .notDetermined:
            return "SAAYR needs location access to check in."
        default:
            break
        }

        if locationManager.lastLocationError == .locationUnknown {
            return "Can't get a GPS signal right now. Move somewhere with a clearer view of the sky."
        }
        return "Still finding your location. Please try again in a moment."
    }

    /// Recenters on the user, or explains why it can't instead of doing nothing.
    private func recenterOnUser() {
        if let location = cameraLocation {
            // Force the camera regardless of the auto-center distance threshold.
            lastAutoCenter = location.coordinate
            withAnimation {
                moveToUser(location)
            }
            return
        }

        switch locationManager.authorizationStatus {
        case .denied, .restricted:
            errorMessage = "Location access is off. Showing Riyadh instead."
        case .notDetermined:
            locationManager.requestPermission()
            errorMessage = "Waiting for location permission. Showing Riyadh instead."
        default:
            // Authorized but nothing has arrived yet — nudge Core Location.
            locationManager.startUpdating()
            errorMessage = "Still finding your location. Showing Riyadh instead."
        }

        // Never leave the button dead: without a fix, fall back to the city.
        withAnimation {
            focusOn = MapCameraFocus(
                latitude: Self.riyadh.latitude,
                longitude: Self.riyadh.longitude,
                zoom: 11
            )
            showAlert = true
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
        let radiusKM = fetchRadiusKM
        lastFetchRadiusKM = radiusKM

        LocationAPI.shared.fetchNearby(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            radiusKM: radiusKM
        ) { newItems, unlockInfo, discoveredLandmarks in
            // Merge rather than replace. Each fetch only covers a circle around
            // one centre, so replacing wiped every pin outside it — panning at a
            // wide zoom (where a small drag is tens of km) emptied the map.
            // Merchants already on screen stay put; a repeat of one just
            // refreshes it with the newer copy.
            var byKey: [String: NearbyLocationResponse] = [:]
            var order: [String] = []
            for item in locations + newItems {
                if byKey[item.uniqueKey] == nil { order.append(item.uniqueKey) }
                byKey[item.uniqueKey] = item
            }
            locations = order.compactMap { byKey[$0] }

            // Merged for the same reason as the pins: this fetch only describes
            // the landmarks near one centre, and dropping the rest would blank
            // the card of one the player walks back to.
            for landmark in discoveredLandmarks {
                landmarkDetails[landmark.landmark_id] = landmark
            }

            // The server's record wins over the local one — a landmark revealed
            // on another device shouldn't still read as a mystery here.
            discoveries.adoptServerState(from: newItems, discoveredLandmarks: discoveredLandmarks)

            if let unlock = unlockInfo {
                fetchFogZones()
                pendingUnlock = unlock
                withAnimation { showUnlockPopup = true }
            }
        }
    }

    // MARK: - Zoom Controls

    private func mapControlButton(
        systemName: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(isEnabled ? .blue : Color.gray.opacity(0.4))
                .frame(width: 48, height: 44)
                .contentShape(Rectangle())
        }
        .disabled(!isEnabled)
    }

    /// Steps the camera one zoom level, keeping the current centre.
    private func stepZoom(by delta: Double) {
        let target = min(max(currentZoom + delta, Self.minZoom), Self.maxZoom)
        guard abs(target - currentZoom) > 0.01 else { return }

        currentZoom = target
        focusOn = MapCameraFocus(
            latitude: visibleRegion.centerLat,
            longitude: visibleRegion.centerLng,
            zoom: target
        )
    }

    private func fetchFogZones() {
        ServiceModel.shared.fetchZones { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let zones):
                    fogZones = zones
                case .failure(let error):
                    print("⚠️ Zones unavailable:", error.localizedDescription)
                    fogZones = []
                }
            }
        }
    }

    private func scheduleNearbyFetch(
        _ coordinate: CLLocationCoordinate2D,
        ignoringDistance: Bool = false
    ) {
        guard shouldFetchNearby(for: coordinate, ignoringDistance: ignoringDistance) else { return }

        nearbyFetchWorkItem?.cancel()
        let workItem = DispatchWorkItem { [coordinate] in
            performNearbyFetch(coordinate, ignoringDistance: ignoringDistance)
        }
        nearbyFetchWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75, execute: workItem)
    }

    /// `ignoringDistance` is for zoom-driven fetches: the centre hasn't moved,
    /// but the area on screen has grown, so the usual "moved 5 km" gate would
    /// block a refetch that is genuinely needed.
    private func shouldFetchNearby(
        for coordinate: CLLocationCoordinate2D,
        ignoringDistance: Bool = false
    ) -> Bool {
        if isDwelling {
            return false
        }

        if let lastCenter = lastFetchCenter, !ignoringDistance {
            let oldLocation = CLLocation(latitude: lastCenter.latitude, longitude: lastCenter.longitude)
            let newLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let distance = oldLocation.distance(from: newLocation)
            if distance < 5_000 {
                return false
            }
        }

        if let lastDate = lastNearbyFetchDate,
           Date().timeIntervalSince(lastDate) < 1.0 {
            return false
        }

        return true
    }

    private func performNearbyFetch(
        _ coordinate: CLLocationCoordinate2D,
        ignoringDistance: Bool = false
    ) {
        guard shouldFetchNearby(for: coordinate, ignoringDistance: ignoringDistance) else { return }
        lastNearbyFetchDate = Date()
        lastFetchCenter = coordinate
        fetchNearby(coordinate)
    }

    // MARK: - Check-In Flow (Anti-Cheat)

    private func beginCheckIn(_ location: NearbyLocationResponse) {
        // Landmarks aren't checked into at all: undiscovered ones are revealed
        // by walking in, and discovered ones are done with. No card offers the
        // button, so this is belt-and-braces against a future caller.
        guard !location.isLandmark else { return }

        guard locationManager.currentLocation != nil else {
            errorMessage = locationUnavailableMessage
            showAlert = true
            return
        }

        selectedLocation = location
        isValidating = true

        // Step 1: Lightweight server pre-check (dryRun)
        if let userLocation = locationManager.currentLocation {
            LocationAPI.shared.checkIn(
                locationId: location.id,
                type: location.type,
                userCoordinate: .init(latitude: userLocation.coordinate.latitude, longitude: userLocation.coordinate.longitude),
                dryRun: true
            ) { result in
                isValidating = false

                switch result {
                case .success:
                    startCheckInTimer()

                case .failure(let error):
                    errorMessage = error.localizedDescription
                    showAlert = true
                    showSuccessAlert = false
                    selectedLocation = nil
                }
            }
        } else {
            isValidating = false
            errorMessage = locationUnavailableMessage
            showAlert = true
            selectedLocation = nil
        }
    }

    private func cancelDwell() {
        stopCheckInTimer()
        isSubmittingFinalCheckIn = false
        isValidating = false
        checkInProgress = 0
        checkInRemainingSeconds = 0
        withAnimation {
            isDwelling = false
            selectedLocation = nil
        }
    }

    private func submitFinalCheckIn() {
        guard let location = selectedLocation,
              !isSubmittingFinalCheckIn else { return }

        isSubmittingFinalCheckIn = true
        isValidating = true

        if let userLocation = locationManager.currentLocation {
            LocationAPI.shared.checkIn(
                locationId: location.id,
                type: location.type,
                userCoordinate: .init(latitude: userLocation.coordinate.latitude, longitude: userLocation.coordinate.longitude),
                dryRun: false
            ) { result in
                isValidating = false
                isSubmittingFinalCheckIn = false

                switch result {
                case .success:
                    successMessage = "Check-in successful!"
                    showSuccessAlert = true
                    showAlert = false
                    print("✅ Check-in submitted successfully")
                    let oldKingId = selectedLocation?.king_user_id
                    let locId = selectedLocation?.id
                    let locName = selectedLocation?.name ?? ""

                    if oldKingId == UserModel.shared.user?.id, let lid = locId {
                        checkDethroned(locationId: lid, locationName: locName)
                    }

                    cancelDwell()
                case .failure(let error):
                    errorMessage = error.localizedDescription
                    showAlert = true
                    showSuccessAlert = false
                    cancelDwell()
                }
            }
        } else {
            isValidating = false
            isSubmittingFinalCheckIn = false
            errorMessage = locationUnavailableMessage
            showAlert = true
        }
    }

    private func startCheckInTimer() {
        withAnimation {
            isDwelling = true
        }
        checkInProgress = 0
        checkInRemainingSeconds = 30

        stopCheckInTimer()
        checkInTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            checkInTick()
        }
    }

    private func stopCheckInTimer() {
        checkInTimer?.invalidate()
        checkInTimer = nil
    }

    private func checkInTick() {
        DispatchQueue.main.async {
            guard isDwelling else { return }
            checkInRemainingSeconds = max(checkInRemainingSeconds - 1, 0)
            checkInProgress = min(1.0, checkInProgress + (1.0 / 30.0))

            if checkInRemainingSeconds <= 0 {
                stopCheckInTimer()
                submitFinalCheckIn()
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
        ) { items, _, _ in
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
        if merchant.type ?? "".lowercased() == "hidden_gems" {
            return .yellow
        }
        return isPartner ? .purple : .green
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
                    // `scaledToFill` overflows its frame, and the hosting view
                    // doesn't clip — an oversized photo would paint across the map.
                    .clipped()
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
    /// Dismisses the card. Only clears the selection — tapping this pin again,
    /// or any other, brings it straight back.
    var onClose: (() -> Void)? = nil

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
            .overlay(alignment: .topTrailing) {
                if let onClose {
                    CardCloseButton(action: onClose)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }
}

// MARK: - Card Close Button

/// The dismiss affordance shared by the check-in and mystery cards.
struct CardCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.black.opacity(0.55))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.black.opacity(0.07)))
        }
        .padding(10)
        .accessibilityLabel("Close")
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
    let type: String?
}

extension NearbyLocationResponse {
    var asMerchant: MerchantLocation {
        MerchantLocation(
            id: id,
            name: name,
            category: category ?? "",
            emoji: "📍",
            xpReward: xp_reward,
            coordinate: coordinate,
            can_checkin: can_checkin,
            imageUrl: WebService.resolvedImageUrl(image_url),
            kingUserId: king_user_id,
            kingFalconName: king_falcon_name,
            boundaryPolygon: boundary_polygon,
            type:type
        )
    }
}

struct MerchantWithDistance: Identifiable {
    let id = UUID()
    let merchant: MerchantLocation
    let distance: Double
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
