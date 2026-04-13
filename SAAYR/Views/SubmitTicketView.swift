//
//  SubmitTicketView.swift
//  SAAYR
//
//  Created by Awais Raza on 08/02/2026.
//

import SwiftUI
import PhotosUI
import Alamofire

struct SubmitTicketView: View {
    @EnvironmentObject var languageManager: LanguageManager
    @Environment(\.dismiss) var dismiss
    @State private var subject: String = ""
    @State private var descriptionText: String = ""
    @State private var selectedImages: [UIImage] = []
    @State private var photosPickerItem: [PhotosPickerItem] = []
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String = ""
    @State private var successMessage: String = ""
    @State private var showSuccessToast: Bool = false
    @State private var showValidation: Bool = false

    private var subjectEmpty: Bool { subject.trimmingCharacters(in: .whitespaces).isEmpty }
    private var descriptionEmpty: Bool { descriptionText.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()
                
                // Success Toast
                if showSuccessToast {
                    VStack {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 20))
                            
                            Text(successMessage)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.green)
                                
                            
                            Spacer()
                        }
                        .padding(12)
                        .background(Color.white.opacity(1))
                        .cornerRadius(12)
                        .padding()
                        
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
                }

                ScrollView {
                    VStack(spacing: 24) {
                        Text("Create Support Ticket")
                            .font(.system(size: 28, weight: .bold))
                            .padding(.top, 20)

                        VStack(alignment: languageManager.currentLanguage == .english ? .leading : .trailing, spacing: 16) {
                            Group {
                                HStack {
                                    Text("Subject")
                                        .font(.system(size: 16, weight: .semibold))
                                    Text("*")
                                        .foregroundColor(.red)
                                        .font(.system(size: 16, weight: .bold))
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    TextField("Brief description of your issue", text: $subject)
                                        .padding()
                                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(UIColor.systemBackground)))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(showValidation && subjectEmpty ? Color.red : Color.gray.opacity(0.2), lineWidth: showValidation && subjectEmpty ? 1.5 : 1)
                                        )
                                    if showValidation && subjectEmpty {
                                        HStack(spacing: 4) {
                                            Image(systemName: "exclamationmark.circle.fill")
                                                .font(.system(size: 12))
                                            Text("Subject is required")
                                                .font(.system(size: 12, weight: .medium))
                                        }
                                        .foregroundColor(.red)
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                    }
                                }

                                HStack {
                                    Text("Description")
                                        .font(.system(size: 16, weight: .semibold))
                                    Text("*")
                                        .foregroundColor(.red)
                                        .font(.system(size: 16, weight: .bold))
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    TextEditor(text: $descriptionText)
                                        .frame(height: 160)
                                        .padding(8)
                                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(UIColor.systemBackground)))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(showValidation && descriptionEmpty ? Color.red : Color.gray.opacity(0.2), lineWidth: showValidation && descriptionEmpty ? 1.5 : 1)
                                        )
                                    if showValidation && descriptionEmpty {
                                        HStack(spacing: 4) {
                                            Image(systemName: "exclamationmark.circle.fill")
                                                .font(.system(size: 12))
                                            Text("Description is required")
                                                .font(.system(size: 12, weight: .medium))
                                        }
                                        .foregroundColor(.red)
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                    }
                                }
                            }

                            Text("Attach Photos (Optional)")
                                .font(.system(size: 16, weight: .semibold))

                            PhotosPicker(
                                selection: $photosPickerItem,
                                maxSelectionCount: 5,
                                matching: .images
                            ) {
                                HStack(spacing: 10) {
                                    Image(systemName: "camera.fill")
                                        .foregroundColor(Color.blue)
                                    Text("Add Photos")
                                        .foregroundColor(Color.blue)
                                        .font(.system(size: 16, weight: .semibold))
                                }
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.blue.opacity(0.25), lineWidth: 2)
                                        .background(Color(UIColor.systemBackground).cornerRadius(12))
                                )
                            }
                            .onChange(of: photosPickerItem) { newItems in
                                loadPhotos(newItems)
                            }

                            Text("You can attach multiple photos to help us understand your issue")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)

                            if !selectedImages.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Selected Photos (\(selectedImages.count))")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.secondary)

                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 12) {
                                            ForEach(selectedImages.indices, id: \.self) { index in
                                                ZStack(alignment: .topTrailing) {
                                                    Image(uiImage: selectedImages[index])
                                                        .resizable()
                                                        .scaledToFill()
                                                        .frame(width: 80, height: 80)
                                                        .cornerRadius(8)
                                                        .clipped()

                                                    Button(action: {
                                                        selectedImages.remove(at: index)
                                                    }) {
                                                        Image(systemName: "xmark.circle.fill")
                                                            .foregroundColor(.white)
                                                            .background(Circle().fill(Color.red))
                                                            .font(.system(size: 18))
                                                    }
                                                    .offset(x: 8, y: -8)
                                                }
                                            }
                                        }
                                        .padding(.vertical, 8)
                                    }
                                }
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color(UIColor.systemBackground)))
                            }

                            HStack(spacing: 12) {
                                Button(action: {
                                    submitTicket()
                                }) {
                                    if isSubmitting {
                                        ProgressView()
                                            .tint(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding()
                                    } else {
                                        Text("Submit Ticket")
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding()
                                    }
                                }
                                .background(
                                    LinearGradient(colors: [Color.purple.opacity(0.8), Color.purple], startPoint: .leading, endPoint: .trailing)
                                )
                                .cornerRadius(12)
                                .disabled(isSubmitting)

                                Button(action: { dismiss() }) {
                                    Text("Cancel")
                                        .foregroundColor(.primary)
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                                                .background(Color(UIColor.systemBackground).cornerRadius(12))
                                        )
                                }
                            }

                            if !errorMessage.isEmpty {
                                Text(errorMessage)
                                    .font(.system(size: 14))
                                    .foregroundColor(.red)
                                    .padding()
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(8)
                            }
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 20).fill(Color(UIColor.secondarySystemBackground)))
                        .padding(.horizontal)

                        Spacer(minLength: 30)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: languageManager.currentLanguage == .english ? "chevron.left" : "chevron.right")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
            }
        }
        .environment(\.layoutDirection, languageManager.currentLanguage == .arabic ? .rightToLeft : .leftToRight)
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) {
        Task {
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    await MainActor.run {
                        if !selectedImages.contains(where: { $0.pngData() == data }) {
                            selectedImages.append(uiImage)
                        }
                    }
                }
            }
        }
    }

    private func submitTicket() {
        showValidation = true
        guard !subject.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Please enter a subject"
            return
        }
        guard !descriptionText.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Please enter a description"
            return
        }

        isSubmitting = true
        errorMessage = ""
        successMessage = ""

        let parameters: [String: Any] = [
            "subject": subject.trimmingCharacters(in: .whitespaces),
            "description": descriptionText.trimmingCharacters(in: .whitespaces)
        ]

        // Use multipart upload if there are images, otherwise regular POST
        if !selectedImages.isEmpty {
            var uploadedUrls: [String] = []
            var uploadErrorMessage: String? = nil
            let group = DispatchGroup()

            for image in selectedImages {
                group.enter()
                ServiceModel.shared.uploadImage(endpoint: WebService.uploadImage, image: image) { result in
                    switch result {
                    case .success(let imageUrl):
                        uploadedUrls.append(imageUrl)
                    case .failure(let error):
                        if uploadErrorMessage == nil {
                            uploadErrorMessage = error.localizedDescription
                        }
                    }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                if let errMsg = uploadErrorMessage {
                    isSubmitting = false
                    errorMessage = "Image upload failed: \(errMsg)"
                    return
                }

                var paramsWithImages = parameters
                paramsWithImages["image_urls"] = uploadedUrls

                ServiceModel.shared.postRequest(endpoint: WebService.createTicket, parameters: paramsWithImages) { result in
                    DispatchQueue.main.async {
                        isSubmitting = false
                        handleSubmitResponse(result)
                    }
                }
            }
        } else {
            ServiceModel.shared.postRequest(
                endpoint: WebService.createTicket,
                parameters: parameters
            ) { result in
                DispatchQueue.main.async {
                    isSubmitting = false
                    handleSubmitResponse(result)
                }
            }
        }
    }

    private func handleSubmitResponse(_ result: Result<Data, AFError>) {
        switch result {
        case .success(let data):
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let success = json["success"] as? Bool ?? false
                    let message = json["message"] as? String ?? "Ticket created successfully"

                    if success {
                        successMessage = message
                        withAnimation {
                            showSuccessToast = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            withAnimation {
                                showSuccessToast = false
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                dismiss()
                            }
                        }
                    } else {
                        errorMessage = message
                    }
                }
            } catch {
                errorMessage = "Failed to process response: \(error.localizedDescription)"
            }

        case .failure(let error):
            errorMessage = error.localizedDescription
            print("❌ API Error:", error.localizedDescription)
        }
    }
}

#Preview {
    SubmitTicketView()
        .environmentObject(LanguageManager())
}
