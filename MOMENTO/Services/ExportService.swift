import UIKit
import os

/// Generates PDF insurance reports and CSV catalogs from CollectionItem data.
/// All methods are synchronous and produce temp file URLs suitable for UIActivityViewController.
nonisolated final class ExportService: Sendable {

    static let shared = ExportService()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Momento", category: "Export")

    private init() {}

    // MARK: - Errors

    enum ExportError: Error, LocalizedError {
        case pdfGenerationFailed
        case csvGenerationFailed
        case noItems

        var errorDescription: String? {
            switch self {
            case .pdfGenerationFailed: "Failed to generate PDF report."
            case .csvGenerationFailed: "Failed to generate CSV file."
            case .noItems: "No items to export."
            }
        }
    }

    // MARK: - PDF Report

    /// Generates a multi-page PDF insurance report for the given items.
    /// Returns the URL of the generated PDF in a temp directory.
    func generatePDFReport(items: [CollectionItem]) throws -> URL {
        guard !items.isEmpty else { throw ExportError.noItems }

        let pageRect = CGRect(
            x: 0, y: 0,
            width: AppConstants.Export.pageWidth,
            height: AppConstants.Export.pageHeight
        )
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let margin = AppConstants.Export.margin
        let contentWidth = pageRect.width - margin * 2

        let data = renderer.pdfData { context in
            // Cover page
            drawCoverPage(context: context, pageRect: pageRect, items: items)

            // Item pages
            for item in items.sorted(by: { $0.title < $1.title }) {
                drawItemPage(context: context, pageRect: pageRect, item: item, contentWidth: contentWidth)
            }
        }

        let url = try exportFileURL(name: "Momento_Insurance_Report", extension: "pdf")
        try data.write(to: url, options: .atomic)
        logger.info("PDF report generated: \(items.count) items, \(data.count) bytes")
        return url
    }

    // MARK: - CSV Export

    /// Generates a CSV catalog with one row per item.
    /// Returns the URL of the generated CSV in a temp directory.
    func generateCSV(items: [CollectionItem]) throws -> URL {
        guard !items.isEmpty else { throw ExportError.noItems }

        var csv = "Title,Collection,Description,Tags,Purchase Date,Purchase Price,Estimated Value,Serial Number,Provenance Notes,Photos,Voice Memos,Notes,Created,Updated\n"

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short

        for item in items.sorted(by: { $0.title < $1.title }) {
            let fields: [String] = [
                escapeCSV(item.title),
                escapeCSV(item.collectionName),
                escapeCSV(item.itemDescription),
                escapeCSV(item.tags.joined(separator: "; ")),
                item.purchaseDate.map { dateFormatter.string(from: $0) } ?? "",
                item.purchasePrice.map { String(format: "%.2f", $0) } ?? "",
                item.estimatedValue.map { String(format: "%.2f", $0) } ?? "",
                escapeCSV(item.serialNumber ?? ""),
                escapeCSV(item.provenanceNotes ?? ""),
                "\(item.photoAttachments.count)",
                "\(item.voiceMemos.count)",
                "\(item.textMemories.count)",
                dateFormatter.string(from: item.createdAt),
                dateFormatter.string(from: item.updatedAt),
            ]
            csv += fields.joined(separator: ",") + "\n"
        }

        let url = try exportFileURL(name: "Momento_Catalog", extension: "csv")
        try csv.write(to: url, atomically: true, encoding: .utf8)
        logger.info("CSV exported: \(items.count) items")
        return url
    }

    // MARK: - Single-Item PDF

    /// Generates a single-page PDF for one item (used from detail view share).
    func generateSingleItemPDF(item: CollectionItem) throws -> URL {
        let pageRect = CGRect(
            x: 0, y: 0,
            width: AppConstants.Export.pageWidth,
            height: AppConstants.Export.pageHeight
        )
        let margin = AppConstants.Export.margin
        let contentWidth = pageRect.width - margin * 2
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let data = renderer.pdfData { context in
            drawItemPage(context: context, pageRect: pageRect, item: item, contentWidth: contentWidth)
        }

        let safeName = item.title.replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
        let url = try exportFileURL(name: "Momento_\(safeName)", extension: "pdf")
        try data.write(to: url, options: .atomic)
        logger.info("Single-item PDF generated: \(item.title)")
        return url
    }

    // MARK: - Cleanup

    func cleanupExportFiles() {
        guard let tempDir = try? exportTempDirectory() else { return }
        try? FileManager.default.removeItem(at: tempDir)
        logger.info("Export temp files cleaned up")
    }

    // MARK: - PDF Drawing Helpers

    private func drawCoverPage(context: UIGraphicsPDFRendererContext, pageRect: CGRect, items: [CollectionItem]) {
        context.beginPage()
        let margin = AppConstants.Export.margin
        var y = pageRect.height * 0.3

        // Title
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 32, weight: .bold),
            .foregroundColor: UIColor.label,
        ]
        let title = "Momento Insurance Report"
        let titleSize = title.size(withAttributes: titleAttrs)
        title.draw(
            at: CGPoint(x: (pageRect.width - titleSize.width) / 2, y: y),
            withAttributes: titleAttrs
        )
        y += titleSize.height + 20

        // Date
        let dateAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: AppConstants.Export.headingFontSize),
            .foregroundColor: UIColor.secondaryLabel,
        ]
        let dateString = "Generated \(Date.now.formatted(date: .long, time: .shortened))"
        let dateSize = dateString.size(withAttributes: dateAttrs)
        dateString.draw(
            at: CGPoint(x: (pageRect.width - dateSize.width) / 2, y: y),
            withAttributes: dateAttrs
        )
        y += dateSize.height + 40

        // Summary
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: AppConstants.Export.bodyFontSize),
            .foregroundColor: UIColor.label,
        ]

        let totalValue = items.compactMap(\.estimatedValue).reduce(0, +)
        let summaryLines = [
            "Total Items: \(items.count)",
            "Total Estimated Value: \(totalValue.formatted(.currency(code: "USD")))",
            "Collections: \(Set(items.map(\.collectionName).filter { !$0.isEmpty }).sorted().joined(separator: ", "))",
        ]

        for line in summaryLines {
            let lineSize = line.size(withAttributes: bodyAttrs)
            line.draw(
                at: CGPoint(x: (pageRect.width - lineSize.width) / 2, y: y),
                withAttributes: bodyAttrs
            )
            y += lineSize.height + AppConstants.Export.lineSpacing
        }

        // Footer
        let footerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: AppConstants.Export.captionFontSize),
            .foregroundColor: UIColor.tertiaryLabel,
        ]
        let footer = "This report was generated by the Momento app."
        let footerSize = footer.size(withAttributes: footerAttrs)
        footer.draw(
            at: CGPoint(x: (pageRect.width - footerSize.width) / 2, y: pageRect.height - margin - footerSize.height),
            withAttributes: footerAttrs
        )
    }

    private func drawItemPage(
        context: UIGraphicsPDFRendererContext,
        pageRect: CGRect,
        item: CollectionItem,
        contentWidth: CGFloat
    ) {
        context.beginPage()
        let margin = AppConstants.Export.margin
        var y = margin

        // Item title
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: AppConstants.Export.titleFontSize, weight: .bold),
            .foregroundColor: UIColor.label,
        ]
        let titleRect = CGRect(x: margin, y: y, width: contentWidth, height: 40)
        item.title.draw(in: titleRect, withAttributes: titleAttrs)
        y += 40 + AppConstants.Export.lineSpacing

        // Collection name
        if !item.collectionName.isEmpty {
            let collAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: AppConstants.Export.headingFontSize),
                .foregroundColor: UIColor.secondaryLabel,
            ]
            item.collectionName.draw(at: CGPoint(x: margin, y: y), withAttributes: collAttrs)
            y += 24
        }

        // Thumbnail
        if let thumbName = item.thumbnailFileName,
           let thumbURL = try? FileStorageService.shared.resolveURL(for: thumbName),
           let thumbImage = UIImage(contentsOfFile: thumbURL.path(percentEncoded: false))
        {
            let maxSize = AppConstants.Export.thumbnailMaxSize
            let aspect = thumbImage.size.width / thumbImage.size.height
            let drawWidth = min(maxSize, contentWidth)
            let drawHeight = drawWidth / aspect
            let imageRect = CGRect(x: margin, y: y, width: drawWidth, height: drawHeight)
            thumbImage.draw(in: imageRect)
            y += drawHeight + AppConstants.Export.sectionSpacing
        }

        y += AppConstants.Export.lineSpacing

        // Metadata table
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: AppConstants.Export.bodyFontSize, weight: .semibold),
            .foregroundColor: UIColor.label,
        ]
        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: AppConstants.Export.bodyFontSize),
            .foregroundColor: UIColor.label,
        ]
        let labelWidth: CGFloat = 140

        let metadataRows: [(String, String)] = [
            ("Estimated Value", item.formattedEstimatedValue ?? "—"),
            ("Purchase Price", item.formattedPurchasePrice ?? "—"),
            ("Purchase Date", item.purchaseDate?.formatted(date: .long, time: .omitted) ?? "—"),
            ("Serial Number", item.serialNumber ?? "—"),
            ("Tags", item.tags.isEmpty ? "—" : item.tags.joined(separator: ", ")),
        ]

        for (label, value) in metadataRows {
            guard y < pageRect.height - margin - 60 else { break }
            "\(label):".draw(at: CGPoint(x: margin, y: y), withAttributes: labelAttrs)
            value.draw(at: CGPoint(x: margin + labelWidth, y: y), withAttributes: valueAttrs)
            y += 18
        }

        y += AppConstants.Export.sectionSpacing

        // Description
        if !item.itemDescription.isEmpty, y < pageRect.height - margin - 80 {
            "Description:".draw(at: CGPoint(x: margin, y: y), withAttributes: labelAttrs)
            y += 18

            let descRect = CGRect(x: margin, y: y, width: contentWidth, height: 80)
            item.itemDescription.draw(in: descRect, withAttributes: valueAttrs)
            y += 80 + AppConstants.Export.lineSpacing
        }

        // Provenance
        if let provenance = item.provenanceNotes, !provenance.isEmpty, y < pageRect.height - margin - 80 {
            "Provenance:".draw(at: CGPoint(x: margin, y: y), withAttributes: labelAttrs)
            y += 18

            let provRect = CGRect(x: margin, y: y, width: contentWidth, height: 60)
            provenance.draw(in: provRect, withAttributes: valueAttrs)
            y += 60 + AppConstants.Export.lineSpacing
        }

        // Notes summary
        if !item.textMemories.isEmpty, y < pageRect.height - margin - 60 {
            y += AppConstants.Export.lineSpacing
            "Notes (\(item.textMemories.count)):".draw(at: CGPoint(x: margin, y: y), withAttributes: labelAttrs)
            y += 18

            for note in item.textMemories.prefix(3) {
                guard y < pageRect.height - margin - 30 else { break }
                let noteRect = CGRect(x: margin + 10, y: y, width: contentWidth - 10, height: 36)
                "• \(note.body)".draw(in: noteRect, withAttributes: valueAttrs)
                y += 36
            }
        }

        // Footer
        let footerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: AppConstants.Export.captionFontSize),
            .foregroundColor: UIColor.tertiaryLabel,
        ]
        let footer = "Photos: \(item.photoAttachments.count)  |  Voice Memos: \(item.voiceMemos.count)  |  Notes: \(item.textMemories.count)"
        footer.draw(
            at: CGPoint(x: margin, y: pageRect.height - margin),
            withAttributes: footerAttrs
        )
    }

    // MARK: - File Helpers

    private func exportTempDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MomentoExports", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    private func exportFileURL(name: String, extension ext: String) throws -> URL {
        let dir = try exportTempDirectory()
        let dateString = Date.now.formatted(.iso8601.year().month().day())
        return dir.appendingPathComponent("\(name)_\(dateString).\(ext)")
    }

    private func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}
