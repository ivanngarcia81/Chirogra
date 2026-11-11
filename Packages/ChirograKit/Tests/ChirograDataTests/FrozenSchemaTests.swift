import CoreData
import SwiftData
import Testing
@testable import ChirograData

/// Los esquemas 1, 2, 3 y 4 están congelados: SwiftData reconoce los almacenes viejos por el hash de cada entidad, así que
/// si cambian (un nombre, un tipo, una relación, un `@Attribute`…) los libros de quien venga de esa versión no se abren.
/// Estos hashes son los de las versiones publicadas (1–3 calculados en `c214680`, 1.0.1 build 15, antes de congelar; los
/// del 4, en `e56f45c`, 1.1 build 30, antes de pasar al esquema 5).
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

    static let hashesV4: [String: String] = [
        "Account": "CVWAWlrkiWNKY4L8egTZdkCu2NiLCt/D73hgu1q+sis=",
        "Attachment": "b7OwZJYYRy14hFM1qzv4L57GPYYfMTY26s3bI50KQz4=",
        "AuditEvent": "5nOb6wMk01kW5gE0kZ9NL73XHyhIEjv5nJMUxg1nLt4=",
        "BankImportProfile": "sYCWeV+kN/c9Nu70rl7N3VPVLbpu4RpJxl0q2WDD9FE=",
        "BankRule": "AuKpKP4ad4hjQcQ4evfM8cMHbL9z6DLTGvk/ODqMm0U=",
        "BankTransaction": "KzwCaFbpoLw+pAZ2YqwtPgWR25MyIUbBH4Vdc4YmzMQ=",
        "Bill": "2JTvoybt6zghRs00Y33qn5UT1AegH/hritoXXZfU1GM=",
        "BillLine": "AWqTE4SQzCYBATmiQFx4Q0CEC3LU+iV06I87I/eplRo=",
        "BillPayment": "8BVd/85bwJBi/9fkYC3YsPnxYzs2Jfvz43YkadDF03g=",
        "Budget": "eAYqS7DJLT8RAI9MTlEFS6DQTF8Au4my2qHqQr+o88c=",
        "BudgetLine": "UHDIaR0z9q+LvUb1tBWRwUgeshmoBbHyyyzVzXzoV2M=",
        "Company": "RYdtGP71/kIcxcsZ6eBacFRpfC7bo8YMPC8RBsL1kxQ=",
        "CreditApplication": "pjSn6mWR8W1FPXKQCLBC431N6uKhyXR0YXQC+ZvO31s=",
        "CreditNote": "ToD3tKzBSN6Y2yspq/OMc4LNMkBIiUiBmwqWAfC7HU0=",
        "Customer": "TnchahERymugB7yZOuP5oLsVBiKYgZLcJ01UF4OHp1I=",
        "CustomerNote": "D8SoKk8MssPGb6eQ2fAw/dYfcitQVeMxBrb08Leh/1U=",
        "Estimate": "An0RjyPO/fSXtmxjf7D97XASjKMTlMnySI0UOdc4ehY=",
        "EstimateLine": "4mL5aW2Gd7g11sbA5bu8OMsUm5MPENJzxW20IfwNwC4=",
        "Expense": "o73/si8jXAtalc/C4RP/sXGeGTaWAVFAyieMYVrRC18=",
        "ExpenseLine": "2V70oy8Tmz7ka8bftXcvdUwYL4FDKBXD7q57SWlNSNk=",
        "Invoice": "n8aPJO5inMGyPFJCM/JnT3Q+9Dc73SC/moEfoz37dm8=",
        "InvoiceEvent": "KhIa57YaIXtSGuev+/4dmG32m+6L3J0L9c/eW+SwLyY=",
        "InvoiceLine": "Jkz1y1XHX3Ihzh0Uxrf7quWVcd75NYYoEarmPkL4Ayk=",
        "InvoiceTaxLine": "mhNgFXqOqGIcysraAx8XrwMU1esIZBgkKQd9JDuQdZc=",
        "Item": "eJ/GSr+lg1vBwrdmn3YNTaJHRwrvM6Xlku7snVtouik=",
        "JournalEntry": "npMRe18ATDOETARjhpx+UQF8PUueMPernhD/KsCRGPo=",
        "JournalLine": "P2o74a/TUJYr8C69Z51ImomG+fuKR44Fne+2iTqdSCc=",
        "NoticeState": "fU9Zhp5FuaYUAzYGYDNio5rYhvl92Atisn5SWGifi4k=",
        "NumberSequence": "QzIWh+fc/ThB1wo0MGjnlO5ERhYB3UHMQ3uukoaOONw=",
        "PaymentApplication": "0E5hDJRLx7QGng7kbLcX942qEKs5CQ/CVzp9IMq1uoE=",
        "PaymentReceived": "WJdb1CWo0PzUXJ9IPHY1E7ubjqMacTnF1wGOF+k+HEs=",
        "PeriodClose": "lGwYJR9IBvvLfxuu7MiR/dY2GA6RdjhsSaWJHI36XvU=",
        "Reconciliation": "Z3eIyIO7bE392YMwGwDLhURRFi7v83vWlU1AUQ5T6ys=",
        "RecurringTemplate": "nk+zXAGmj8LfxCIbDZtCPBP9sWEi4JKyWygjgQg6ZeQ=",
        "RecurringTemplateLine": "GJuZ8i6YCaKtxSb55wLMSEzRAUzYfiWGWF4hfx3z14c=",
        "TaxAgency": "1mFItXoZ9v/2c38fbu4IDW6bUYTVm7jX9QdeCQjla5g=",
        "TaxGroup": "q44XCVmFnBOwq7eknOGaN84q8PRkj6Fa5Cke7VrJP6I=",
        "TaxRate": "7BioUb8FjmxTjERSlRojRSDo6nmYwtC+8OojKl7oOF0=",
        "Vendor": "peat6IJQJEHoopLiAapDxgCg6dH7knMoSZnWEsD9QE8=",
    ]

    static func hashes(_ models: [any PersistentModel.Type]) throws -> [String: String] {
        let model = try #require(NSManagedObjectModel.makeManagedObjectModel(for: models))
        return model.entityVersionHashesByName.mapValues { $0.base64EncodedString() }
    }

    @Test("Los esquemas 1, 2, 3 y 4 tienen los mismos hashes que en las versiones publicadas")
    func frozenHashes() throws {
        #expect(try Self.hashes(SchemaV1.models) == Self.hashesV1)
        #expect(try Self.hashes(SchemaV2.models) == Self.hashesV2)
        #expect(try Self.hashes(SchemaV3.models) == Self.hashesV3)
        #expect(try Self.hashes(SchemaV4.models) == Self.hashesV4)
    }

    @Test("El esquema 4 cambia las entidades (si no, SwiftData no sabría que hay que migrar)")
    func schema4Differs() throws {
        let v3 = try Self.hashes(SchemaV3.models)
        let v4 = try Self.hashes(SchemaV4.models)
        #expect(v4.count == v3.count + 6)
        for (entity, hash) in v3 { #expect(v4[entity] != hash, "\(entity)") }
    }

    @Test("El esquema 5 solo cambia la bitácora y los movimientos del banco")
    func schema5Differs() throws {
        let v4 = try Self.hashes(SchemaV4.models)
        let v5 = try Self.hashes(SchemaV5.models)
        #expect(Set(v5.keys) == Set(v4.keys))
        #expect(Set(v4.keys.filter { v4[$0] != v5[$0] }) == ["AuditEvent", "BankTransaction"])
    }
}
