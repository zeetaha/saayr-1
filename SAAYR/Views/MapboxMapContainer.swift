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

    var isCheckingIn: Bool
    var onCameraChanged: (MapboxCameraState) -> Void
    var onTapLocation: (NearbyLocationResponse) -> Void

    typealias UIViewType = MapboxMaps.MapView

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MapboxMaps.MapView {

        let mapView = MapboxMaps.MapView(frame: CGRect.zero)

        mapView.mapboxMap.loadStyle(MapboxMaps.StyleURI.standard)

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

        context.coordinator.syncAnnotations(
            mapView: mapView,
            locations: locations,
            selectedId: selectedLocation?.id
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

        var annotationViews: [Int: UIView] = [:]
        private var lastDigest: Int = -1

        var cameraObserver: Cancelable?

        init(parent: MapboxMapContainer) {
            self.parent = parent
        }

        func syncAnnotations(
            mapView: MapboxMaps.MapView,
            locations: [NearbyLocationResponse],
            selectedId: Int?
        ) {
            let digest = locations.count * 200_003 + (selectedId ?? 0)
            guard digest != lastDigest else { return }
            lastDigest = digest

            for (_, view) in annotationViews {
                mapView.viewAnnotations.remove(view)
            }
            annotationViews.removeAll()

            for location in locations {

                let isActive = location.id == selectedId
                let view = makeAnnotationView(for: location, isActive: isActive)

                annotationViews[location.id] = view

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
            hc.view.tag = location.id

            hc.view.addGestureRecognizer(
                UITapGestureRecognizer(
                    target: self,
                    action: #selector(handleAnnotationTap(_:))
                )
            )

            return hc.view
        }

        @objc private func handleAnnotationTap(_ sender: UITapGestureRecognizer) {
            guard let id = sender.view?.tag,
                  !parent.isCheckingIn,
                  let location = parent.locations.first(where: { $0.id == id })
            else { return }

            parent.onTapLocation(location)
        }
    }
}
