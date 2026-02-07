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
        }, to: endpoint, headers: getHeader())
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
    
    func getHeader()-> HTTPHeaders{
        var headers: HTTPHeaders = [
                "Content-Type": "application/json", // or "application/x-www-form-urlencoded" depending on your needs
                "Cache-Control": "no-cache",
                "accept": "application/json"
            ]
            
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
