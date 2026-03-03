import Foundation
import AppKit

/// Utilities for exporting conversation sessions to various formats.
enum ConversationExporter {

    // MARK: - Markdown Export

    /// Export a conversation session as a formatted Markdown string.
    ///
    /// The output includes a title header, session metadata, and each entry
    /// with a timestamp, role label, and text content.
    ///
    /// - Parameter session: The conversation session to export.
    /// - Returns: A formatted Markdown string.
    static func exportAsMarkdown(session: ConversationSession) -> String {
        var md = "# \(session.title)\n\n"

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short

        md += "**Started:** \(dateFormatter.string(from: session.startedAt))\n"
        if let ended = session.endedAt {
            md += "**Ended:** \(dateFormatter.string(from: ended))\n"
        }

        let durationMinutes = Int(session.duration / 60)
        let durationSeconds = Int(session.duration) % 60
        md += "**Duration:** \(durationMinutes)m \(durationSeconds)s\n"
        md += "**Entries:** \(session.entryCount)\n\n"
        md += "---\n\n"

        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .medium

        for entry in session.entries {
            let roleLabel = roleEmoji(for: entry.role)
            let timestamp = timeFormatter.string(from: entry.timestamp)
            md += "**\(roleLabel) [\(timestamp)]**\n\n"
            md += "\(entry.text)\n\n"
        }

        return md
    }

    // MARK: - PDF Export

    /// Export a conversation session as a basic PDF document.
    ///
    /// Uses `NSAttributedString` with basic styling to render each entry.
    ///
    /// - Parameter session: The conversation session to export.
    /// - Returns: The PDF data, or `nil` if rendering fails.
    static func exportAsPDF(session: ConversationSession) -> Data? {
        let markdown = exportAsMarkdown(session: session)

        // Build a simple attributed string from the markdown content
        let attributed = NSMutableAttributedString()

        // Title
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 18),
            .foregroundColor: NSColor.labelColor
        ]
        attributed.append(NSAttributedString(string: "\(session.title)\n\n", attributes: titleAttrs))

        // Metadata
        let metaAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short

        var metaText = "Started: \(dateFormatter.string(from: session.startedAt))\n"
        if let ended = session.endedAt {
            metaText += "Ended: \(dateFormatter.string(from: ended))\n"
        }
        let durationMinutes = Int(session.duration / 60)
        let durationSeconds = Int(session.duration) % 60
        metaText += "Duration: \(durationMinutes)m \(durationSeconds)s • \(session.entryCount) entries\n\n"
        attributed.append(NSAttributedString(string: metaText, attributes: metaAttrs))

        // Separator
        attributed.append(NSAttributedString(string: "────────────────────────────────\n\n", attributes: metaAttrs))

        // Entries
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .medium

        let roleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 12),
            .foregroundColor: NSColor.labelColor
        ]
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.labelColor
        ]

        for entry in session.entries {
            let roleLabel = roleEmoji(for: entry.role)
            let timestamp = timeFormatter.string(from: entry.timestamp)
            attributed.append(NSAttributedString(string: "\(roleLabel) [\(timestamp)]\n", attributes: roleAttrs))
            attributed.append(NSAttributedString(string: "\(entry.text)\n\n", attributes: bodyAttrs))
        }

        // Render to PDF
        let pageSize = CGSize(width: 612, height: 792) // US Letter
        let margin: CGFloat = 50
        let textRect = CGRect(
            x: margin,
            y: margin,
            width: pageSize.width - margin * 2,
            height: pageSize.height - margin * 2
        )

        let textStorage = NSTextStorage(attributedString: attributed)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(size: textRect.size)
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)

        let pdfData = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return nil
        }

        // Calculate total glyph range
        let fullRange = layoutManager.glyphRange(for: textContainer)
        var currentLocation = fullRange.location
        let endLocation = NSMaxRange(fullRange)

        while currentLocation < endLocation {
            pdfContext.beginPDFPage(nil)

            // Set up the graphics context for AppKit drawing
            let nsContext = NSGraphicsContext(cgContext: pdfContext, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsContext

            // Transform to position text in the margin area
            pdfContext.translateBy(x: margin, y: margin)

            // Draw the glyphs that fit on this page
            let glyphRange = layoutManager.glyphRange(forBoundingRect: CGRect(origin: .zero, size: textRect.size), in: textContainer)
            layoutManager.drawBackground(forGlyphRange: glyphRange, at: .zero)
            layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: .zero)

            NSGraphicsContext.restoreGraphicsState()
            pdfContext.endPDFPage()

            // Move past drawn glyphs (simplified — single page for most conversations)
            currentLocation = NSMaxRange(glyphRange)
            break
        }

        pdfContext.closePDF()
        return pdfData as Data
    }

    // MARK: - Helpers

    /// Return an emoji label for a conversation role.
    private static func roleEmoji(for role: ConversationRole) -> String {
        switch role {
        case .user: return "🧑 You"
        case .assistant: return "🤖 Quinn"
        case .system: return "⚙️ System"
        case .tool: return "🔧 Tool"
        }
    }
}
