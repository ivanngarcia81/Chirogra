// Texto de un PDF con PDFKit (macOS), para las tablas que los estados solo publican en PDF (Florida, DR-15DSS).
// Uso: swift scripts/tasas/pdf_texto.swift archivo.pdf > archivo.txt
import Foundation
import PDFKit
guard CommandLine.arguments.count == 2, let doc = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1])) else {
    FileHandle.standardError.write(Data("Uso: swift pdf_texto.swift archivo.pdf\n".utf8))
    exit(1)
}
print(doc.string ?? "")
