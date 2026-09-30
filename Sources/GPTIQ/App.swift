import AppKit
import SwiftUI
import RadarCore

@main
struct GPTIQApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--render-preview") {
            PreviewRenderer.run()
            app.run()
            return
        }
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private let store = RadarStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Opening the app a second time activates the existing instance.
        if let identifier = Bundle.main.bundleIdentifier,
           let other = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            other.activate()
            NSApp.terminate(nil)
            return
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "waveform.path", accessibilityDescription: "GPT IQ")
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.target = self
            button.action = #selector(toggle)
        }
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: PanelView(store: store) { NSApp.terminate(nil) })
        store.onChange = { [weak self] in self?.updateLabel() }
        updateLabel()
    }

    private func updateLabel() {
        if let point = store.selected, let iq = point.iq {
            item.button?.title = String(format: " %.1f", iq)
            let date = store.currentFetchedAt?.formatted(date: .abbreviated, time: .shortened) ?? "未知"
            item.button?.toolTip = "\(point.displayName) · \(point.effortName) · IQ \(iq)\n最近获取：\(date)\n点击查看并更新"
        } else {
            item.button?.title = " IQ"
            item.button?.toolTip = "GPT IQ · 点击获取"
        }
    }

    @objc private func toggle() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = item.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        store.opened()
    }

    func popoverDidClose(_ notification: Notification) { store.closed() }
    func applicationWillTerminate(_ notification: Notification) { store.closed() }
}
