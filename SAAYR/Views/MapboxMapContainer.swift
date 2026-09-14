import SwiftUI
import MapboxMaps
import CoreLocation

struct MapCameraFocus: Equatable {
    let latitude: Double
    let longitude: Double
    let zoom: Double
}

struct MapboxCameraState {
    let center: CLLocationCoordinate2D
    let zoom: Double
    let north: Double
    let south: Double
    let east: Double
    let west: Double
}

struct VisibleMapRegion {
    let centerLat: Double
    let centerLng: Double
    let latDelta: Double
    let lngDelta: Double
}

struct MapboxMapContainer: UIViewRepresentable {

    /// Already filtered to what the player is allowed to see — the container
    /// renders these as-is. Read-only, so it isn't a binding.
    var locations: [NearbyLocationResponse]
    @Binding var selectedLocation: NearbyLocationResponse?
    @Binding var focusOn: MapCameraFocus?

    var merchantPolygon: [PolygonPoint]?
    /// The area of a tapped-but-undiscovered landmark: shows where to walk to
    /// without saying what's waiting there.
    var mysteryArea: [PolygonPoint]?
    /// `uniqueKey`s of landmarks this player hasn't discovered yet — drawn as
    /// mystery pins instead of merchant markers.
    var lockedLandmarkKeys: Set<String>
    /// `uniqueKey`s of locations that count towards the current boss — drawn
    /// as boss markers so an on-site event has somewhere to point at.
    var bossKeys: Set<String> = []
    var zones: [Zone]
    /// The playable circle, when the server has sent one.
    var coverage: ZoneCoverageConfig?
    /// Areas of the boss the home banner is advertising, drawn in red above
    /// the fog. Empty whenever no banner is showing, which is what takes the
    /// overlay back off the map.
    var bossZones: [BossZone] = []
    /// Picks `name_ar` over `name` for the zone labels.
    var isArabic: Bool
    var isCheckingIn: Bool
    var onCameraChanged: (MapboxCameraState) -> Void
    var onTapLocation: (NearbyLocationResponse) -> Void

    typealias UIViewType = MapboxMaps.MapView

    /// The custom Saayr style from Mapbox Studio, falling back to Mapbox's
    /// built-in Standard style when no style URL is configured.
    static var styleURI: MapboxMaps.StyleURI {
        guard !WebService.mapboxStyleURL.isEmpty,
              let custom = MapboxMaps.StyleURI(rawValue: WebService.mapboxStyleURL)
        else { return .standard }
        return custom
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MapboxMaps.MapView {

        let mapView = MapboxMaps.MapView(frame: CGRect.zero)

        mapView.mapboxMap.loadStyle(Self.styleURI) { error in
            if let error {
                print("⚠️ Mapbox style failed to load:", error)
            }
        }

        mapView.location.options.puckType = MapboxMaps.PuckType.puck2D()
        // Without a center the camera starts at 0,0 in the Atlantic. Riyadh is
        // the sensible placeholder until the first fix moves us.
        mapView.mapboxMap.setCamera(
            to: CameraOptions(
                center: MapView.riyadh,
                zoom: 11,
                bearing: 0, pitch: 30
            )
        )
        // ✅ FIXED observer (NO forced event typing)
        context.coordinator.cameraObserver =
            mapView.mapboxMap.onCameraChanged.observe { [weak mapView] event in
                guard let mapView else { return }

                let camera = event.cameraState

                let bounds: CoordinateBounds =
                    mapView.mapboxMap.coordinateBounds(for: mapView.bounds)

                context.coordinator.parent.onCameraChanged(
                    MapboxCameraState(
                        center: camera.center,
                        zoom: camera.zoom,
                        north: bounds.north,
                        south: bounds.south,
                        east: bounds.east,
                        west: bounds.west
                    )
                )
            }

        context.coordinator.mapView = mapView
        return mapView
    }

    func updateUIView(_ mapView: MapboxMaps.MapView, context: Context) {

        context.coordinator.parent = self

        // Zones first so the merchant polygon and markers draw above them.
        context.coordinator.syncZones(
            mapView: mapView,
            zones: zones,
            coverage: coverage,
            isArabic: isArabic
        )

        // After the fog, before the markers: the boss areas have to sit over
        // the blackout and under everything the player can tap.
        context.coordinator.syncBossZones(mapView: mapView, zones: bossZones)

        context.coordinator.syncAnnotations(
            mapView: mapView,
            locations: locations,
            selectedKey: selectedLocation?.uniqueKey,
            lockedLandmarkKeys: lockedLandmarkKeys,
            bossKeys: bossKeys
        )

        context.coordinator.syncPolygon(
            mapView: mapView,
            polygon: merchantPolygon
        )

        #if DEBUG
        // TEMPORARY — last, so it draws over the pins. See `syncCoverageCentre`.
        context.coordinator.syncCoverageCentre(mapView: mapView, coverage: coverage)
        #endif

        context.coordinator.syncMysteryArea(
            mapView: mapView,
            polygon: mysteryArea
        )

        // ✅ SAFE focus handling
        if let focus = focusOn {

            let camera = CameraOptions(
                center: CLLocationCoordinate2D(
                    latitude: focus.latitude,
                    longitude: focus.longitude
                ),
                zoom: focus.zoom
            )

            mapView.camera.fly(to: camera, duration: 0.3)

            DispatchQueue.main.async {
                context.coordinator.parent.focusOn = nil
            }
        }
    }

    static func dismantleUIView(_ uiView: MapboxMaps.MapView, coordinator: Coordinator) {
        coordinator.cameraObserver?.cancel()
        coordinator.annotationViews.removeAll()
    }

    // MARK: - Coordinator

    class Coordinator: NSObject {

        var parent: MapboxMapContainer
        weak var mapView: MapboxMaps.MapView?

        var annotationViews: [String: UIView] = [:]
        private var lastDigest: Int = -1

        var cameraObserver: Cancelable?

        // Polygon annotation state
        private var polygonManager: PolygonAnnotationManager?
        private var outlineManager: PolylineAnnotationManager?
        private var currentPolygonDigest: Int = -1

        // Mystery landmark area state
        private var mysteryFillManager: PolygonAnnotationManager?
        private var mysteryOutlineManager: PolylineAnnotationManager?
        private var currentMysteryDigest: Int = -1

        // Zone annotation state
        private var zoneFogManager: PolygonAnnotationManager?
        private var zoneFillManager: PolygonAnnotationManager?
        private var zoneLockedFillManager: PolygonAnnotationManager?
        private var zoneLockedOutlineManager: PolylineAnnotationManager?
        private var zoneLabelManager: PointAnnotationManager?
        #if DEBUG
        private var coverageCentreManager: CircleAnnotationManager?
        private var coverageCentreDigest: String = ""
        #endif
        private var currentZonesDigest: Int = -1

        // Boss zone annotation state
        private var bossZoneFillManager: PolygonAnnotationManager?
        private var bossZoneOutlineManager: PolylineAnnotationManager?
        private var currentBossZonesDigest: Int = -1

        /// Zone shading. An unlocked zone is a light green wash with no
        /// border — it is already explored, so nothing needs to draw the eye
        /// to it. `fog` blacks out everything outside the zones, and locked
        /// zones keep a stroke because they are what is still to be found.
        private enum ZoneStyle {
            static let fill   = StyleColor(red: 21, green: 106, blue: 71, alpha: 0.10)
            /// The rest of the world is blacked out rather than dimmed — only
            /// the zones are available to be viewed. Held just short of opaque
            /// so the major roads still ghost through and the blackout reads as
            /// deliberate rather than as a failed render. This is the knob:
            /// raise towards 1.0 for a harder blackout, lower for more of the
            /// basemap. Keep it well clear of `lockedFill` below so locked
            /// zones stay a distinct shade from out-of-bounds ground.
            static let fog    = StyleColor(red: 8, green: 20, blue: 16, alpha: 0.82)

            /// Locked zones sit in their own hole in the fog and are shaded
            /// here instead — dark enough to read as off-limits, sheer enough
            /// that the streets still show, so they look like regions waiting
            /// to be unlocked rather than more blacked-out world.
            static let lockedFill   = StyleColor(red: 8, green: 20, blue: 16, alpha: 0.58)
            static let lockedStroke = StyleColor(red: 21, green: 106, blue: 71, alpha: 0.6)
            static let lockedLineWidth: Double = 1.5

            /// Zone names: same green as the boundary on a white halo where the
            /// zone is revealed, inverted over the dark shading where it isn't.
            static let labelColor     = StyleColor(red: 16, green: 78, blue: 52, alpha: 1.0)
            static let labelHalo      = StyleColor(red: 255, green: 255, blue: 255, alpha: 0.9)
            static let lockedLabelColor = StyleColor(red: 240, green: 246, blue: 243, alpha: 1.0)
            static let lockedLabelHalo  = StyleColor(red: 8, green: 20, blue: 16, alpha: 0.7)
            static let labelSize: Double      = 15
            static let labelHaloWidth: Double = 1.6
        }

        /// The coverage look: one circle of playable ground, everything beyond
        /// it blacked out. Zones stop being holes in the fog and become plain
        /// shading inside the circle — grey while unexplored, nothing at all
        /// once explored, so the map fills in as the player covers it.
        private enum CoverageStyle {
            /// Peak darkness outside the circle. Short of opaque for the same
            /// reason as the older fog: the roads ghosting through read as
            /// deliberate rather than as a failed render.
            static let maxOpacity: Double = 0.96
            static let fogRed = 13.0, fogGreen = 23.0, fogBlue = 21.0

            static let lockedFill   = StyleColor(red: 143, green: 151, blue: 143, alpha: 0.55)
            static let lockedStroke = StyleColor(red: 46, green: 125, blue: 79, alpha: 1.0)
            static let lockedLineWidth: Double = 2.0

            /// Appended to an explored zone's name.
            static let exploredMark = " ✓"

            /// Optional to match `StyleColor`'s own failable initialiser, the
            /// way every colour above is.
            static func fog(_ fraction: Double) -> StyleColor? {
                StyleColor(red: fogRed, green: fogGreen, blue: fogBlue, alpha: maxOpacity * fraction)
            }
        }

        /// The boss areas. Red because nothing else on this map is — the
        /// zones are green and the fog is near-black, so red reads as "this
        /// is the event" without competing with anything.
        private enum BossZoneStyle {
            static let stroke = StyleColor(red: 214, green: 45, blue: 45, alpha: 1.0)
            static let fill   = StyleColor(red: 214, green: 45, blue: 45, alpha: 0.15)
            static let lineWidth: Double = 3.0
        }

        /// Standard-style slot for everything we draw. `top` sits above the
        /// basemap's labels and POIs but still inside the imported style, so the
        /// location puck — which has no slot and therefore sits above the whole
        /// import — keeps rendering over our layers instead of under the fog.
        private static let overlaySlot = "top"

        /// Outer ring for the fog polygon. Stops short of the antimeridian and
        /// the poles so the shape never wraps on itself.
        private static let worldRing = Ring(coordinates: [
            CLLocationCoordinate2D(latitude: -85, longitude: -179.9),
            CLLocationCoordinate2D(latitude: -85, longitude:  179.9),
            CLLocationCoordinate2D(latitude:  85, longitude:  179.9),
            CLLocationCoordinate2D(latitude:  85, longitude: -179.9),
            CLLocationCoordinate2D(latitude: -85, longitude: -179.9)
        ])

        /// Deep green boundary over a soft translucent fill.
        private enum PolygonStyle {
            static let stroke = StyleColor(red: 21, green: 106, blue: 71, alpha: 1.0)
            static let fill   = StyleColor(red: 21, green: 106, blue: 71, alpha: 0.14)
            static let lineWidth: Double = 3
        }

        /// The area of an undiscovered landmark: the violet of the mystery pin,
        /// so it reads as "walk in here to find out" rather than as a merchant
        /// you could already check into.
        private enum MysteryAreaStyle {
            static let stroke = StyleColor(red: 124, green: 58, blue: 237, alpha: 0.95)
            static let fill   = StyleColor(red: 124, green: 58, blue: 237, alpha: 0.16)
            static let lineWidth: Double = 3
        }

        init(parent: MapboxMapContainer) {
            self.parent = parent
        }

        func syncAnnotations(
            mapView: MapboxMaps.MapView,
            locations: [NearbyLocationResponse],
            selectedKey: String?,
            lockedLandmarkKeys: Set<String>,
            bossKeys: Set<String>
        ) {
            // Both sets are part of the digest: discovering a landmark has to
            // redraw its pin from mystery to merchant, and a boss starting or
            // ending has to swap those pins too.
            let digest = locations.map(\.uniqueKey).joined(separator: "|").hashValue
                ^ (selectedKey?.hashValue ?? 0)
                ^ lockedLandmarkKeys.sorted().joined(separator: "|").hashValue
                ^ bossKeys.sorted().joined(separator: "|").hashValue
            guard digest != lastDigest else { return }
            lastDigest = digest

            for (_, view) in annotationViews {
                mapView.viewAnnotations.remove(view)
            }
            annotationViews.removeAll()

            for location in locations {

                let isActive = location.uniqueKey == selectedKey
                let view = makeAnnotationView(
                    for: location,
                    isActive: isActive,
                    isLocked: lockedLandmarkKeys.contains(location.uniqueKey),
                    isBoss: bossKeys.contains(location.uniqueKey)
                )

                annotationViews[location.uniqueKey] = view

                // ✅ FIXED Point usage for v11
                let point = Point(
                    CLLocationCoordinate2D(
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude
                    )
                )

                // Every knob Mapbox can use to hide a marker is pinned open here,
                // so a pin only ever leaves the screen by being panned off it.
                // `allowOverlap` is the one that bites when zooming out: markers
                // that were spread apart start colliding as the view widens, and
                // the default behaviour is to hide the ones that collide rather
                // than shift them. `minZoom`/`maxZoom` are stated rather than
                // left to the defaults so no zoom range can cull them either.
                let options = ViewAnnotationOptions(
                    annotatedFeature: .geometry(point),
                    width: 60,
                    height: 72,
                    allowOverlap: true,
                    allowOverlapWithPuck: true,
                    visible: true,
                    variableAnchors: .center,
                    ignoreCameraPadding: true,
                    minZoom: 0,
                    maxZoom: 22
                )

                try? mapView.viewAnnotations.add(view, options: options)
            }
        }

        private func makeAnnotationView(
            for location: NearbyLocationResponse,
            isActive: Bool,
            isLocked: Bool,
            isBoss: Bool
        ) -> UIView {

            // Order matters. A mystery pin outranks everything — revealing that
            // an undiscovered landmark is a boss target would give away that
            // there's something there at all. A boss target outranks the
            // ordinary merchant marker, because during an event that's the
            // reason to walk to it.
            let markerView: AnyView
            if isLocked {
                markerView = AnyView(MysteryMarkerView())
            } else if isBoss {
                markerView = AnyView(BossMarkerView())
            } else {
                markerView = AnyView(MerchantMarkerView(
                    merchant: location.asMerchant,
                    isInRange: true,
                    isActive: isActive,
                    isPartner: location.is_partner
                ))
            }

            let hc = UIHostingController(rootView: markerView)
            hc.view.backgroundColor = .clear
            hc.view.frame = CGRect(x: 0, y: 0, width: 60, height: 72)
            hc.view.accessibilityIdentifier = location.uniqueKey

            hc.view.addGestureRecognizer(
                UITapGestureRecognizer(
                    target: self,
                    action: #selector(handleAnnotationTap(_:))
                )
            )

            return hc.view
        }

        @objc private func handleAnnotationTap(_ sender: UITapGestureRecognizer) {
            guard let key = sender.view?.accessibilityIdentifier,
                  !parent.isCheckingIn,
                  let location = parent.locations.first(where: { $0.uniqueKey == key })
            else { return }

            parent.onTapLocation(location)
        }

        // MARK: - Zone Annotations

        func syncZones(
            mapView: MapboxMaps.MapView,
            zones: [Zone],
            coverage: ZoneCoverageConfig?,
            isArabic: Bool
        ) {
            let circle = coverage.map { "\($0.center.lat),\($0.center.lng),\($0.radius),\($0.fade)" } ?? "none"
            let digest = (zones
                .map { "\($0.id):\($0.is_unlocked)" }
                .joined(separator: "|") + "|ar:\(isArabic)|circle:\(circle)")
                .hashValue
            guard digest != currentZonesDigest else { return }
            currentZonesDigest = digest

            // Managers draw in creation order, and everything below is about
            // to be torn down and remade — which would leave the fog newer
            // than the boss overlay, hiding it. Forcing a rebuild makes
            // `syncBossZones`, called straight after this in the same pass,
            // the last one created again.
            currentBossZonesDigest = -1

            if zoneFogManager != nil {
                mapView.annotations.removeAnnotationManager(withId: "zones-fog")
                zoneFogManager = nil
            }
            if zoneFillManager != nil {
                mapView.annotations.removeAnnotationManager(withId: "zones-fill")
                zoneFillManager = nil
            }
            if zoneLockedFillManager != nil {
                mapView.annotations.removeAnnotationManager(withId: "zones-locked-fill")
                zoneLockedFillManager = nil
            }
            if zoneLockedOutlineManager != nil {
                mapView.annotations.removeAnnotationManager(withId: "zones-locked-outline")
                zoneLockedOutlineManager = nil
            }
            if zoneLabelManager != nil {
                mapView.annotations.removeAnnotationManager(withId: "zones-labels")
                zoneLabelManager = nil
            }


            // Deferred so the names are the last manager created and therefore
            // draw above every shaded region, whichever way this function exits.
            defer { installZoneLabels(mapView: mapView, zones: zones, isArabic: isArabic) }

            let unlockedRings = Self.rings(of: zones.filter(\.is_unlocked).map(\.boundary_polygon))
            let lockedRings   = Self.rings(of: zones.filter { !$0.is_unlocked }.map(\.boundary_polygon))

            // Two fog models, and only ever one of them. The circle replaces
            // the blackout rather than adding to it — drawing both would stack
            // two darkenings over the same ground.
            if let coverage {
                // Shading first, blackout second — the reverse of the older
                // model. A zone can reach past the circle, and out there it is
                // not playable ground, so the fog has to cover it rather than
                // the other way round.
                installLockedZones(mapView: mapView, rings: lockedRings, style: .coverage)
                installCoverageFog(mapView: mapView, coverage: coverage)
                // An explored zone is drawn as nothing at all: no fill, no
                // border. Covered ground is simply clear.
                return
            }

            // Created first so every shaded region below draws over the fog.
            installFog(mapView: mapView, zoneRings: unlockedRings + lockedRings)
            installLockedZones(mapView: mapView, rings: lockedRings, style: .legacy)

            guard !unlockedRings.isEmpty else { return }

            // Fills abut without overlapping, so drawing them per zone already
            // reads as one shape.
            var fills: [PolygonAnnotation] = []
            for coords in unlockedRings {
                let shape = Polygon(outerRing: Ring(coordinates: coords), innerRings: [])
                var fill = PolygonAnnotation(polygon: shape)
                fill.fillColor = ZoneStyle.fill
                fills.append(fill)
            }

            // No outline. An unlocked zone is somewhere the player has already
            // been, and a border around it keeps drawing attention to ground
            // that is finished with. What is left to explore is what should be
            // outlined, so only locked zones carry a stroke — the hard edge
            // between the light fill and the fog is enough to read the shape.
            guard !fills.isEmpty else { return }

            let fillManager = mapView.annotations.makePolygonAnnotationManager(id: "zones-fill")
            fillManager.slot = Self.overlaySlot
            fillManager.annotations = fills
            zoneFillManager = fillManager
        }

        // MARK: - Boss Zone Annotations

        /// Draws the boss areas in red, or clears them when there are none.
        /// An empty `zones` is the normal way this ends: the banner stopped
        /// showing a boss, so the overlay comes off.
        func syncBossZones(mapView: MapboxMaps.MapView, zones: [BossZone]) {
            let digest = zones.map { "\($0.id)" }.joined(separator: "|").hashValue
            guard digest != currentBossZonesDigest else { return }
            currentBossZonesDigest = digest

            if bossZoneFillManager != nil {
                mapView.annotations.removeAnnotationManager(withId: "boss-zones-fill")
                bossZoneFillManager = nil
            }
            if bossZoneOutlineManager != nil {
                mapView.annotations.removeAnnotationManager(withId: "boss-zones-outline")
                bossZoneOutlineManager = nil
            }

            let rings = Self.rings(of: zones.map(\.boundary_polygon))
            guard !rings.isEmpty else { return }

            var fills: [PolygonAnnotation] = []
            var outlines: [PolylineAnnotation] = []
            for coords in rings {
                var fill = PolygonAnnotation(
                    polygon: Polygon(outerRing: Ring(coordinates: coords), innerRings: [])
                )
                fill.fillColor = BossZoneStyle.fill
                fills.append(fill)

                // A polyline is open: without repeating the first point the
                // segment back to it is never drawn and the ring shows a gap
                // along whichever edge the boundary happens to start on.
                var outline = PolylineAnnotation(lineCoordinates: coords + [coords[0]])
                outline.lineColor = BossZoneStyle.stroke
                outline.lineWidth = BossZoneStyle.lineWidth
                outline.lineJoin = .round
                outlines.append(outline)
            }

            let fillManager = mapView.annotations.makePolygonAnnotationManager(id: "boss-zones-fill")
            fillManager.slot = Self.overlaySlot
            fillManager.annotations = fills
            bossZoneFillManager = fillManager

            let lineManager = mapView.annotations.makePolylineAnnotationManager(id: "boss-zones-outline")
            lineManager.slot = Self.overlaySlot
            lineManager.lineCap = .round
            lineManager.annotations = outlines
            bossZoneOutlineManager = lineManager
        }

        /// Boundary rings of `zones`, as map coordinates, dropping any too
        /// degenerate to enclose an area.
        private static func rings(of boundaries: [[ZoneCoordinate]]) -> [[CLLocationCoordinate2D]] {
            boundaries
                .map { boundary in
                    boundary.map {
                        CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng)
                    }
                }
                .filter { $0.count >= 3 }
        }

        /// Closed rings for the outer boundary of a group of zones, with the
        /// seams between neighbours dropped where they can be merged exactly.
        private static func mergedRings(
            of rings: [[CLLocationCoordinate2D]]
        ) -> [[CLLocationCoordinate2D]] {
            let (boxes, others) = ZoneBoundaryMerger.partition(rings)
            return ZoneBoundaryMerger.unionRings(of: boxes)
                + others.map { ring in ring + (ring.first.map { [$0] } ?? []) }
        }

        /// Blacks out everything that isn't a zone: one world-sized polygon with
        /// every zone punched out as a hole. It's a real geo feature, so the
        /// blackout stays glued to the streets through pan, zoom, rotate and
        /// tilt.
        ///
        /// Locked zones are punched out too — they're shaded separately by
        /// `installLockedZones` so they stay legible as regions you haven't
        /// reached yet. Only genuinely out-of-bounds ground goes black.
        /// The coverage circle: clear inside, black outside, and a short graded
        /// band across the edge so the boundary reads as a horizon rather than
        /// a cut.
        ///
        /// Four shapes. Three are rings stepping up through the fade, and the
        /// last is the whole world with the outermost ring punched out of it.
        /// They abut rather than overlap, so each one's opacity is the opacity
        /// of that band — nothing compounds.
        private func installCoverageFog(
            mapView: MapboxMaps.MapView,
            coverage: ZoneCoverageConfig
        ) {
            let centre = coverage.coordinate
            let radius = coverage.radiusMeters
            let fade = max(coverage.fadeMeters, 0)

            // A circle with no radius would black out the map entirely, which
            // reads as a broken screen. Leave it uncovered instead.
            guard radius > 0 else { return }

            let bands: [(from: Double, to: Double?, fraction: Double)] = [
                (radius,               radius + fade * 0.33, 0.25),
                (radius + fade * 0.33, radius + fade * 0.66, 0.50),
                (radius + fade * 0.66, radius + fade,        0.75),
                (radius + fade,        nil,                  1.00)
            ]

            var shapes: [PolygonAnnotation] = []
            for band in bands {
                let outer = band.to.map { Ring(coordinates: Self.circle(around: centre, radius: $0)) }
                    ?? Self.worldRing
                let inner = Ring(coordinates: Self.circle(around: centre, radius: band.from))

                var shape = PolygonAnnotation(polygon: Polygon(outerRing: outer, innerRings: [inner]))
                shape.fillColor = CoverageStyle.fog(band.fraction)
                shapes.append(shape)
            }

            let manager = mapView.annotations.makePolygonAnnotationManager(id: "zones-fog")
            manager.slot = Self.overlaySlot
            manager.annotations = shapes
            zoneFogManager = manager
        }

        #if DEBUG
        /// TEMPORARY: marks where the server says the coverage circle is
        /// centred, so the config can be checked against the ground without
        /// measuring the fog's edge. Drawn in screen points rather than metres
        /// so it stays a dot at every zoom, and installed after the markers so
        /// a pin standing on the centre can't hide it. Delete this, its call in
        /// `updateUIView` and its teardown once the centre is confirmed.
        func syncCoverageCentre(
            mapView: MapboxMaps.MapView,
            coverage: ZoneCoverageConfig?
        ) {
            let digest = coverage.map { "\($0.center.lat),\($0.center.lng)" } ?? "none"
            guard digest != coverageCentreDigest else { return }
            coverageCentreDigest = digest

            if coverageCentreManager != nil {
                mapView.annotations.removeAnnotationManager(withId: "coverage-centre")
                coverageCentreManager = nil
            }
            guard let coverage else { return }

            var dot = CircleAnnotation(centerCoordinate: coverage.coordinate)
            dot.circleRadius = 7
            dot.circleColor = StyleColor(red: 232, green: 163, blue: 61, alpha: 1.0)
            dot.circleStrokeWidth = 3
            dot.circleStrokeColor = StyleColor(red: 255, green: 255, blue: 255, alpha: 1.0)

            let manager = mapView.annotations.makeCircleAnnotationManager(id: "coverage-centre")
            manager.slot = Self.overlaySlot
            manager.annotations = [dot]
            coverageCentreManager = manager
        }
        #endif

        /// A closed ring of `points` around `centre`. Longitude degrees shrink
        /// towards the poles, so the circle stays round on the ground instead
        /// of being drawn as an ellipse.
        private static func circle(
            around centre: CLLocationCoordinate2D,
            radius metres: Double,
            points: Int = 90
        ) -> [CLLocationCoordinate2D] {
            let latitudeDegrees = metres / 111_320
            let longitudeDegrees = metres / (111_320 * max(cos(centre.latitude * .pi / 180), 0.01))

            return (0...points).map { step in
                let angle = (Double(step) / Double(points)) * 2 * .pi
                return CLLocationCoordinate2D(
                    latitude: centre.latitude + latitudeDegrees * sin(angle),
                    longitude: centre.longitude + longitudeDegrees * cos(angle)
                )
            }
        }

        private func installFog(
            mapView: MapboxMaps.MapView,
            zoneRings: [[CLLocationCoordinate2D]]
        ) {
            let holes = Self.mergedRings(of: zoneRings)
                .filter { $0.count >= 4 }
                .map { Ring(coordinates: $0) }
            // With no zones loaded the whole map would go black, which reads as
            // a broken screen rather than a locked one. Leave it uncovered.
            guard !holes.isEmpty else { return }

            var fog = PolygonAnnotation(
                polygon: Polygon(outerRing: Self.worldRing, innerRings: holes)
            )
            fog.fillColor = ZoneStyle.fog

            let fogManager = mapView.annotations.makePolygonAnnotationManager(id: "zones-fog")
            fogManager.slot = Self.overlaySlot
            fogManager.annotations = [fog]
            zoneFogManager = fogManager
        }

        /// Shades every locked zone as its own dark block with a soft boundary,
        /// so the areas still to be unlocked are visible as regions.
        /// Which palette an unexplored zone is shaded with. The older fog cuts
        /// zones out of a blackout, so a locked one has to read as darker
        /// ground; inside the coverage circle there is no blackout to be
        /// darker than, so it reads as grey instead.
        enum LockedZoneStyle { case legacy, coverage }

        private func installLockedZones(
            mapView: MapboxMaps.MapView,
            rings: [[CLLocationCoordinate2D]],
            style: LockedZoneStyle
        ) {
            guard !rings.isEmpty else { return }

            let fillColor = style == .coverage ? CoverageStyle.lockedFill : ZoneStyle.lockedFill
            let strokeColor = style == .coverage ? CoverageStyle.lockedStroke : ZoneStyle.lockedStroke
            let strokeWidth = style == .coverage ? CoverageStyle.lockedLineWidth : ZoneStyle.lockedLineWidth

            var fills: [PolygonAnnotation] = []
            var outlines: [PolylineAnnotation] = []
            for coords in rings {
                var fill = PolygonAnnotation(
                    polygon: Polygon(outerRing: Ring(coordinates: coords), innerRings: [])
                )
                fill.fillColor = fillColor
                fills.append(fill)

                // Repeat the first point so the stroke closes the ring.
                var ring = coords
                if let first = coords.first { ring.append(first) }

                var outline = PolylineAnnotation(lineCoordinates: ring)
                outline.lineColor = strokeColor
                outline.lineWidth = strokeWidth
                outline.lineJoin = .round
                outlines.append(outline)
            }

            let fillManager = mapView.annotations.makePolygonAnnotationManager(id: "zones-locked-fill")
            fillManager.slot = Self.overlaySlot
            fillManager.annotations = fills
            zoneLockedFillManager = fillManager

            let lineManager = mapView.annotations.makePolylineAnnotationManager(id: "zones-locked-outline")
            lineManager.slot = Self.overlaySlot
            lineManager.lineCap = .round
            lineManager.annotations = outlines
            zoneLockedOutlineManager = lineManager
        }

        /// One name per zone, green-on-white where the zone is unlocked and
        /// light-on-dark where it's still shaded.
        private func installZoneLabels(
            mapView: MapboxMaps.MapView,
            zones: [Zone],
            isArabic: Bool
        ) {
            // An explored zone loses its shading entirely in the coverage look,
            // so the tick is the only thing left saying it was ever unexplored.
            let marksExplored = parent.coverage != nil

            var labels: [PointAnnotation] = []
            for zone in zones {
                let title = isArabic
                    ? (zone.name_ar.isEmpty ? zone.name : zone.name_ar)
                    : (zone.name.isEmpty ? zone.name_ar : zone.name)
                guard !title.isEmpty, let center = Self.labelCenter(of: zone) else { continue }

                var label = PointAnnotation(id: "zone-label-\(zone.id)", point: Point(center))
                label.textField = marksExplored && zone.is_unlocked
                    ? title + CoverageStyle.exploredMark
                    : title
                // The pale-on-dark pair is for the older fog, where an
                // unexplored zone is a dark hole. Inside the coverage circle
                // it is grey over a light basemap instead, so every name reads
                // dark on a bright halo whichever side of explored it is on.
                let onDarkGround = !zone.is_unlocked && parent.coverage == nil
                label.textColor = onDarkGround ? ZoneStyle.lockedLabelColor : ZoneStyle.labelColor
                label.textHaloColor = onDarkGround ? ZoneStyle.lockedLabelHalo : ZoneStyle.labelHalo
                label.textHaloWidth = ZoneStyle.labelHaloWidth
                label.textSize = ZoneStyle.labelSize
                label.textAnchor = .center
                // Long names wrap instead of spilling across the whole zone.
                label.textMaxWidth = 8
                labels.append(label)
            }

            guard !labels.isEmpty else { return }

            let labelManager = mapView.annotations.makePointAnnotationManager(id: "zones-labels")
            labelManager.slot = Self.overlaySlot
            // Zone names outrank the basemap's own labels: always draw them, and
            // don't let them suppress the POI labels underneath.
            labelManager.textAllowOverlap = true
            labelManager.textIgnorePlacement = true
            labelManager.annotations = labels
            zoneLabelManager = labelManager
        }

        /// Where a zone's name goes: the API's centre when it parses, otherwise
        /// the average of the boundary points.
        private static func labelCenter(of zone: Zone) -> CLLocationCoordinate2D? {
            if let lat = Double(zone.center_lat), let lng = Double(zone.center_lng),
               lat != 0 || lng != 0 {
                return CLLocationCoordinate2D(latitude: lat, longitude: lng)
            }

            let points = zone.boundary_polygon
            guard !points.isEmpty else { return nil }
            let count = Double(points.count)
            return CLLocationCoordinate2D(
                latitude: points.reduce(0) { $0 + $1.lat } / count,
                longitude: points.reduce(0) { $0 + $1.lng } / count
            )
        }

        // MARK: - Mystery Landmark Area

        /// Draws where an undiscovered landmark is, without drawing what it is.
        /// Created after the merchant polygon so the two never fight over which
        /// sits on top when a selection changes.
        func syncMysteryArea(mapView: MapboxMaps.MapView, polygon: [PolygonPoint]?) {
            let digest = polygon?.hashValue ?? -1
            guard digest != currentMysteryDigest else { return }
            currentMysteryDigest = digest

            if mysteryFillManager != nil {
                mapView.annotations.removeAnnotationManager(withId: "mystery-area")
                mysteryFillManager = nil
            }
            if mysteryOutlineManager != nil {
                mapView.annotations.removeAnnotationManager(withId: "mystery-area-outline")
                mysteryOutlineManager = nil
            }

            guard let points = polygon, points.count >= 3 else { return }

            let coords = points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }

            var fill = PolygonAnnotation(
                polygon: Polygon(outerRing: Ring(coordinates: coords), innerRings: [])
            )
            fill.fillColor = MysteryAreaStyle.fill

            let fillManager = mapView.annotations.makePolygonAnnotationManager(id: "mystery-area")
            fillManager.slot = Self.overlaySlot
            fillManager.annotations = [fill]
            mysteryFillManager = fillManager

            // Repeat the first point so the stroke closes the ring.
            var ringCoords = coords
            if let first = coords.first { ringCoords.append(first) }

            var outline = PolylineAnnotation(lineCoordinates: ringCoords)
            outline.lineColor = MysteryAreaStyle.stroke
            outline.lineWidth = MysteryAreaStyle.lineWidth
            outline.lineJoin = .round

            let lineManager = mapView.annotations.makePolylineAnnotationManager(id: "mystery-area-outline")
            lineManager.slot = Self.overlaySlot
            lineManager.lineCap = .round
            lineManager.annotations = [outline]
            mysteryOutlineManager = lineManager
        }

        // MARK: - Polygon Annotation

        func syncPolygon(mapView: MapboxMaps.MapView, polygon: [PolygonPoint]?) {
            // Compute digest to avoid redundant updates
            let digest = polygon?.hashValue ?? -1
            guard digest != currentPolygonDigest else { return }
            currentPolygonDigest = digest

            // Remove existing polygon if present
            if polygonManager != nil {
                mapView.annotations.removeAnnotationManager(withId: "merchant-polygon")
                polygonManager = nil
            }
            if outlineManager != nil {
                mapView.annotations.removeAnnotationManager(withId: "merchant-polygon-outline")
                outlineManager = nil
            }

            guard let points = polygon, points.count >= 3 else { return }

            let coords = points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
            let outerRing = Ring(coordinates: coords)
            let polygonShape = Polygon(outerRing: outerRing, innerRings: [])

            // Fill only — `fillOutlineColor` can just draw a hairline, so the
            // boundary is a separate line layer that can carry real weight.
            var fillAnnotation = PolygonAnnotation(polygon: polygonShape)
            fillAnnotation.fillColor = PolygonStyle.fill

            let fillManager = mapView.annotations.makePolygonAnnotationManager(id: "merchant-polygon")
            fillManager.slot = Self.overlaySlot
            fillManager.annotations = [fillAnnotation]
            polygonManager = fillManager

            // Repeat the first point so the stroke closes the ring.
            var ringCoords = coords
            if let first = coords.first { ringCoords.append(first) }

            var outlineAnnotation = PolylineAnnotation(lineCoordinates: ringCoords)
            outlineAnnotation.lineColor = PolygonStyle.stroke
            outlineAnnotation.lineWidth = PolygonStyle.lineWidth
            outlineAnnotation.lineJoin = .round

            // Created after the fill so the stroke draws on top of it.
            let lineManager = mapView.annotations.makePolylineAnnotationManager(id: "merchant-polygon-outline")
            lineManager.slot = Self.overlaySlot
            lineManager.lineCap = .round
            lineManager.annotations = [outlineAnnotation]
            outlineManager = lineManager
        }
    }
}
