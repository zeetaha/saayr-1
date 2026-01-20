import SwiftUI
import MapKit
import Combine

//struct MapView: View {
//    @State private var region = MKCoordinateRegion(
//        center: CLLocationCoordinate2D(latitude: 24.7136, longitude: 46.6753),
//        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
//    )
//
//    @State private var merchants: [MerchantLocation] = MerchantLocation.demo()
//    @State private var selectedMerchant: MerchantLocation?
//    @State private var isCheckingIn = false
//    @State private var elapsedTime = 0
//    @State private var progress: Double = 0
//
//    let checkInDuration = 120
//    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
//
//    // MARK: Computed
//    var merchantsWithDistanceArray: [MerchantWithDistance] {
//        merchants.enumerated().map { index, merchant in
//            let distance = index < 2 ? 50.0 : Double(index + 1) * 500.0
//            return MerchantWithDistance(merchant: merchant, distance: distance)
//        }
//    }
//
//    var body: some View {
//        ZStack {
//            // MARK: Map
//            Map(coordinateRegion: $region, annotationItems: merchantsWithDistanceArray) { item in
//                MapAnnotation(coordinate: item.merchant.coordinate) {
//                    MerchantMarkerView(
//                        merchant: item.merchant,
//                        isInRange: item.distance <= 100,
//                        isActive: item.merchant.id == selectedMerchant?.id && isCheckingIn
//                    )
//                    .onTapGesture {
//                        withAnimation {
//                            selectedMerchant = item.merchant
//                        }
//                    }
//                }
//            }
//            .ignoresSafeArea()
//
//            // MARK: Top Header
//            VStack {
//                HeaderCard(nearbyCount: merchantsWithDistanceArray.filter { $0.distance <= 100 }.count)
//                Spacer()
//            }
//
//            // MARK: Check-In Progress
//            if isCheckingIn, let merchant = selectedMerchant {
//                CheckInProgressCard(
//                    merchant: merchant,
//                    progress: progress,
//                    remaining: checkInDuration - elapsedTime
//                ) {
//                    resetCheckIn()
//                }
//            }
//
//            // MARK: Bottom Check-In CTA
//            if !isCheckingIn, let merchant = selectedMerchant ?? merchantsWithDistanceArray.first(where: { $0.distance <= 100 })?.merchant {
//                BottomCheckInCard(merchant: merchant) {
//                    startCheckIn(merchant)
//                }
//            }
//        }
//        .onReceive(timer) { _ in
//            guard isCheckingIn else { return }
//
//            elapsedTime += 1
//            progress = Double(elapsedTime) / Double(checkInDuration)
//
//            if elapsedTime >= checkInDuration {
//                completeCheckIn()
//            }
//        }
//    }
//
//    // MARK: Actions
//    private func startCheckIn(_ merchant: MerchantLocation) {
//        withAnimation {
//            selectedMerchant = merchant
//            isCheckingIn = true
//            elapsedTime = 0
//            progress = 0
//        }
//    }
//
//    private func resetCheckIn() {
//        withAnimation {
//            isCheckingIn = false
//            selectedMerchant = nil
//            elapsedTime = 0
//            progress = 0
//        }
//    }
//
//    private func completeCheckIn() {
//        resetCheckIn()
//    }
//}

struct MapView: View {
    
    @StateObject private var locationManager = LocationManager()
    
    @State private var region = MKCoordinateRegion()
    @State private var locations: [NearbyLocationResponse] = []
    @State private var selectedLocation: NearbyLocationResponse?
    
    @State private var lastFetchCenter: CLLocationCoordinate2D?
    
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
    @State private var elapsedTime = 0
    @State private var progress: Double = 0
    let checkInDuration = 10   // example 5 sec for demo; can be 120
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    
    
    var body: some View {
        ZStack {
            
            // MARK: Map
            Map(
                coordinateRegion: $region,
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
                            can_checkin: item.can_checkin
                        ),
                        isInRange: true,
                        isActive: selectedLocation?.id == item.id
                    )
                    .onTapGesture {
                        selectedLocation = item
                    }
                }
            }
            .ignoresSafeArea()
            
            
           
            
            // MARK: HeaderCard - Only show after API response
            if !locations.isEmpty && !showSuccessAlert && !showAlert{
                VStack {
                    HeaderCard(nearbyCount: locations.count)
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
                        coordinate: location.coordinate, can_checkin: location.can_checkin
                    ),
                    progress: progress,
                    remaining: checkInDuration - elapsedTime
                ) {
                    resetCheckIn()
                }
            }
            
            
            
            // MARK: Bottom Check-In
            if !isCheckingIn, let location = selectedLocation{
                BottomCheckInCard(
                    merchant: location.asMerchant
                ) {
                    startCheckIn(location)
                }
            }
            
        }
        .onAppear {
            locationManager.requestPermission()
        }
        .onReceive(locationManager.$location.compactMap { $0 }) { location in
            moveToUser(location)
            fetchNearby(location.coordinate)
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
            span: .init(latitudeDelta: 0.1, longitudeDelta: 0.02)
        )
    }
    
    private func fetchNearby(_ coordinate: CLLocationCoordinate2D) {
        lastFetchCenter = coordinate
        
        LocationAPI.shared.fetchNearby(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        ) { newItems in
            // Prevent duplicate pins
            let existingIDs = Set(locations.map { $0.id })
            let filtered = newItems.filter { !existingIDs.contains($0.id) }
            
            locations.append(contentsOf: filtered)
        }
    }
    
    // MARK: Check-In Actions
    // Start the check-in process (just UI + timer)
    private func startCheckIn(_ location: NearbyLocationResponse) {
        withAnimation {
            selectedLocation = location
            isCheckingIn = true
            elapsedTime = 0
            progress = 0
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
    
    // Called when the timer finishes
    private func completeCheckIn() {
        guard let location = selectedLocation,
              let userLocation = locationManager.location?.coordinate else {
            resetCheckIn()
            return
        }
        
        // ✅ Call API after timer ends
        LocationAPI.shared.checkIn(locationId: location.id, userCoordinate: userLocation) { result in
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
    
    @State private var pulse = false
    
    var body: some View {
        ZStack {
            if isInRange && !isActive {
                Circle()
                    .fill(Color.green.opacity(0.3))
                    .frame(width: 60, height: 60)
                    .scaleEffect(pulse ? 1.6 : 1)
                    .opacity(pulse ? 0 : 0.6)
                    .animation(
                        .easeOut(duration: 2).repeatForever(autoreverses: false),
                        value: pulse
                    )
            }
            
            RoundedRectangle(cornerRadius: 14)
                .fill(isActive ? Color.green : .white)
                .frame(width: 48, height: 48)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isInRange ? Color.green : Color.gray, lineWidth: 3)
                )
                .shadow(radius: 6)
            
            Text(merchant.emoji)
                .font(.system(size: 24))
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
                    Text(merchant.emoji)
                        .font(.largeTitle)
                    
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
    let onCheckIn: () -> Void
    
    var body: some View {
        VStack {
            Spacer()
            
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    // Merchant Emoji
                    Text(merchant.emoji)
                        .font(.system(size: 48))
                    
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
                        Image(systemName: "location.fill")
                        Text("Check In (+\(merchant.xpReward) XP)")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(merchant.can_checkin ? Color.green : Color.gray) // gray if cannot check in
                    .cornerRadius(16)
                }
                .disabled(!merchant.can_checkin) // disables button if cannot check in
                
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
}
extension NearbyLocationResponse {
    var asMerchant: MerchantLocation {
        MerchantLocation(
            id: id,
            name: name,
            category: category,
            emoji: "📍",  // default
            xpReward: xp_reward,
            coordinate: coordinate,
            can_checkin: can_checkin
        )
    }
}


struct MerchantWithDistance: Identifiable {
    let id = UUID()           // Make it Identifiable
    let merchant: MerchantLocation
    let distance: Double
}

#Preview {
    MapView()
        .environmentObject(LanguageManager())
        .environmentObject(UserManager())
}
