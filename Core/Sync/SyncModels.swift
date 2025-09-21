import Foundation
import CloudKit

enum SyncFeature: String, CaseIterable, Identifiable, Codable, Sendable {
    case core
    case finances
    case merchants
    case transactions
    case inventory
    case shopping
    case habits
    case rules
    case attachments
    case events

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .core:
            return "Profile"
        case .finances:
            return "Accounts"
        case .merchants:
            return "Merchants"
        case .transactions:
            return "Transactions"
        case .inventory:
            return "Inventory"
        case .shopping:
            return "Shopping"
        case .habits:
            return "Habits"
        case .rules:
            return "Rules"
        case .attachments:
            return "Attachments"
        case .events:
            return "Activity Log"
        }
    }

    var systemImageName: String {
        switch self {
        case .core:
            return "person.crop.circle"
        case .finances:
            return "building.columns"
        case .merchants:
            return "building.2"
        case .transactions:
            return "arrow.right.arrow.left"
        case .inventory:
            return "shippingbox"
        case .shopping:
            return "cart"
        case .habits:
            return "repeat"
        case .rules:
            return "switch.2"
        case .attachments:
            return "paperclip"
        case .events:
            return "clock"
        }
    }
}

struct SyncConfiguration: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case featurePermissions
    }

    var isEnabled: Bool
    private var featurePermissions: [SyncFeature: Bool]

    init(isEnabled: Bool = true, featurePermissions: [SyncFeature: Bool] = [:]) {
        self.isEnabled = isEnabled
        var permissions = [SyncFeature: Bool]()
        for feature in SyncFeature.allCases {
            permissions[feature] = featurePermissions[feature] ?? true
        }
        self.featurePermissions = permissions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        let rawPermissions = try container.decodeIfPresent([String: Bool].self, forKey: .featurePermissions) ?? [:]
        var permissions = [SyncFeature: Bool]()
        for feature in SyncFeature.allCases {
            permissions[feature] = rawPermissions[feature.rawValue] ?? true
        }
        self.isEnabled = isEnabled
        self.featurePermissions = permissions
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        let rawPermissions = Dictionary(uniqueKeysWithValues: featurePermissions.map { ($0.key.rawValue, $0.value) })
        try container.encode(rawPermissions, forKey: .featurePermissions)
    }

    func allows(_ feature: SyncFeature) -> Bool {
        featurePermissions[feature, default: true]
    }

    mutating func setFeature(_ feature: SyncFeature, enabled: Bool) {
        featurePermissions[feature] = enabled
    }

    mutating func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }
}

enum SyncStatus: Equatable, Sendable {
    case idle(lastSync: Date?)
    case syncing
    case disabled
    case error(message: String, lastSync: Date?)

    var lastSyncDate: Date? {
        switch self {
        case let .idle(date):
            return date
        case let .error(_, date):
            return date
        case .syncing, .disabled:
            return nil
        }
    }

    var isSyncing: Bool {
        if case .syncing = self { return true }
        return false
    }
}

enum SyncEntity: String, CaseIterable, Identifiable, Codable, Sendable {
    case appUser = "AppUser"
    case account = "Account"
    case merchant = "Merchant"
    case transaction = "Transaction"
    case inventoryItem = "InventoryItem"
    case locationBin = "LocationBin"
    case shoppingList = "ShoppingList"
    case shoppingListLine = "ShoppingListLine"
    case habit = "Habit"
    case taskLink = "TaskLink"
    case calendarLink = "CalendarLink"
    case attachment = "Attachment"
    case budgetEnvelope = "BudgetEnvelope"
    case personLink = "PersonLink"
    case ruleSpec = "RuleSpec"
    case eventRecord = "EventRecord"

    var id: String { rawValue }

    var recordType: String { rawValue }

    var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: "Keystone\(rawValue)", ownerName: CKCurrentUserDefaultName)
    }

    var feature: SyncFeature {
        switch self {
        case .appUser:
            return .core
        case .account:
            return .finances
        case .merchant:
            return .merchants
        case .transaction:
            return .transactions
        case .inventoryItem, .locationBin:
            return .inventory
        case .shoppingList, .shoppingListLine:
            return .shopping
        case .habit, .taskLink, .calendarLink:
            return .habits
        case .attachment:
            return .attachments
        case .budgetEnvelope:
            return .finances
        case .personLink:
            return .core
        case .ruleSpec:
            return .rules
        case .eventRecord:
            return .events
        }
    }
}

struct SyncPayload: Sendable {
    let id: UUID
    let data: Data
    let checksum: String
}

struct SyncRecordMetadata: Codable, Sendable {
    var checksum: String
    var lastSynced: Date
}
