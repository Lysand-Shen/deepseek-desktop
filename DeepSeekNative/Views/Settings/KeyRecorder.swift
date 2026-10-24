import AppKit
import SwiftUI

/// Click, then press a key combination. ⎋ cancels, ⌫ turns the shortcut off.
struct KeyRecorder: View {
    @Binding var combo: KeyCombo?

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var showsModifierHint = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                Button(action: toggleRecording) {
                    HStack(spacing: 3) {
                        if isRecording {
                            Text(L("Press a shortcut…"))
                                .foregroundStyle(.secondary)
                        } else if let combo {
                            ForEach(Array(combo.displayParts.enumerated()), id: \.offset) { _, part in
                                KeyCap(part)
                            }
                        } else {
                            Text(L("None"))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(minWidth: 128, minHeight: 20)
                }
                .help(isRecording ? L("Press ⎋ to cancel, or ⌫ to turn the shortcut off") : L("Click to record a new shortcut"))

                if combo != nil, !isRecording {
                    Button {
                        combo = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(L("Turn off this shortcut"))
                }
            }
            if showsModifierHint {
                Text(L("Include at least one of ⌘, ⌥ or ⌃"))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        showsModifierHint = false
        isRecording = true
        // Release the current shortcut so pressing it again can be recorded.
        HotKeyManager.shared.isSuspended = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        HotKeyManager.shared.isSuspended = false
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let plain = flags.isDisjoint(with: [.command, .option, .control, .shift])
        switch Int(event.keyCode) {
        case 53 where plain: // ⎋
            stopRecording()
            return
        case 51 where plain, 117 where plain: // ⌫ ⌦
            combo = nil
            stopRecording()
            return
        default:
            break
        }
        guard let recorded = KeyCombo(event: event) else {
            showsModifierHint = true
            NSSound.beep()
            return
        }
        showsModifierHint = false
        combo = recorded
        stopRecording()
    }
}

struct KeyCap: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .frame(minWidth: 20)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(.quaternary))
    }
}
