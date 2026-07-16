//
//  Redemption.swift
//  SAAYR
//
//  Created by Awais Raza on 05/07/2026.
//

import Foundation

struct MyRedemptionsResponse: Codable {
    let redemptions: [Redemption]
    let total: Int
    let page: Int
    let pageSize: Int
    let totalPages: Int
    
    enum CodingKeys: String, CodingKey {
        case redemptions
        case total
        case page
        case pageSize = "page_size"
        case totalPages = "total_pages"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        redemptions = try container.decodeIfPresent([Redemption].self, forKey: .redemptions) ?? []
        total = try container.decodeIfPresent(Int.self, forKey: .total) ?? 0
        page = try container.decodeIfPresent(Int.self, forKey: .page) ?? 0
        pageSize = try container.decodeIfPresent(Int.self, forKey: .pageSize) ?? 0
        totalPages = try container.decodeIfPresent(Int.self, forKey: .totalPages) ?? 0
    }
}

struct Redemption: Codable, Identifiable {
    let id: Int
    let rewardId: Int?
    let rewardTitle: String?
    let rewardType: String?
    let merchantName: String?
    let xpSpent: Int?
    let redemptionCode: String?
    let status: String?
    let claimedAt: String?
    let redeemedAt: String?
    let redemptionInstructions: String?
    let imageUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case rewardId = "reward_id"
        case rewardTitle = "reward_title"
        case rewardType = "reward_type"
        case merchantName = "merchant_name"
        case xpSpent = "xp_spent"
        case redemptionCode = "redemption_code"
        case status
        case claimedAt = "claimed_at"
        case redeemedAt = "redeemed_at"
        case redemptionInstructions = "redemption_instructions"
        case imageUrl = "image_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int.self, forKey: .id) ?? 0
        rewardId = try container.decodeIfPresent(Int.self, forKey: .rewardId)
        rewardTitle = try container.decodeIfPresent(String.self, forKey: .rewardTitle)
        rewardType = try container.decodeIfPresent(String.self, forKey: .rewardType)
        merchantName = try container.decodeIfPresent(String.self, forKey: .merchantName)
        xpSpent = try container.decodeIfPresent(Int.self, forKey: .xpSpent)
        redemptionCode = try container.decodeIfPresent(String.self, forKey: .redemptionCode)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        claimedAt = try container.decodeIfPresent(String.self, forKey: .claimedAt)
        redeemedAt = try container.decodeIfPresent(String.self, forKey: .redeemedAt)
        redemptionInstructions = try container.decodeIfPresent(String.self, forKey: .redemptionInstructions)
        imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
    }
}
