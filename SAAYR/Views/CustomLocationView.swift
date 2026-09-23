//
//  CustomLocationView.swift
//  SAAYR
//
//  Where the allowed tester sets the point the app treats as their location.
//  Only reachable from Profile when `CustomLocation.shared.isAllowed`.
//

import SwiftUI
import CoreLocation

struct CustomLocationView: View {
    @ObservedObject private var custom = CustomLocation.shared
    @Environment(\.dismiss) private var dismiss

    @State private var input = ""
    @State private var inputError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Use custom location", isOn: $custom.isEnabled)
                        .disabled(custom.coordinate == nil)
                } footer: {
                    Text(custom.coordinate == nil
                         ? "Set a point below first."
                         : "While on, the app ignores GPS and places you at this point.")
                }

                Section {
                    TextField("24.6312, 46.7134", text: $input)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("Set location", action: apply)
                        .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("Latitude, longitude")
                } footer: {
                    if let inputError {
                        Text(inputError).foregroundColor(.red)
                    } else {
                        Text("Long-press a spot in Google Maps and paste the coordinates it copies.")
                    }
                }

                if let coordinate = custom.coordinate {
                    Section("Current point") {
                        Text(String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude))
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Custom Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            if let coordinate = custom.coordinate {
                input = String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
            }
        }
    }

    private func apply() {
        let parts = input
            .split(whereSeparator: { $0 == "," || $0 == " " })
            .compactMap { Double($0) }
        guard parts.count == 2,
              (-90...90).contains(parts[0]),
              (-180...180).contains(parts[1]) else {
            inputError = "Enter it as “latitude, longitude”, e.g. 24.6312, 46.7134."
            return
        }
        inputError = nil
        custom.coordinate = CLLocationCoordinate2D(latitude: parts[0], longitude: parts[1])
        custom.isEnabled = true
    }
}
