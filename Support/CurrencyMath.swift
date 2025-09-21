import Foundation

/// Utilities for performing currency-safe decimal math using bankers rounding.
enum CurrencyMath {
    private static let defaultScale: Int16 = 2
    private static let defaultRounding: NSDecimalNumber.RoundingMode = .bankers

    /// Returns the sum of the provided values rounded to the default currency scale.
    static func sum(_ values: [Decimal], scale: Int16 = defaultScale) -> Decimal {
        values.reduce(into: Decimal.zero) { partialResult, value in
            partialResult = partialResult.currencyAdding(value, scale: scale)
        }
    }

    /// Returns the average of the provided values rounded to the default currency scale.
    static func average(_ values: [Decimal], scale: Int16 = defaultScale) -> Decimal? {
        guard !values.isEmpty else { return nil }
        let total = sum(values, scale: scale)
        return total.currencyDividing(by: Decimal(values.count), scale: scale)
    }

    /// Returns the percentage that `value` represents of `total` rounded to the default scale.
    static func percentage(of value: Decimal, total: Decimal, scale: Int16 = defaultScale) -> Decimal {
        guard total != .zero else { return .zero }
        let ratio = value.currencyDividing(by: total, scale: scale + 2)
        return ratio.currencyMultiplying(by: 100, scale: scale)
    }
}

extension Decimal {
    /// Returns the decimal rounded using bankers rounding to the provided scale.
    func currencyRounded(scale: Int16 = 2, roundingMode: NSDecimalNumber.RoundingMode = .bankers) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, roundingMode)
        return result
    }

    /// Adds another decimal using bankers rounding.
    func currencyAdding(_ value: Decimal, scale: Int16 = 2, roundingMode: NSDecimalNumber.RoundingMode = .bankers) -> Decimal {
        var lhs = self
        var rhs = value
        var result = Decimal()
        NSDecimalAdd(&result, &lhs, &rhs, roundingMode)
        return result.currencyRounded(scale: scale, roundingMode: roundingMode)
    }

    /// Subtracts another decimal using bankers rounding.
    func currencySubtracting(_ value: Decimal, scale: Int16 = 2, roundingMode: NSDecimalNumber.RoundingMode = .bankers) -> Decimal {
        var lhs = self
        var rhs = value
        var result = Decimal()
        NSDecimalSubtract(&result, &lhs, &rhs, roundingMode)
        return result.currencyRounded(scale: scale, roundingMode: roundingMode)
    }

    /// Multiplies with another decimal using bankers rounding.
    func currencyMultiplying(by value: Decimal, scale: Int16 = 2, roundingMode: NSDecimalNumber.RoundingMode = .bankers) -> Decimal {
        var lhs = self
        var rhs = value
        var result = Decimal()
        NSDecimalMultiply(&result, &lhs, &rhs, roundingMode)
        return result.currencyRounded(scale: scale, roundingMode: roundingMode)
    }

    /// Divides by another decimal using bankers rounding.
    func currencyDividing(by value: Decimal, scale: Int16 = 2, roundingMode: NSDecimalNumber.RoundingMode = .bankers) -> Decimal {
        var lhs = self
        var rhs = value
        var result = Decimal()
        NSDecimalDivide(&result, &lhs, &rhs, roundingMode)
        return result.currencyRounded(scale: scale, roundingMode: roundingMode)
    }

    /// Returns the negated value rounded to the default currency scale.
    func currencyNegated(scale: Int16 = 2, roundingMode: NSDecimalNumber.RoundingMode = .bankers) -> Decimal {
        currencyMultiplying(by: -1, scale: scale, roundingMode: roundingMode)
    }
}
