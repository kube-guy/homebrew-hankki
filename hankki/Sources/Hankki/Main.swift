import AppKit
import SwiftUI

enum Hankki {
    static let version = "0.3.1"
    static let help = """
    한 끼 꾸러미 \(version)

    hankki               앱 열기
    hankki --version     버전 확인
    hankki --self-check  내장 점검 실행
    """
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // `swift run` 처럼 앱 번들 없이 실행해도 Dock 에 뜨고 앞으로 나오게 한다.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main struct HankkiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = Store()

    init() {
        let arguments = CommandLine.arguments
        if arguments.contains("--version") { print("hankki \(Hankki.version)"); exit(0) }
        if arguments.contains("--help") { print(Hankki.help); exit(0) }
        if arguments.contains("--self-check") { exit(Checks.run() ? 0 : 1) }
    }

    var body: some Scene {
        WindowGroup("한 끼 꾸러미") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1060, minHeight: 720)
        }
        .defaultSize(width: 1240, height: 900)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}
