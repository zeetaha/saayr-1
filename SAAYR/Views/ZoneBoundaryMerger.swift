//
//  ZoneBoundaryMerger.swift
//  SAAYR
//
//  Merges neighbouring zone rectangles into a single outer boundary so the
//  shared edges between adjacent zones aren't drawn.
//

import Foundation
import CoreLocation

enum ZoneBoundaryMerger {

    struct BoundingBox {
        let minLat: Double
        let maxLat: Double
        let minLng: Double
        let maxLng: Double
    }

    /// Splits rings into axis-aligned boxes (which can be unioned exactly) and
    /// anything else, which the caller should draw on its own.
    static func partition(
        _ rings: [[CLLocationCoordinate2D]]
    ) -> (boxes: [BoundingBox], others: [[CLLocationCoordinate2D]]) {

        var boxes: [BoundingBox] = []
        var others: [[CLLocationCoordinate2D]] = []

        for ring in rings {
            if let box = boundingBox(of: ring) {
                boxes.append(box)
            } else {
                others.append(ring)
            }
        }
        return (boxes, others)
    }

    /// A rectangle is four corners — optionally repeating the first — with
    /// exactly two distinct latitudes and two distinct longitudes.
    private static func boundingBox(of ring: [CLLocationCoordinate2D]) -> BoundingBox? {
        var points = ring
        if points.count > 1,
           let first = points.first, let last = points.last,
           first.latitude == last.latitude, first.longitude == last.longitude {
            points.removeLast()
        }
        guard points.count == 4 else { return nil }

        let lats = Set(points.map(\.latitude))
        let lngs = Set(points.map(\.longitude))
        guard lats.count == 2, lngs.count == 2,
              let minLat = lats.min(), let maxLat = lats.max(),
              let minLng = lngs.min(), let maxLng = lngs.max()
        else { return nil }

        return BoundingBox(minLat: minLat, maxLat: maxLat, minLng: minLng, maxLng: maxLng)
    }

    /// Closed boundary rings of the union of `boxes`, with interior edges dropped.
    ///
    /// Works by slicing the boxes into a grid on every distinct edge coordinate,
    /// marking which cells are covered, then keeping only the cell edges that
    /// separate a covered cell from an uncovered one.
    static func unionRings(of boxes: [BoundingBox]) -> [[CLLocationCoordinate2D]] {
        guard !boxes.isEmpty else { return [] }

        let xs = Set(boxes.flatMap { [$0.minLng, $0.maxLng] }).sorted()
        let ys = Set(boxes.flatMap { [$0.minLat, $0.maxLat] }).sorted()
        guard xs.count >= 2, ys.count >= 2 else { return [] }

        let columns = xs.count - 1
        let rows = ys.count - 1

        var covered = Array(
            repeating: Array(repeating: false, count: rows),
            count: columns
        )
        for i in 0..<columns {
            let centreLng = (xs[i] + xs[i + 1]) / 2
            for j in 0..<rows {
                let centreLat = (ys[j] + ys[j + 1]) / 2
                covered[i][j] = boxes.contains {
                    centreLng > $0.minLng && centreLng < $0.maxLng &&
                    centreLat > $0.minLat && centreLat < $0.maxLat
                }
            }
        }

        var segments: [(CLLocationCoordinate2D, CLLocationCoordinate2D)] = []
        for i in 0..<columns {
            for j in 0..<rows where covered[i][j] {
                let left = xs[i], right = xs[i + 1]
                let bottom = ys[j], top = ys[j + 1]

                if i == 0 || !covered[i - 1][j] {
                    segments.append((point(bottom, left), point(top, left)))
                }
                if i == columns - 1 || !covered[i + 1][j] {
                    segments.append((point(bottom, right), point(top, right)))
                }
                if j == 0 || !covered[i][j - 1] {
                    segments.append((point(bottom, left), point(bottom, right)))
                }
                if j == rows - 1 || !covered[i][j + 1] {
                    segments.append((point(top, left), point(top, right)))
                }
            }
        }

        return stitch(segments)
    }

    // MARK: - Helpers

    private static func point(_ lat: Double, _ lng: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    private static func key(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.9f,%.9f", coordinate.latitude, coordinate.longitude)
    }

    /// Walks the loose boundary segments into closed rings.
    private static func stitch(
        _ segments: [(CLLocationCoordinate2D, CLLocationCoordinate2D)]
    ) -> [[CLLocationCoordinate2D]] {

        guard !segments.isEmpty else { return [] }

        var adjacency: [String: [Int]] = [:]
        for (index, segment) in segments.enumerated() {
            adjacency[key(segment.0), default: []].append(index)
            adjacency[key(segment.1), default: []].append(index)
        }

        var used = Array(repeating: false, count: segments.count)
        var rings: [[CLLocationCoordinate2D]] = []

        for start in segments.indices where !used[start] {
            var ring: [CLLocationCoordinate2D] = []
            var current = start
            var cursor = segments[start].0
            let origin = cursor

            while true {
                used[current] = true
                ring.append(cursor)

                let segment = segments[current]
                cursor = key(segment.0) == key(cursor) ? segment.1 : segment.0

                if key(cursor) == key(origin) { break }
                guard let next = adjacency[key(cursor)]?.first(where: { !used[$0] }) else { break }
                current = next
            }

            if ring.count >= 3 {
                ring.append(origin)   // close the loop
                rings.append(ring)
            }
        }

        return rings
    }
}
