//
//  LogTextView.swift
//  JobsScheduler
//
//  Created by Jobs on 2026年7月22日，星期三.
//

import AppKit
import SwiftUI

struct LogTextView: NSViewRepresentable {
    let text: String
    let contentRevision: UUID
    let scrollToEndRequestID: UUID
    let followsLatestOutput: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .labelColor
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.layoutManager?.allowsNonContiguousLayout = true
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let wasNearBottom = context.coordinator.isNearBottom(scrollView)
        let contentChanged = context.coordinator.contentRevision != contentRevision
        let explicitlyRequestedEnd = context.coordinator.scrollToEndRequestID != scrollToEndRequestID
        if contentChanged {
            textView.string = text
            textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            textView.textColor = .labelColor
            context.coordinator.contentRevision = contentRevision
        }
        context.coordinator.scrollToEndRequestID = scrollToEndRequestID
        guard contentChanged, explicitlyRequestedEnd || (followsLatestOutput && wasNearBottom) else { return }
        DispatchQueue.main.async {
            textView.scrollToEndOfDocument(nil)
        }
    }

    @MainActor final class Coordinator {
        var contentRevision: UUID?
        var scrollToEndRequestID: UUID?

        func isNearBottom(_ scrollView: NSScrollView) -> Bool {
            guard let documentView = scrollView.documentView else { return true }
            let visibleBottom = scrollView.contentView.bounds.maxY
            return documentView.bounds.height - visibleBottom < 48
        }
    }
}
