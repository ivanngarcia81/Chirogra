import CoreData
import SwiftData
import Testing
@testable import ChirograData

/// Los esquemas 1, 2 y 3 están congelados: SwiftData reconoce los almacenes viejos por el hash de cada entidad, así que
/// si cambian (un nombre, un tipo, una relación, un `@Attribute`…) los libros de quien venga de esa versión no se abren.
/// Estos hashes son los de las versiones publicadas (calculados en `c214680`, 1.0.1 build 15, antes de congelar).
@Suite("Esquemas congelados")
struct FrozenSchemaTests {

    static let hashesV1: [String: String] = [
        "Account": "Q9D1w3Gd3kjCOXJT6EU5WjpKL226y+kJQnbULrW3vME=",
        "Attachment": "i1/4H+w0/pkzM/zv3YUCUdGWVrztLxKB/e9xaT9a+So=",
        "AuditEvent": "R/pIOKGWkHJHIQyPgThaeZVFS4yIJyAF/URfSO0jdqs=",
        "Bill": "+wuXcualy55f36Dk9x7/oMqmZmpZdWH2z5L+c6ePn7g=",
        "BillLine": "DqwRXAEkYmSPMeT+2mqvjvhkxy/ZSeRzpUroC+affSk=",
        "BillPayment": "kPMRtlps31qNxm0SuJwbjRHNYS5ljXf1O5U/ei6ijgk=",
        "Company": "9Ro8ix2DkuCCcHAQnbmE5TQnQSkw9GbnWvwT/Idfz7g=",
        "CreditApplication": "5YcuQkxcmNjQ5Sa3Ft4jMFgZChH5W0Mxm/8qP9abARA=",
        "CreditNote": "1oriVdrNQ2p9W+6lzpNQUOJtaeyy9CfuGOt9uORvmlM=",
        "Customer": "hVaCjtGnmdqVW/cwR85nhXM4Z7snLS/wpLx9MBVpCxw=",
        "Expense": "RamR4LjoaXfCMruz7fguRbMCkRK+3BdYTtxSA7tYFsI=",
        "ExpenseLine": "ufrYl9gqEGkVMHF9y7vTMOOxXasVuouK0RWhKxzw+V0=",
        "Invoice": "9925H/QeT8F6fghBnpimsTYmY4LHOBulrfz4rCXyUHw=",
        "InvoiceLine": "Qvq30rB+AU0nSwGnInQyj8S54sywzL+/9o3164dBMCQ=",
        "InvoiceTaxLine": "ZgSfWuwk4lZhIEulXYW0/FRdjlC6PkKTk6y+mjoiz9k=",
        "Item": "o8Xbb8d6zqOPFn4pyoLxF/9Flf7ilQSGn8IxDQwHijQ=",
        "JournalEntry": "ixmf/+AXcsoO2OLITFo9Lsk/0pn1LGf8iJ5zZvfLIJU=",
        "JournalLine": "m/Adj+uN3eFnAz+nnsY+M2QUjDeWohPN2fz8/z+nX6A=",
        "NumberSequence": "/afCxhL9CB1CibOuDUovJX6SPlr04x3d42DryrheOYE=",
        "PaymentApplication": "SGlzjqJEhV/aypaAx2igiMj0T6GtCZZ6PeTcz9TMQ9Y=",
        "PaymentReceived": "/GzzmD1lLKj+u0TGF3aUwot4kHSENNrrquNf3RSgTJc=",
        "TaxAgency": "y1gt6RbbfmfQ5EDk8LBvkn5arfamI+pJKO6D2lzKYXY=",
        "TaxGroup": "pxWKOhw5+Vpb3BsDqt+77Nq6F5mv/VIVf7aTI22i35A=",
        "TaxRate": "8BEvuV+glxZp0sZJ8PxdJv5D1+Fbn+Y+MzM2l4UbfZs=",
        "Vendor": "DYIQrj5bayHPArmIvANowCoP/5+vOte684ukiyfCLGo=",
    ]

    static let hashesV2: [String: String] = [
        "Account": "PomZGG67AhuQnyuYWxPi+FWH6xoY6ADs/MBX+olo+mw=",
        "Attachment": "10KIHsausLvbiGftE6Pqd5qGicCByvez1ayMpf80g/Q=",
        "AuditEvent": "R/pIOKGWkHJHIQyPgThaeZVFS4yIJyAF/URfSO0jdqs=",
        "Bill": "ueSBqsNdXBNyA4dZ7caHZvG4zo/Zw1rMHPZSTjkrTVo=",
        "BillLine": "DqwRXAEkYmSPMeT+2mqvjvhkxy/ZSeRzpUroC+affSk=",
        "BillPayment": "kPMRtlps31qNxm0SuJwbjRHNYS5ljXf1O5U/ei6ijgk=",
        "Company": "9F28qUBqcVYgXcGeB46aBL1EWfElqjeTJdPuORpgj2U=",
        "CreditApplication": "5YcuQkxcmNjQ5Sa3Ft4jMFgZChH5W0Mxm/8qP9abARA=",
        "CreditNote": "1oriVdrNQ2p9W+6lzpNQUOJtaeyy9CfuGOt9uORvmlM=",
        "Customer": "VXGM2sfyAWp2yKsHfAhf4T5uMy9WZn0OIfVqkicWCjw=",
        "CustomerNote": "+ycOPuAxvSWMIe+bOL//AQB9ORuuT0/JTA9/bPrQiEU=",
        "Estimate": "5pRRPeSikk/g0xe/Jw21NA+deqAgpDAzFnJX7Vyp8Kk=",
        "EstimateLine": "OCO6MLGFD2ridMsDaG3A3nNCDJrJk9w48gPDCex+JUo=",
        "Expense": "SNEIQRgnEDDIDKdjJV4dxeR6r2XkrMx5Y5mkKKyCaRU=",
        "ExpenseLine": "ufrYl9gqEGkVMHF9y7vTMOOxXasVuouK0RWhKxzw+V0=",
        "Invoice": "s0pG7vQZaJar+fTPws7n93td7dEEvkjTHrbGXP5fYHM=",
        "InvoiceEvent": "yGcabZFeDkZNDs7h1R/f7IS11OCHigJhtaF4D9gENxc=",
        "InvoiceLine": "Qvq30rB+AU0nSwGnInQyj8S54sywzL+/9o3164dBMCQ=",
        "InvoiceTaxLine": "ZgSfWuwk4lZhIEulXYW0/FRdjlC6PkKTk6y+mjoiz9k=",
        "Item": "o8Xbb8d6zqOPFn4pyoLxF/9Flf7ilQSGn8IxDQwHijQ=",
        "JournalEntry": "kDOyeErROXOSfQyWU/BHO1kBVSw8SWp7PHCn/fyVq3Y=",
        "JournalLine": "m/Adj+uN3eFnAz+nnsY+M2QUjDeWohPN2fz8/z+nX6A=",
        "NoticeState": "f4zeqAbtwd7KHZ9CBuSpmX2uX9iQ5spWXmE+ayZsqUM=",
        "NumberSequence": "/afCxhL9CB1CibOuDUovJX6SPlr04x3d42DryrheOYE=",
        "PaymentApplication": "SGlzjqJEhV/aypaAx2igiMj0T6GtCZZ6PeTcz9TMQ9Y=",
        "PaymentReceived": "/GzzmD1lLKj+u0TGF3aUwot4kHSENNrrquNf3RSgTJc=",
        "PeriodClose": "koFZnT6xfqGCsBOgevccQvgchEe+2jP0rHja/S29Osw=",
        "RecurringTemplate": "NsfQA/3K/gVWj/sL9lJWlChA42X0KD+o/DNxOuLvwrI=",
        "RecurringTemplateLine": "yBHgbCd176pnRU6T6fgZ8WjUpVsIqKwuAbEsIGczv2Q=",
        "TaxAgency": "y1gt6RbbfmfQ5EDk8LBvkn5arfamI+pJKO6D2lzKYXY=",
        "TaxGroup": "pxWKOhw5+Vpb3BsDqt+77Nq6F5mv/VIVf7aTI22i35A=",
        "TaxRate": "8BEvuV+glxZp0sZJ8PxdJv5D1+Fbn+Y+MzM2l4UbfZs=",
        "Vendor": "1QtKRVhNgKWM/ztsLdKrC6p5WH4AaWsP6FcMkzPdewY=",
    ]

    static let hashesV3: [String: String] = [
        "Account": "PomZGG67AhuQnyuYWxPi+FWH6xoY6ADs/MBX+olo+mw=",
        "Attachment": "10KIHsausLvbiGftE6Pqd5qGicCByvez1ayMpf80g/Q=",
        "AuditEvent": "2TVp5LCyD8YkNdQ2RbEeTAmcmuSJaKFCEeZpS4aCzsc=",
        "Bill": "ueSBqsNdXBNyA4dZ7caHZvG4zo/Zw1rMHPZSTjkrTVo=",
        "BillLine": "DqwRXAEkYmSPMeT+2mqvjvhkxy/ZSeRzpUroC+affSk=",
        "BillPayment": "kPMRtlps31qNxm0SuJwbjRHNYS5ljXf1O5U/ei6ijgk=",
        "Company": "9F28qUBqcVYgXcGeB46aBL1EWfElqjeTJdPuORpgj2U=",
        "CreditApplication": "5YcuQkxcmNjQ5Sa3Ft4jMFgZChH5W0Mxm/8qP9abARA=",
        "CreditNote": "1oriVdrNQ2p9W+6lzpNQUOJtaeyy9CfuGOt9uORvmlM=",
        "Customer": "VXGM2sfyAWp2yKsHfAhf4T5uMy9WZn0OIfVqkicWCjw=",
        "CustomerNote": "+ycOPuAxvSWMIe+bOL//AQB9ORuuT0/JTA9/bPrQiEU=",
        "Estimate": "5pRRPeSikk/g0xe/Jw21NA+deqAgpDAzFnJX7Vyp8Kk=",
        "EstimateLine": "OCO6MLGFD2ridMsDaG3A3nNCDJrJk9w48gPDCex+JUo=",
        "Expense": "SNEIQRgnEDDIDKdjJV4dxeR6r2XkrMx5Y5mkKKyCaRU=",
        "ExpenseLine": "ufrYl9gqEGkVMHF9y7vTMOOxXasVuouK0RWhKxzw+V0=",
        "Invoice": "s0pG7vQZaJar+fTPws7n93td7dEEvkjTHrbGXP5fYHM=",
        "InvoiceEvent": "yGcabZFeDkZNDs7h1R/f7IS11OCHigJhtaF4D9gENxc=",
        "InvoiceLine": "Qvq30rB+AU0nSwGnInQyj8S54sywzL+/9o3164dBMCQ=",
        "InvoiceTaxLine": "ZgSfWuwk4lZhIEulXYW0/FRdjlC6PkKTk6y+mjoiz9k=",
        "Item": "o8Xbb8d6zqOPFn4pyoLxF/9Flf7ilQSGn8IxDQwHijQ=",
        "JournalEntry": "kDOyeErROXOSfQyWU/BHO1kBVSw8SWp7PHCn/fyVq3Y=",
        "JournalLine": "m/Adj+uN3eFnAz+nnsY+M2QUjDeWohPN2fz8/z+nX6A=",
        "NoticeState": "f4zeqAbtwd7KHZ9CBuSpmX2uX9iQ5spWXmE+ayZsqUM=",
        "NumberSequence": "/afCxhL9CB1CibOuDUovJX6SPlr04x3d42DryrheOYE=",
        "PaymentApplication": "SGlzjqJEhV/aypaAx2igiMj0T6GtCZZ6PeTcz9TMQ9Y=",
        "PaymentReceived": "/GzzmD1lLKj+u0TGF3aUwot4kHSENNrrquNf3RSgTJc=",
        "PeriodClose": "koFZnT6xfqGCsBOgevccQvgchEe+2jP0rHja/S29Osw=",
        "RecurringTemplate": "NsfQA/3K/gVWj/sL9lJWlChA42X0KD+o/DNxOuLvwrI=",
        "RecurringTemplateLine": "yBHgbCd176pnRU6T6fgZ8WjUpVsIqKwuAbEsIGczv2Q=",
        "TaxAgency": "y1gt6RbbfmfQ5EDk8LBvkn5arfamI+pJKO6D2lzKYXY=",
        "TaxGroup": "pxWKOhw5+Vpb3BsDqt+77Nq6F5mv/VIVf7aTI22i35A=",
        "TaxRate": "8BEvuV+glxZp0sZJ8PxdJv5D1+Fbn+Y+MzM2l4UbfZs=",
        "Vendor": "1QtKRVhNgKWM/ztsLdKrC6p5WH4AaWsP6FcMkzPdewY=",
    ]

    static func hashes(_ models: [any PersistentModel.Type]) throws -> [String: String] {
        let model = try #require(NSManagedObjectModel.makeManagedObjectModel(for: models))
        return model.entityVersionHashesByName.mapValues { $0.base64EncodedString() }
    }

    @Test("Los esquemas 1, 2 y 3 tienen los mismos hashes que en las versiones publicadas")
    func frozenHashes() throws {
        #expect(try Self.hashes(SchemaV1.models) == Self.hashesV1)
        #expect(try Self.hashes(SchemaV2.models) == Self.hashesV2)
        #expect(try Self.hashes(SchemaV3.models) == Self.hashesV3)
    }

    @Test("El esquema 4 cambia las entidades (si no, SwiftData no sabría que hay que migrar)")
    func schema4Differs() throws {
        let v3 = try Self.hashes(SchemaV3.models)
        let v4 = try Self.hashes(SchemaV4.models)
        #expect(v4.count == v3.count + 6)
        for (entity, hash) in v3 { #expect(v4[entity] != hash, "\(entity)") }
    }
}
