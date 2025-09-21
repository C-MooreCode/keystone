import Foundation

/// Tracks inventory operations to guarantee idempotent execution for side-effecting commands.
/// The tracker stores opaque identifiers provided by the caller and will only allow
/// each identifier to be observed once per operation category.
public struct InventoryOperationTracker {
    private var adjustmentTokens: Set<UUID> = []
    private var mergeTokens: Set<UUID> = []

    public init() {}

    /// Returns `true` if the adjustment identified by `id` has not yet been recorded.
    /// When the method returns `true` the caller should proceed with the adjustment.
    /// When it returns `false` the adjustment has already been performed.
    @discardableResult
    public mutating func markAdjustment(id: UUID) -> Bool {
        adjustmentTokens.insert(id).inserted
    }

    /// Returns `true` if the merge identified by `id` has not yet been recorded.
    /// When the method returns `true` the caller should proceed with the merge.
    /// When it returns `false` the merge has already been performed.
    @discardableResult
    public mutating func markMerge(id: UUID) -> Bool {
        mergeTokens.insert(id).inserted
    }

    /// Clears the tracked state so new adjustments and merges can be processed again.
    public mutating func reset() {
        adjustmentTokens.removeAll(keepingCapacity: true)
        mergeTokens.removeAll(keepingCapacity: true)
    }
}
