import Foundation

struct CSVTransactionRecord: Equatable {
    let date: Date
    let description: String
    let amount: Decimal
}

struct CSVInventoryRecord: Equatable {
    let name: String
    let quantity: Decimal
    let unit: String?
    let barcode: String?
}

enum CSVImportError: LocalizedError {
    case invalidHeader(expected: [String], actual: [String])
    case invalidDecimal(String)
    case invalidDate(String)
    case missingField(String)

    var errorDescription: String? {
        switch self {
        case let .invalidHeader(expected, actual):
            return "Invalid CSV header. Expected: \(expected.joined(separator: ", ")), actual: \(actual.joined(separator: ", "))."
        case let .invalidDecimal(value):
            return "Unable to parse decimal value from \(value)."
        case let .invalidDate(value):
            return "Unable to parse date value from \(value)."
        case let .missingField(field):
            return "The field \(field) is required."
        }
    }
}

protocol CSVImportServicing {
    func importTransactions(
        from url: URL,
        dateFormatters: [DateFormatter]
    ) async throws -> [CSVTransactionRecord]

    func importInventory(from url: URL) async throws -> [CSVInventoryRecord]
}

final class CSVImportService: CSVImportServicing {
    private let parser: CSVParser

    init(parser: CSVParser = CSVParser()) {
        self.parser = parser
    }

    func importTransactions(
        from url: URL,
        dateFormatters: [DateFormatter]
    ) async throws -> [CSVTransactionRecord] {
        let rows = try parser.parse(url: url)
        guard let header = rows.first else {
            return []
        }

        let expectedHeader = ["date", "description", "amount"]
        guard header.caseInsensitiveElementsEqual(expectedHeader) else {
            throw CSVImportError.invalidHeader(expected: expectedHeader, actual: header)
        }

        let normalizedHeader = header.map { $0.lowercased() }

        return try rows.dropFirst().map { row in
            let mapped = Dictionary(uniqueKeysWithValues: zip(normalizedHeader, row))

            guard let dateString = mapped["date"], !dateString.isEmpty else {
                throw CSVImportError.missingField("date")
            }

            guard let description = mapped["description"], !description.isEmpty else {
                throw CSVImportError.missingField("description")
            }

            guard let amountString = mapped["amount"], !amountString.isEmpty else {
                throw CSVImportError.missingField("amount")
            }

            guard let amount = DecimalFormatter.decimal(from: amountString) else {
                throw CSVImportError.invalidDecimal(amountString)
            }

            guard let date = dateFormatters.firstNonNil({ $0.date(from: dateString) }) else {
                throw CSVImportError.invalidDate(dateString)
            }

            return CSVTransactionRecord(date: date, description: description, amount: amount)
        }
    }

    func importInventory(from url: URL) async throws -> [CSVInventoryRecord] {
        let rows = try parser.parse(url: url)
        guard let header = rows.first else {
            return []
        }

        let expectedHeader = ["name", "quantity", "unit", "barcode"]
        guard header.caseInsensitiveElementsEqual(expectedHeader) else {
            throw CSVImportError.invalidHeader(expected: expectedHeader, actual: header)
        }

        let normalizedHeader = header.map { $0.lowercased() }

        return try rows.dropFirst().map { row in
            let mapped = Dictionary(uniqueKeysWithValues: zip(normalizedHeader, row))

            guard let name = mapped["name"], !name.isEmpty else {
                throw CSVImportError.missingField("name")
            }

            guard let quantityString = mapped["quantity"], !quantityString.isEmpty else {
                throw CSVImportError.missingField("quantity")
            }

            guard let quantity = DecimalFormatter.decimal(from: quantityString) else {
                throw CSVImportError.invalidDecimal(quantityString)
            }

            let unit = mapped["unit"].flatMap { $0.isEmpty ? nil : $0 }
            let barcode = mapped["barcode"].flatMap { $0.isEmpty ? nil : $0 }

            return CSVInventoryRecord(name: name, quantity: quantity, unit: unit, barcode: barcode)
        }
    }
}

final class CSVParser {
    private let delimiter: Character

    init(delimiter: Character = ",") {
        self.delimiter = delimiter
    }

    func parse(url: URL) throws -> [[String]] {
        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return parse(string: content)
    }

    func parse(string: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var isInsideQuotes = false
        var previousCharacter: Character?
        let characters = Array(string)
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if character == "\"" {
                if isInsideQuotes,
                   index + 1 < characters.count,
                   characters[index + 1] == "\"" {
                    currentField.append("\"")
                    index += 2
                    previousCharacter = "\""
                    continue
                } else {
                    isInsideQuotes.toggle()
                    index += 1
                    previousCharacter = character
                    continue
                }
            }

            if character == delimiter && !isInsideQuotes {
                currentRow.append(currentField)
                currentField = ""
                index += 1
                previousCharacter = character
                continue
            }

            if character.isNewline && !isInsideQuotes {
                if !(previousCharacter == "\r" && character == "\n") {
                    currentRow.append(currentField)
                    rows.append(currentRow)
                    currentRow = []
                }
                currentField = ""
                index += 1
                previousCharacter = character
                continue
            }

            currentField.append(character)
            index += 1
            previousCharacter = character
        }

        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            rows.append(currentRow)
        }

        return rows
    }
}

private enum DecimalFormatter {
    static func decimal(from string: String) -> Decimal? {
        let allowedCharacters = CharacterSet(charactersIn: "0123456789.,-")
        let filteredScalars = string.unicodeScalars.filter { allowedCharacters.contains($0) }
        var sanitized = String(String.UnicodeScalarView(filteredScalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else { return nil }

        if sanitized.contains(",") && !sanitized.contains(".") {
            sanitized = sanitized.replacingOccurrences(of: ".", with: "")
            sanitized = sanitized.replacingOccurrences(of: ",", with: ".")
        } else {
            sanitized = sanitized.replacingOccurrences(of: ",", with: "")
        }

        return Decimal(string: sanitized)
    }
}

private extension Array where Element == String {
    func caseInsensitiveElementsEqual(_ other: [String]) -> Bool {
        guard count == other.count else { return false }
        for (lhs, rhs) in zip(self, other) {
            if lhs.lowercased() != rhs.lowercased() {
                return false
            }
        }
        return true
    }
}

private extension Array {
    func firstNonNil<T>(_ transform: (Element) -> T?) -> T? {
        for element in self {
            if let value = transform(element) {
                return value
            }
        }
        return nil
    }
}
