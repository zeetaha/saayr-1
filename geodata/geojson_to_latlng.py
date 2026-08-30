#!/usr/bin/env python3
"""Convert a GeoJSON polygon into a [{"lat": ..., "lng": ...}, ...] list.

GeoJSON stores positions as [lon, lat]; this flips them into the {lat, lng}
objects the app's map code expects.

Usage:
    ./geojson_to_latlng.py king-khalid-airport.geojson
    ./geojson_to_latlng.py in.geojson -o out.json --precision 6
    ./geojson_to_latlng.py in.geojson --keep-closing-point --pretty
"""

import argparse
import json
import sys


def outer_ring(geometry):
    """Return the outer ring of a (Multi)Polygon as a list of [lon, lat]."""
    kind = geometry["type"]
    if kind == "Polygon":
        return geometry["coordinates"][0]
    if kind == "MultiPolygon":
        # Largest part by vertex count — the airport-style datasets put slivers
        # and detached parcels in the remaining polygons.
        return max(geometry["coordinates"], key=lambda poly: len(poly[0]))[0]
    raise ValueError(f"unsupported geometry type: {kind}")


def to_latlng(ring, precision=None, keep_closing_point=False):
    if not keep_closing_point and len(ring) > 1 and ring[0] == ring[-1]:
        ring = ring[:-1]
    points = []
    for lon, lat, *_ in ring:
        if precision is not None:
            lat, lon = round(lat, precision), round(lon, precision)
        point = {"lat": lat, "lng": lon}
        # Rounding can collapse neighbouring vertices onto each other.
        if points and points[-1] == point:
            continue
        points.append(point)
    return points


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("input", help="GeoJSON file (FeatureCollection, Feature, or bare geometry)")
    parser.add_argument("-o", "--output", help="write here instead of stdout")
    parser.add_argument("-i", "--index", type=int, default=0,
                        help="which feature to convert when the file has several (default: 0)")
    parser.add_argument("-p", "--precision", type=int,
                        help="round to this many decimal places (6 ~= 0.1 m)")
    parser.add_argument("--keep-closing-point", action="store_true",
                        help="keep the repeated first==last vertex GeoJSON requires")
    parser.add_argument("--pretty", action="store_true", help="indent the output")
    args = parser.parse_args()

    with open(args.input) as handle:
        data = json.load(handle)

    if data.get("type") == "FeatureCollection":
        features = data["features"]
        if not 0 <= args.index < len(features):
            parser.error(f"--index {args.index} out of range ({len(features)} features)")
        geometry = features[args.index]["geometry"]
    elif data.get("type") == "Feature":
        geometry = data["geometry"]
    else:
        geometry = data

    points = to_latlng(outer_ring(geometry), args.precision, args.keep_closing_point)
    text = json.dumps(points, ensure_ascii=False, indent=2 if args.pretty else None)

    if args.output:
        with open(args.output, "w") as handle:
            handle.write(text + "\n")
        print(f"{len(points)} points -> {args.output}", file=sys.stderr)
    else:
        print(text)


if __name__ == "__main__":
    main()
