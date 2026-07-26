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

    @Binding var locations: [NearbyLocationResponse]
    @Binding var selectedLocation: NearbyLocationResponse?
    @Binding var focusOn: MapCameraFocus?

    var merchantPolygon: [PolygonPoint]?
    var zones: [Zone]
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
        mapView.mapboxMap.setCamera(
            to: CameraOptions(
                zoom: 15,
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
        context.coordinator.syncZones(mapView: mapView, zones: zones)

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
        private var zoneFillManager: PolygonAnnotationManager?
        private var zoneOutlineManager: PolylineAnnotationManager?
        private var currentZonesDigest: Int = -1

        /// Zone boundaries: same green as a merchant, lighter fill because the
        /// areas are far larger.
        private enum ZoneStyle {
            static let stroke = StyleColor(red: 21, green: 106, blue: 71, alpha: 1.0)
            static let fill   = StyleColor(red: 21, green: 106, blue: 71, alpha: 0.10)
            static let lineWidth: Double = 2.5
        }

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

                let options = ViewAnnotationOptions(
                    geometry: point,
                    allowOverlap: false,
                    anchor: .center
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

        func syncZones(mapView: MapboxMaps.MapView, zones: [Zone]) {
            let digest = zones
                .map { "\($0.id):\($0.is_unlocked)" }
                .joined(separator: "|")
                .hashValue
            guard digest != currentZonesDigest else { return }
            currentZonesDigest = digest

            if zoneFillManager != nil {
                mapView.annotations.removeAnnotationManager(withId: "zones-fill")
                zoneFillManager = nil
            }
            if zoneOutlineManager != nil {
                mapView.annotations.removeAnnotationManager(withId: "zones-outline")
                zoneOutlineManager = nil
            }

            let unlocked = zones.filter(\.is_unlocked)
            guard !unlocked.isEmpty else { return }

            let rings = unlocked
                .map { zone in
                    zone.boundary_polygon.map {
                        CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng)
                    }
                }
                .filter { $0.count >= 3 }

            // Fills abut without overlapping, so drawing them per zone already
            // reads as one shape.
            var fills: [PolygonAnnotation] = []
            for coords in rings {
                let shape = Polygon(outerRing: Ring(coordinates: coords), innerRings: [])
                var fill = PolygonAnnotation(polygon: shape)
                fill.fillColor = ZoneStyle.fill
                fills.append(fill)
            }

            // Outlines are merged so the seams between neighbouring zones
            // aren't drawn — only the outer boundary of the whole group.
            let (boxes, others) = ZoneBoundaryMerger.partition(rings)
            var outlineRings = ZoneBoundaryMerger.unionRings(of: boxes)
            outlineRings += others.map { ring in
                ring + (ring.first.map { [$0] } ?? [])
            }

            var outlines: [PolylineAnnotation] = []
            for ring in outlineRings where ring.count >= 2 {
                var outline = PolylineAnnotation(lineCoordinates: ring)
                outline.lineColor = ZoneStyle.stroke
                outline.lineWidth = ZoneStyle.lineWidth
                outline.lineJoin = .round
                outlines.append(outline)
            }

            guard !fills.isEmpty else { return }

            let fillManager = mapView.annotations.makePolygonAnnotationManager(id: "zones-fill")
            fillManager.annotations = fills
            zoneFillManager = fillManager

            let lineManager = mapView.annotations.makePolylineAnnotationManager(id: "zones-outline")
            lineManager.lineCap = .round
            lineManager.annotations = outlines
            zoneOutlineManager = lineManager
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
            lineManager.lineCap = .round
            lineManager.annotations = [outlineAnnotation]
            outlineManager = lineManager
        }
    }
}
