//
//  ServiceModel.swift
//  lechef
//
//  Created by Awais Raza on 29/09/2024.
//

import Foundation
import Alamofire
import UIKit


class ServiceModel {
    
    // Singleton instance for easy access throughout the app
    static let shared = ServiceModel()
    
    private init() { }
    
    // MARK: - GET Request
    func getRequest(endpoint: String, parameters: [String: Any]? = nil, completion: @escaping (Result<Data, AFError>) -> Void) {
        AF.request(endpoint, method: .get, parameters: parameters, encoding: URLEncoding.default, headers: getHeader())
            .validate()
            .responseData { response in
                switch response.result {
                case .success(let data):
                    completion(.success(data))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
    }
    
    // MARK: - POST Request
    func postRequest(endpoint: String, parameters: [String: Any]? = nil, completion: @escaping (Result<Data, AFError>) -> Void)
    
    {
        AF.request(endpoint, method: .post, parameters: parameters, encoding: JSONEncoding.default, headers: getHeader())
            .validate()
            .responseData { response in
                switch response.result {
                case .success(let data):
                    completion(.success(data))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
    }
    
    // MARK: - DELETE Request
    func deleteRequest(endpoint: String, parameters: [String: Any]? = nil, completion: @escaping (Result<Data, AFError>) -> Void) {
        AF.request(endpoint, method: .delete, parameters: parameters, encoding: JSONEncoding.default, headers: getHeader())
            .validate()
            .responseData { response in
                switch response.result {
                case .success(let data):
                    completion(.success(data))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
    }
    
    // MARK: - PATCH Request
    func patchRequest(endpoint: String, parameters: [String: Any]? = nil, completion: @escaping (Result<Data, AFError>) -> Void) {
        AF.request(endpoint, method: .patch, parameters: parameters, encoding: JSONEncoding.default)
            .validate()
            .responseData { response in
                switch response.result {
                case .success(let data):
                    completion(.success(data))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
    }
    
    // MARK: - PUT Request
       func putRequest(endpoint: String, parameters: [String: Any]? = nil, completion: @escaping (Result<Data, AFError>) -> Void) {
           AF.request(endpoint, method: .put, parameters: parameters, encoding: JSONEncoding.default,headers: getHeader())
               .validate()
               .responseData { response in
                   switch response.result {
                   case .success(let data):
                       completion(.success(data))
                   case .failure(let error):
                       completion(.failure(error))
                   }
               }
       }

    // MARK: - Multipart Form Data POST Request (for file uploads)
    func multipartPostRequest(endpoint: String, parameters: [String: Any]? = nil, images: [UIImage]? = nil, completion: @escaping (Result<Data, AFError>) -> Void) {
        AF.upload(multipartFormData: { multipartFormData in
            // Add text parameters
            if let params = parameters {
                for (key, value) in params {
                    if let stringValue = value as? String {
                        multipartFormData.append(stringValue.data(using: .utf8) ?? Data(), withName: key)
                    } else if let intValue = value as? Int {
                        multipartFormData.append("\(intValue)".data(using: .utf8) ?? Data(), withName: key)
                    }
                }
            }
            
            // Add images
            if let images = images {
                for (index, image) in images.enumerated() {
                    if let jpegData = image.jpegData(compressionQuality: 0.8) {
                        multipartFormData.append(jpegData, withName: "images", fileName: "image_\(index).jpg", mimeType: "image/jpeg")
                    }
                }
            }
        }, to: endpoint, headers: getHeader(forMultipart: true))
            .validate()
            .responseData { response in
                switch response.result {
                case .success(let data):
                    completion(.success(data))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
    }

    // MARK: - Upload Single Image (returns image_url string from server)
    func uploadImage(endpoint: String, image: UIImage, completion: @escaping (Result<String, AFError>) -> Void) {
        // Resize & compress before uploading to avoid large payload (HTTP 413)
        let maxDimension: CGFloat = 1280
        let resized = resizeImage(image: image, maxDimension: maxDimension)
        let compressionQuality: CGFloat = 0.6
        guard let jpegData = resized.jpegData(compressionQuality: compressionQuality) else {
            completion(.failure(AFError.parameterEncodingFailed(reason: .missingURL)))
            return
        }

        AF.upload(multipartFormData: { multipartFormData in
            multipartFormData.append(jpegData, withName: "file", fileName: "image.jpg", mimeType: "image/jpeg")
        }, to: endpoint, headers: getHeader(forMultipart: true))
        .validate()
        .responseData { response in
            switch response.result {
            case .success(let data):
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let dataDict = json["data"] as? [String: Any],
                       let imageUrl = dataDict["image_url"] as? String {
                        completion(.success(imageUrl))
                    } else {
                        completion(.failure(AFError.responseSerializationFailed(reason: .decodingFailed(error: NSError(domain: "ServiceModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid upload response"])))))
                    }
                } catch {
                    completion(.failure(AFError.responseSerializationFailed(reason: .decodingFailed(error: error))))
                }
            case .failure(let error):
                // If payload too large, suggest client-side compression further
                if let code = response.response?.statusCode, code == 413 {
                    completion(.failure(AFError.responseValidationFailed(reason: .unacceptableStatusCode(code: code))))
                } else {
                    completion(.failure(error))
                }
            }
        }
    }

    // Resize image preserving aspect ratio
    private func resizeImage(image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let aspect = size.width / size.height
        var newSize: CGSize
        if size.width > size.height {
            if size.width <= maxDimension { return image }
            newSize = CGSize(width: maxDimension, height: maxDimension / aspect)
        } else {
            if size.height <= maxDimension { return image }
            newSize = CGSize(width: maxDimension * aspect, height: maxDimension)
        }

        UIGraphicsBeginImageContextWithOptions(newSize, false, 0.8)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let newImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        return newImage
    }
    
    // MARK: - Fetch Rewards Catalog
    func fetchRewards(page: Int, pageSize: Int, completion: @escaping (Result<[APIReward], Error>) -> Void) {
        let parameters: [String: Any] = [
            "page": page,
            "page_size": pageSize
        ]
        
        getRequest(endpoint: WebService.rewardsCatalog, parameters: parameters) { result in
            switch result {
            case .success(let data):
                do {
                    let response = try JSONDecoder().decode(RewardsCatalogResponse.self, from: data)
                    completion(.success(response.rewards))
                } catch {
                    completion(.failure(error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Redeem Reward
    func redeemReward(rewardId: Int, completion: @escaping (Result<RedeemResponse, Error>) -> Void) {
        let parameters: [String: Any] = [
            "reward_id": rewardId
        ]
        
        AF.request(
            WebService.redeemReward,
            method: .post,
            parameters: parameters,
            encoding: JSONEncoding.default,
            headers: getHeader()
        )
        .responseData { response in
            print("Redeem Response Status: \(response.response?.statusCode ?? -1)")
            
            switch response.result {
            case .success(let data):
                do {
                    let jsonString = String(data: data, encoding: .utf8) ?? ""
                    print("Redeem Response Data: \(jsonString)")
                    
                    let decodedResponse = try JSONDecoder().decode(RedeemResponse.self, from: data)
                    completion(.success(decodedResponse))
                } catch {
                    print("Redeem Decode Error: \(error)")
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let detail = json["detail"] as? String {
                        let error = NSError(domain: "RedeemError", code: -1, userInfo: [NSLocalizedDescriptionKey: detail])
                        completion(.failure(error))
                    } else {
                        completion(.failure(error))
                    }
                }
            case .failure(let error):
                print("Redeem Request Error: \(error)")
                if let data = response.data {
                    let jsonString = String(data: data, encoding: .utf8) ?? ""
                    print("Error Response: \(jsonString)")
                }
                completion(.failure(error))
            }
        }
    }

    func getHeader(forMultipart: Bool = false)-> HTTPHeaders{
        var headers: HTTPHeaders = [
                "Cache-Control": "no-cache",
                "accept": "application/json"
            ]
        if !forMultipart {
            headers["Content-Type"] = "application/json"
        }
            
            // Add Authorization if needed
        if let token = UserModel.shared.user?.accessToken {
            print(token)
                headers["Authorization"] = "Bearer \(token)"
        }
        headers["Language-Code"] = UserModel.shared.languageCode
        headers["App-Version"] = "1.0.0"
        headers["Latitude"] = UserModel.shared.latitude
        headers["Longitude"] = UserModel.shared.longitude
        headers["Country-Code"] = UserModel.shared.countryCode

            

        return headers
    }
}
