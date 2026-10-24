import AppKit
import SwiftUI

/// Click, then press a key combination. ⎋ cancels, ⌫ turns the shortcut off.
struct KeyRecorder: View {
    @Binding var combo: KeyCombo?

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var hint: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                Button(action: toggleRecording) {
                    HStack(spacing: 3) {
                        if isRecording {
                            Text("请按下快捷键…")
                                .foregroundStyle(.secondary)
                        } else if let combo {
                            ForEach(Array(combo.displayParts.enumerated()), id: \.offset) { _, part in
                                KeyCap(part)
                            }
                        } else {
                            Text("未设置")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(minWidth: 128, minHeight: 20)
                }
                .help(isRecording ? "按 ⎋ 取消，按 ⌫ 停用快捷键" : "点按以录制新的快捷键")

                if combo != nil, !isRecording {
                    Button {
                        combo = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("停用全局快捷键")
                }
            }
            if let hint {
                Text(hint)
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
        hint = nil
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
            hint = "请至少包含 ⌘、⌥ 或 ⌃ 中的一个修饰键"
            NSSound.beep()
            return
        }
        hint = nil
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
