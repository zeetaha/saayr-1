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
    var zones: [Zone]
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
            isArabic: isArabic
        )

        context.coordinator.syncAnnotations(
            mapView: mapView,
            locations: locations,
            selectedKey: selectedLocation?.uniqueKey
        )

        context.coordinator.syncPolygon(
            mapView: mapView,
            polygon: merchantPolygon
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

        // Zone annotation state
        private var zoneFogManager: PolygonAnnotationManager?
        private var zoneFillManager: PolygonAnnotationManager?
        private var zoneOutlineManager: PolylineAnnotationManager?
        private var zoneLockedFillManager: PolygonAnnotationManager?
        private var zoneLockedOutlineManager: PolylineAnnotationManager?
        private var zoneLabelManager: PointAnnotationManager?
        private var currentZonesDigest: Int = -1

        /// Zone boundaries: same green as a merchant, lighter fill because the
        /// areas are far larger. `fog` blacks out everything outside them.
        private enum ZoneStyle {
            static let stroke = StyleColor(red: 21, green: 106, blue: 71, alpha: 1.0)
            static let fill   = StyleColor(red: 21, green: 106, blue: 71, alpha: 0.10)
            /// The rest of the world is blacked out rather than dimmed — only
            /// the zones are available to be viewed. Held just short of opaque
            /// so the major roads still ghost through and the blackout reads as
            /// deliberate rather than as a failed render. This is the knob:
            /// raise towards 1.0 for a harder blackout, lower for more of the
            /// basemap. Keep it well clear of `lockedFill` below so locked
            /// zones stay a distinct shade from out-of-bounds ground.
            static let fog    = StyleColor(red: 8, green: 20, blue: 16, alpha: 0.82)
            static let lineWidth: Double = 2.5

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

        init(parent: MapboxMapContainer) {
            self.parent = parent
        }

        func syncAnnotations(
            mapView: MapboxMaps.MapView,
            locations: [NearbyLocationResponse],
            selectedKey: String?
        ) {
            let digest = locations.map(\.uniqueKey).joined(separator: "|").hashValue ^ (selectedKey?.hashValue ?? 0)
            guard digest != lastDigest else { return }
            lastDigest = digest

            for (_, view) in annotationViews {
                mapView.viewAnnotations.remove(view)
            }
            annotationViews.removeAll()

            for location in locations {

                let isActive = location.uniqueKey == selectedKey
                let view = makeAnnotationView(for: location, isActive: isActive)

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
            isActive: Bool
        ) -> UIView {

            let merchantView = MerchantMarkerView(
                merchant: location.asMerchant,
                isInRange: true,
                isActive: isActive,
                isPartner: location.is_partner
            )

            let hc = UIHostingController(rootView: merchantView)
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

        func syncZones(mapView: MapboxMaps.MapView, zones: [Zone], isArabic: Bool) {
            let digest = (zones
                .map { "\($0.id):\($0.is_unlocked)" }
                .joined(separator: "|") + "|ar:\(isArabic)")
                .hashValue
            guard digest != currentZonesDigest else { return }
            currentZonesDigest = digest

            if zoneFogManager != nil {
                mapView.annotations.removeAnnotationManager(withId: "zones-fog")
                zoneFogManager = nil
            }
            if zoneFillManager != nil {
                mapView.annotations.removeAnnotationManager(withId: "zones-fill")
                zoneFillManager = nil
            }
            if zoneOutlineManager != nil {
                mapView.annotations.removeAnnotationManager(withId: "zones-outline")
                zoneOutlineManager = nil
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

            let unlockedRings = Self.rings(of: zones.filter(\.is_unlocked))
            let lockedRings   = Self.rings(of: zones.filter { !$0.is_unlocked })

            // Created first so every shaded region below draws over the fog.
            installFog(mapView: mapView, zoneRings: unlockedRings + lockedRings)
            installLockedZones(mapView: mapView, rings: lockedRings)

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

            // Outlines are merged so the seams between neighbouring zones
            // aren't drawn — only the outer boundary of the whole group.
            var outlines: [PolylineAnnotation] = []
            for ring in Self.mergedRings(of: unlockedRings) where ring.count >= 2 {
                var outline = PolylineAnnotation(lineCoordinates: ring)
                outline.lineColor = ZoneStyle.stroke
                outline.lineWidth = ZoneStyle.lineWidth
                outline.lineJoin = .round
                outlines.append(outline)
            }

            guard !fills.isEmpty else { return }

            let fillManager = mapView.annotations.makePolygonAnnotationManager(id: "zones-fill")
            fillManager.slot = Self.overlaySlot
            fillManager.annotations = fills
            zoneFillManager = fillManager

            let lineManager = mapView.annotations.makePolylineAnnotationManager(id: "zones-outline")
            lineManager.slot = Self.overlaySlot
            lineManager.lineCap = .round
            lineManager.annotations = outlines
            zoneOutlineManager = lineManager
        }

        /// Boundary rings of `zones`, as map coordinates, dropping any too
        /// degenerate to enclose an area.
        private static func rings(of zones: [Zone]) -> [[CLLocationCoordinate2D]] {
            zones
                .map { zone in
                    zone.boundary_polygon.map {
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
        private func installLockedZones(
            mapView: MapboxMaps.MapView,
            rings: [[CLLocationCoordinate2D]]
        ) {
            guard !rings.isEmpty else { return }

            var fills: [PolygonAnnotation] = []
            var outlines: [PolylineAnnotation] = []
            for coords in rings {
                var fill = PolygonAnnotation(
                    polygon: Polygon(outerRing: Ring(coordinates: coords), innerRings: [])
                )
                fill.fillColor = ZoneStyle.lockedFill
                fills.append(fill)

                // Repeat the first point so the stroke closes the ring.
                var ring = coords
                if let first = coords.first { ring.append(first) }

                var outline = PolylineAnnotation(lineCoordinates: ring)
                outline.lineColor = ZoneStyle.lockedStroke
                outline.lineWidth = ZoneStyle.lockedLineWidth
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
            var labels: [PointAnnotation] = []
            for zone in zones {
                let title = isArabic
                    ? (zone.name_ar.isEmpty ? zone.name : zone.name_ar)
                    : (zone.name.isEmpty ? zone.name_ar : zone.name)
                guard !title.isEmpty, let center = Self.labelCenter(of: zone) else { continue }

                var label = PointAnnotation(id: "zone-label-\(zone.id)", point: Point(center))
                label.textField = title
                label.textColor = zone.is_unlocked ? ZoneStyle.labelColor : ZoneStyle.lockedLabelColor
                label.textHaloColor = zone.is_unlocked ? ZoneStyle.labelHalo : ZoneStyle.lockedLabelHalo
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
