import Foundation

struct SyncSnapshotAdapter {
    let entity: SyncEntity
    let feature: SyncFeature
    let fetchLocal: @MainActor (PersistenceController) throws -> [SyncPayload]
    let applyRemote: @MainActor (PersistenceController, SyncPayload) throws -> Void
    let deleteLocal: @MainActor (PersistenceController, UUID) throws -> Void
}

extension SyncSnapshotAdapter {
    static let all: [SyncEntity: SyncSnapshotAdapter] = {
        var adapters: [SyncEntity: SyncSnapshotAdapter] = [:]

        adapters[.appUser] = SyncSnapshotAdapter(
            entity: .appUser,
            feature: .core,
            fetchLocal: { persistence in
                let models = try persistence.appUsers.fetch()
                return try models.map { model in
                    let snapshot = AppUserSnapshot(model: model)
                    let data = try JSONEncoder().encode(snapshot)
                    return SyncPayload(id: snapshot.identifier, data: data, checksum: syncChecksum(for: data))
                }
            },
            applyRemote: { persistence, payload in
                let snapshot = try JSONDecoder().decode(AppUserSnapshot.self, from: payload.data)
                if let existing = try persistence.appUsers.first(where: #Predicate { $0.identifier == snapshot.identifier }) {
                    snapshot.apply(to: existing)
                    try persistence.save()
                } else {
                    let user = snapshot.makeModel()
                    persistence.mainContext.insert(user)
                    try persistence.save()
                }
            },
            deleteLocal: { persistence, identifier in
                _ = try persistence.appUsers.delete(predicate: #Predicate { $0.identifier == identifier })
            }
        )

        adapters[.account] = SyncSnapshotAdapter(
            entity: .account,
            feature: .finances,
            fetchLocal: { persistence in
                let models = try persistence.accounts.fetch()
                return try models.map { model in
                    let snapshot = AccountSnapshot(model: model)
                    let data = try JSONEncoder().encode(snapshot)
                    return SyncPayload(id: snapshot.id, data: data, checksum: syncChecksum(for: data))
                }
            },
            applyRemote: { persistence, payload in
                let snapshot = try JSONDecoder().decode(AccountSnapshot.self, from: payload.data)
                if let existing = try persistence.accounts.first(where: #Predicate { $0.id == snapshot.id }) {
                    snapshot.apply(to: existing)
                    try persistence.save()
                } else {
                    let account = try snapshot.makeModel()
                    try persistence.accounts.insert(account)
                }
            },
            deleteLocal: { persistence, identifier in
                _ = try persistence.accounts.delete(predicate: #Predicate { $0.id == identifier })
            }
        )

        adapters[.merchant] = SyncSnapshotAdapter(
            entity: .merchant,
            feature: .merchants,
            fetchLocal: { persistence in
                let models = try persistence.merchants.fetch()
                return try models.map { model in
                    let snapshot = MerchantSnapshot(model: model)
                    let data = try JSONEncoder().encode(snapshot)
                    return SyncPayload(id: snapshot.id, data: data, checksum: syncChecksum(for: data))
                }
            },
            applyRemote: { persistence, payload in
                let snapshot = try JSONDecoder().decode(MerchantSnapshot.self, from: payload.data)
                if let existing = try persistence.merchants.first(where: #Predicate { $0.id == snapshot.id }) {
                    snapshot.apply(to: existing)
                    try persistence.save()
                } else {
                    let merchant = try snapshot.makeModel()
                    try persistence.merchants.insert(merchant)
                }
            },
            deleteLocal: { persistence, identifier in
                _ = try persistence.merchants.delete(predicate: #Predicate { $0.id == identifier })
            }
        )

        adapters[.transaction] = SyncSnapshotAdapter(
            entity: .transaction,
            feature: .transactions,
            fetchLocal: { persistence in
                let models = try persistence.transactions.fetch()
                return try models.map { model in
                    let snapshot = TransactionSnapshot(model: model)
                    let data = try JSONEncoder().encode(snapshot)
                    return SyncPayload(id: snapshot.id, data: data, checksum: syncChecksum(for: data))
                }
            },
            applyRemote: { persistence, payload in
                let snapshot = try JSONDecoder().decode(TransactionSnapshot.self, from: payload.data)
                if let existing = try persistence.transactions.first(where: #Predicate { $0.id == snapshot.id }) {
                    snapshot.apply(to: existing)
                    try persistence.save()
                } else {
                    let transaction = try snapshot.makeModel()
                    try persistence.transactions.insert(transaction)
                }
            },
            deleteLocal: { persistence, identifier in
                _ = try persistence.transactions.delete(predicate: #Predicate { $0.id == identifier })
            }
        )

        adapters[.inventoryItem] = SyncSnapshotAdapter(
            entity: .inventoryItem,
            feature: .inventory,
            fetchLocal: { persistence in
                let models = try persistence.inventoryItems.fetch()
                return try models.map { model in
                    let snapshot = InventoryItemSnapshot(model: model)
                    let data = try JSONEncoder().encode(snapshot)
                    return SyncPayload(id: snapshot.id, data: data, checksum: syncChecksum(for: data))
                }
            },
            applyRemote: { persistence, payload in
                let snapshot = try JSONDecoder().decode(InventoryItemSnapshot.self, from: payload.data)
                if let existing = try persistence.inventoryItems.first(where: #Predicate { $0.id == snapshot.id }) {
                    snapshot.apply(to: existing)
                    try persistence.save()
                } else {
                    let item = try snapshot.makeModel()
                    try persistence.inventoryItems.insert(item)
                }
            },
            deleteLocal: { persistence, identifier in
                _ = try persistence.inventoryItems.delete(predicate: #Predicate { $0.id == identifier })
            }
        )

        adapters[.locationBin] = SyncSnapshotAdapter(
            entity: .locationBin,
            feature: .inventory,
            fetchLocal: { persistence in
                let models = try persistence.locationBins.fetch()
                return try models.map { model in
                    let snapshot = LocationBinSnapshot(model: model)
                    let data = try JSONEncoder().encode(snapshot)
                    return SyncPayload(id: snapshot.id, data: data, checksum: syncChecksum(for: data))
                }
            },
            applyRemote: { persistence, payload in
                let snapshot = try JSONDecoder().decode(LocationBinSnapshot.self, from: payload.data)
                if let existing = try persistence.locationBins.first(where: #Predicate { $0.id == snapshot.id }) {
                    snapshot.apply(to: existing)
                    try persistence.save()
                } else {
                    let location = try snapshot.makeModel()
                    try persistence.locationBins.insert(location)
                }
            },
            deleteLocal: { persistence, identifier in
                _ = try persistence.locationBins.delete(predicate: #Predicate { $0.id == identifier })
            }
        )

        adapters[.shoppingList] = SyncSnapshotAdapter(
            entity: .shoppingList,
            feature: .shopping,
            fetchLocal: { persistence in
                let models = try persistence.shoppingLists.fetch()
                return try models.map { model in
                    let snapshot = ShoppingListSnapshot(model: model)
                    let data = try JSONEncoder().encode(snapshot)
                    return SyncPayload(id: snapshot.id, data: data, checksum: syncChecksum(for: data))
                }
            },
            applyRemote: { persistence, payload in
                let snapshot = try JSONDecoder().decode(ShoppingListSnapshot.self, from: payload.data)
                if let existing = try persistence.shoppingLists.first(where: #Predicate { $0.id == snapshot.id }) {
                    snapshot.apply(to: existing)
                    try persistence.save()
                } else {
                    let list = try snapshot.makeModel()
                    try persistence.shoppingLists.insert(list)
                }
            },
            deleteLocal: { persistence, identifier in
                _ = try persistence.shoppingLists.delete(predicate: #Predicate { $0.id == identifier })
            }
        )

        adapters[.shoppingListLine] = SyncSnapshotAdapter(
            entity: .shoppingListLine,
            feature: .shopping,
            fetchLocal: { persistence in
                let models = try persistence.shoppingListLines.fetch()
                return try models.map { model in
                    let snapshot = ShoppingListLineSnapshot(model: model)
                    let data = try JSONEncoder().encode(snapshot)
                    return SyncPayload(id: snapshot.id, data: data, checksum: syncChecksum(for: data))
                }
            },
            applyRemote: { persistence, payload in
                let snapshot = try JSONDecoder().decode(ShoppingListLineSnapshot.self, from: payload.data)
                let list: ShoppingList?
                if let listId = snapshot.listId {
                    list = try persistence.shoppingLists.first(where: #Predicate { $0.id == listId })
                } else {
                    list = nil
                }
                if let existing = try persistence.shoppingListLines.first(where: #Predicate { $0.id == snapshot.id }) {
                    snapshot.apply(to: existing, list: list)
                    try persistence.save()
                } else {
                    let line = try snapshot.makeModel(list: list)
                    try persistence.shoppingListLines.insert(line)
                }
            },
            deleteLocal: { persistence, identifier in
                _ = try persistence.shoppingListLines.delete(predicate: #Predicate { $0.id == identifier })
            }
        )

        adapters[.habit] = SyncSnapshotAdapter(
            entity: .habit,
            feature: .habits,
            fetchLocal: { persistence in
                let models = try persistence.habits.fetch()
                return try models.map { model in
                    let snapshot = HabitSnapshot(model: model)
                    let data = try JSONEncoder().encode(snapshot)
                    return SyncPayload(id: snapshot.id, data: data, checksum: syncChecksum(for: data))
                }
            },
            applyRemote: { persistence, payload in
                let snapshot = try JSONDecoder().decode(HabitSnapshot.self, from: payload.data)
                if let existing = try persistence.habits.first(where: #Predicate { $0.id == snapshot.id }) {
                    snapshot.apply(to: existing)
                    try persistence.save()
                } else {
                    let habit = try snapshot.makeModel()
                    try persistence.habits.insert(habit)
                }
            },
            deleteLocal: { persistence, identifier in
                _ = try persistence.habits.delete(predicate: #Predicate { $0.id == identifier })
            }
        )

        adapters[.taskLink] = SyncSnapshotAdapter(
            entity: .taskLink,
            feature: .habits,
            fetchLocal: { persistence in
                let models = try persistence.taskLinks.fetch()
                return try models.map { model in
                    let snapshot = TaskLinkSnapshot(model: model)
                    let data = try JSONEncoder().encode(snapshot)
                    return SyncPayload(id: snapshot.id, data: data, checksum: syncChecksum(for: data))
                }
            },
            applyRemote: { persistence, payload in
                let snapshot = try JSONDecoder().decode(TaskLinkSnapshot.self, from: payload.data)
                if let existing = try persistence.taskLinks.first(where: #Predicate { $0.id == snapshot.id }) {
                    snapshot.apply(to: existing)
                    try persistence.save()
                } else {
                    let link = try snapshot.makeModel()
                    try persistence.taskLinks.insert(link)
                }
            },
            deleteLocal: { persistence, identifier in
                _ = try persistence.taskLinks.delete(predicate: #Predicate { $0.id == identifier })
            }
        )

        adapters[.calendarLink] = SyncSnapshotAdapter(
            entity: .calendarLink,
            feature: .habits,
            fetchLocal: { persistence in
                let models = try persistence.calendarLinks.fetch()
                return try models.map { model in
                    let snapshot = CalendarLinkSnapshot(model: model)
                    let data = try JSONEncoder().encode(snapshot)
                    return SyncPayload(id: snapshot.id, data: data, checksum: syncChecksum(for: data))
                }
            },
            applyRemote: { persistence, payload in
                let snapshot = try JSONDecoder().decode(CalendarLinkSnapshot.self, from: payload.data)
                if let existing = try persistence.calendarLinks.first(where: #Predicate { $0.id == snapshot.id }) {
                    snapshot.apply(to: existing)
                    try persistence.save()
                } else {
                    let link = try snapshot.makeModel()
                    try persistence.calendarLinks.insert(link)
                }
            },
            deleteLocal: { persistence, identifier in
                _ = try persistence.calendarLinks.delete(predicate: #Predicate { $0.id == identifier })
            }
        )

        adapters[.attachment] = SyncSnapshotAdapter(
            entity: .attachment,
            feature: .attachments,
            fetchLocal: { persistence in
                let models = try persistence.attachments.fetch()
                return try models.map { model in
                    let snapshot = AttachmentSnapshot(model: model)
                    let data = try JSONEncoder().encode(snapshot)
                    return SyncPayload(id: snapshot.id, data: data, checksum: syncChecksum(for: data))
                }
            },
            applyRemote: { persistence, payload in
                let snapshot = try JSONDecoder().decode(AttachmentSnapshot.self, from: payload.data)
                if let existing = try persistence.attachments.first(where: #Predicate { $0.id == snapshot.id }) {
                    snapshot.apply(to: existing)
                    try persistence.save()
                } else {
                    let attachment = try snapshot.makeModel()
                    try persistence.attachments.insert(attachment)
                }
            },
            deleteLocal: { persistence, identifier in
                _ = try persistence.attachments.delete(predicate: #Predicate { $0.id == identifier })
            }
        )

        adapters[.budgetEnvelope] = SyncSnapshotAdapter(
            entity: .budgetEnvelope,
            feature: .finances,
            fetchLocal: { persistence in
                let models = try persistence.budgetEnvelopes.fetch()
                return try models.map { model in
                    let snapshot = BudgetEnvelopeSnapshot(model: model)
                    let data = try JSONEncoder().encode(snapshot)
                    return SyncPayload(id: snapshot.id, data: data, checksum: syncChecksum(for: data))
                }
            },
            applyRemote: { persistence, payload in
                let snapshot = try JSONDecoder().decode(BudgetEnvelopeSnapshot.self, from: payload.data)
                if let existing = try persistence.budgetEnvelopes.first(where: #Predicate { $0.id == snapshot.id }) {
                    snapshot.apply(to: existing)
                    try persistence.save()
                } else {
                    let envelope = try snapshot.makeModel()
                    try persistence.budgetEnvelopes.insert(envelope)
                }
            },
            deleteLocal: { persistence, identifier in
                _ = try persistence.budgetEnvelopes.delete(predicate: #Predicate { $0.id == identifier })
            }
        )

        adapters[.personLink] = SyncSnapshotAdapter(
            entity: .personLink,
            feature: .core,
            fetchLocal: { persistence in
                let models = try persistence.personLinks.fetch()
                return try models.map { model in
                    let snapshot = PersonLinkSnapshot(model: model)
                    let data = try JSONEncoder().encode(snapshot)
                    return SyncPayload(id: snapshot.id, data: data, checksum: syncChecksum(for: data))
                }
            },
            applyRemote: { persistence, payload in
                let snapshot = try JSONDecoder().decode(PersonLinkSnapshot.self, from: payload.data)
                if let existing = try persistence.personLinks.first(where: #Predicate { $0.id == snapshot.id }) {
                    snapshot.apply(to: existing)
                    try persistence.save()
                } else {
                    let link = try snapshot.makeModel()
                    try persistence.personLinks.insert(link)
                }
            },
            deleteLocal: { persistence, identifier in
                _ = try persistence.personLinks.delete(predicate: #Predicate { $0.id == identifier })
            }
        )

        adapters[.ruleSpec] = SyncSnapshotAdapter(
            entity: .ruleSpec,
            feature: .rules,
            fetchLocal: { persistence in
                let models = try persistence.ruleSpecs.fetch()
                return try models.map { model in
                    let snapshot = RuleSpecSnapshot(model: model)
                    let data = try JSONEncoder().encode(snapshot)
                    return SyncPayload(id: snapshot.id, data: data, checksum: syncChecksum(for: data))
                }
            },
            applyRemote: { persistence, payload in
                let snapshot = try JSONDecoder().decode(RuleSpecSnapshot.self, from: payload.data)
                if let existing = try persistence.ruleSpecs.first(where: #Predicate { $0.id == snapshot.id }) {
                    snapshot.apply(to: existing)
                    try persistence.save()
                } else {
                    let rule = try snapshot.makeModel()
                    try persistence.ruleSpecs.insert(rule)
                }
            },
            deleteLocal: { persistence, identifier in
                _ = try persistence.ruleSpecs.delete(predicate: #Predicate { $0.id == identifier })
            }
        )

        adapters[.eventRecord] = SyncSnapshotAdapter(
            entity: .eventRecord,
            feature: .events,
            fetchLocal: { persistence in
                let models = try persistence.eventRecords.fetch()
                return try models.map { model in
                    let snapshot = EventRecordSnapshot(model: model)
                    let data = try JSONEncoder().encode(snapshot)
                    return SyncPayload(id: snapshot.id, data: data, checksum: syncChecksum(for: data))
                }
            },
            applyRemote: { persistence, payload in
                let snapshot = try JSONDecoder().decode(EventRecordSnapshot.self, from: payload.data)
                if let existing = try persistence.eventRecords.first(where: #Predicate { $0.id == snapshot.id }) {
                    snapshot.apply(to: existing)
                    try persistence.save()
                } else {
                    let record = try snapshot.makeModel()
                    try persistence.eventRecords.insert(record)
                }
            },
            deleteLocal: { persistence, identifier in
                _ = try persistence.eventRecords.delete(predicate: #Predicate { $0.id == identifier })
            }
        )

        return adapters
    }()
}
