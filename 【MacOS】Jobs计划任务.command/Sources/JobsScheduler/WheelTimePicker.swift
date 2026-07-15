//
//  WheelTimePicker.swift
//  JobsScheduler
//
//  Created by Jobs on 2026年7月14日，星期二.
//

import AppKit
import SwiftUI

struct WheelTimePicker: View {
    let title: String
    @Binding var selection: Date
    private let calendar = Calendar.current

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            HStack(spacing: 2) {
                WheelColumn(values: Array(0..<24), selection: hourBinding)
                    .frame(width: 64, height: 112)
                    .accessibilityLabel("小时")

                Text(":")
                    .font(.title3.monospacedDigit().bold())

                WheelColumn(values: Array(0..<60), selection: minuteBinding)
                    .frame(width: 64, height: 112)
                    .accessibilityLabel("分钟")
            }
            .font(.body.monospacedDigit())
            .fixedSize(horizontal: true, vertical: true)
            .padding(.horizontal, 6)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.13))
                    .frame(height: 28)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var hourBinding: Binding<Int> {
        Binding(
            get: { calendar.component(.hour, from: selection) },
            set: { update(hour: $0) }
        )
    }

    private var minuteBinding: Binding<Int> {
        Binding(
            get: { calendar.component(.minute, from: selection) },
            set: { update(minute: $0) }
        )
    }

    private func update(hour: Int? = nil, minute: Int? = nil) {
        let currentHour = calendar.component(.hour, from: selection)
        let currentMinute = calendar.component(.minute, from: selection)
        selection = calendar.date(
            bySettingHour: hour ?? currentHour,
            minute: minute ?? currentMinute,
            second: 0,
            of: selection
        ) ?? selection
    }
}

private struct WheelColumn: NSViewRepresentable {
    let values: [Int]
    @Binding var selection: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WheelColumnNSView {
        let view = WheelColumnNSView(values: values, selection: selection)
        view.onSelection = { value in context.coordinator.updateSelection(value) };return view
    }

    func updateNSView(_ nsView: WheelColumnNSView, context: Context) {
        context.coordinator.parent = self
        nsView.synchronize(values: values, selection: selection)
    }

    @MainActor final class Coordinator {
        var parent: WheelColumn

        init(_ parent: WheelColumn) {
            self.parent = parent
        }

        func updateSelection(_ value: Int) {
            guard parent.selection != value else { return }
            parent.selection = value
        }
    }
}

private final class WheelColumnNSView: NSView {
    private let rowHeight: CGFloat = 28
    private var values: [Int]
    private var selection: Int
    private var movement: CGFloat = 0
    private var lastDragY: CGFloat?
    var onSelection: ((Int) -> Void)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(values: [Int], selection: Int) {
        self.values = values
        self.selection = selection
        super.init(frame: NSRect(x: 0, y: 0, width: 64, height: 112))
        setAccessibilityElement(true)
        setAccessibilityRole(.incrementor)
        setAccessibilityValue(String(format: "%02d", selection))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 64, height: 112)
    }

    func synchronize(values: [Int], selection: Int) {
        self.values = values
        guard self.selection != selection else { return }
        self.selection = selection
        movement = 0
        setAccessibilityValue(String(format: "%02d", selection))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !values.isEmpty else { return }
        let selectedIndex = values.firstIndex(of: selection) ?? 0
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        for relativeIndex in -3...3 {
            let index = wrappedIndex(selectedIndex + relativeIndex)
            let distance = abs(relativeIndex)
            let alpha: CGFloat = distance == 0 ? 1 : (distance == 1 ? 0.52 : (distance == 2 ? 0.26 : 0.10))
            let fontSize: CGFloat = distance == 0 ? 16 : (distance == 1 ? 14 : 12)
            let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: distance == 0 ? .semibold : .regular)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.labelColor.withAlphaComponent(alpha),
                .paragraphStyle: paragraph
            ]
            let centerY = bounds.midY + CGFloat(relativeIndex) * rowHeight - movement
            let text = NSString(format: "%02d", values[index])
            let textHeight = ceil(text.size(withAttributes: attributes).height)
            let rect = NSRect(x: 0, y: centerY - textHeight / 2, width: bounds.width, height: textHeight)
            text.draw(in: rect, withAttributes: attributes)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        applyMovement(-event.scrollingDeltaY)
        if event.phase == .ended || event.momentumPhase == .ended {
            settle()
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        lastDragY = convert(event.locationInWindow, from: nil).y
    }

    override func mouseDragged(with event: NSEvent) {
        let currentY = convert(event.locationInWindow, from: nil).y
        guard let lastDragY else { return }
        applyMovement(lastDragY - currentY)
        self.lastDragY = currentY
    }

    override func mouseUp(with event: NSEvent) {
        lastDragY = nil
        settle()
    }

    override func accessibilityPerformIncrement() -> Bool {
        advance(by: 1)
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        advance(by: -1)
        return true
    }

    private func applyMovement(_ delta: CGFloat) {
        movement += delta
        while movement >= rowHeight {
            movement -= rowHeight
            advance(by: 1)
        }
        while movement <= -rowHeight {
            movement += rowHeight
            advance(by: -1)
        }
        needsDisplay = true
    }

    private func settle() {
        if movement >= rowHeight / 2 {
            advance(by: 1)
        } else if movement <= -rowHeight / 2 {
            advance(by: -1)
        }
        movement = 0
        needsDisplay = true
    }

    private func advance(by offset: Int) {
        guard !values.isEmpty else { return }
        let currentIndex = values.firstIndex(of: selection) ?? 0
        selection = values[wrappedIndex(currentIndex + offset)]
        setAccessibilityValue(String(format: "%02d", selection))
        onSelection?(selection)
        needsDisplay = true
    }

    private func wrappedIndex(_ index: Int) -> Int {
        guard !values.isEmpty else { return 0 };return (index % values.count + values.count) % values.count
    }
}
