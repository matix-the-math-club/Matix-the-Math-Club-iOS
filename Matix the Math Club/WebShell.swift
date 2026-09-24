import SwiftUI
import WebKit
import UserNotifications
#if os(iOS)
import UIKit
#else
import AppKit
#endif

final class ShellCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {

    // set once the WKWebView exists so native replies (e.g. search results) can be posted back into it
    weak var webView: WKWebView?

    // window.open / target=_blank: keep it in the same view
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    // camera + microphone for club video calls
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.grant)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        #if os(iOS)
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        Self.present(alert) { completionHandler() }
        #else
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
        completionHandler()
        #endif
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        #if os(iOS)
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        Self.present(alert) { completionHandler(false) }
        #else
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
        #endif
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        #if os(iOS)
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText ?? "" }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak alert] _ in
            completionHandler(alert?.textFields?.first?.text ?? "")
        })
        Self.present(alert) { completionHandler(nil) }
        #else
        let alert = NSAlert()
        alert.messageText = prompt
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        completionHandler(alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil)
        #endif
    }

    #if os(macOS)
    // <input type="file"> uploads
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.begin { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
    }
    #endif

    #if os(iOS)
    static func present(_ alert: UIAlertController, fallback: () -> Void) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow } ?? scenes.first?.windows.first
        guard var top = window?.rootViewController else {
            fallback()
            return
        }
        while let presented = top.presentedViewController { top = presented }
        top.present(alert, animated: true)
    }
    #endif
}

func makeShellWebView(coordinator: ShellCoordinator) -> WKWebView {
    let config = WKWebViewConfiguration()
    config.websiteDataStore = .default()
    config.defaultWebpagePreferences.allowsContentJavaScript = true
    config.mediaTypesRequiringUserActionForPlayback = []
    #if os(iOS)
    config.allowsInlineMediaPlayback = true
    #endif
    config.userContentController.add(coordinator, name: "matix")
    let webView = WKWebView(frame: .zero, configuration: config)
    webView.navigationDelegate = coordinator
    webView.uiDelegate = coordinator
    coordinator.webView = webView
    UNUserNotificationCenter.current().delegate = coordinator
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    if let url = Bundle.main.url(forResource: "app", withExtension: "html") {
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }
    return webView
}

#if os(iOS)
struct WebShellView: UIViewRepresentable {
    func makeCoordinator() -> ShellCoordinator { ShellCoordinator() }
    func makeUIView(context: Context) -> WKWebView { makeShellWebView(coordinator: context.coordinator) }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#else
struct WebShellView: NSViewRepresentable {
    func makeCoordinator() -> ShellCoordinator { ShellCoordinator() }
    func makeNSView(context: Context) -> WKWebView { makeShellWebView(coordinator: context.coordinator) }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#endif


extension ShellCoordinator: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "matix" else { return }
        guard let dict = message.body as? [String: Any], let type = dict["type"] as? String else { return }

        switch type {
        case "notify":
            let title = (dict["title"] as? String) ?? "Matix the Math Club"
            let body = (dict["body"] as? String) ?? ""
            let content = UNMutableNotificationContent()
            content.title = title.isEmpty ? "Matix the Math Club" : title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)

        case "search":
            // native Google-first / DuckDuckGo-fallback web search, bridged back to the AI chat in app.html
            let query = (dict["query"] as? String) ?? ""
            let requestId = (dict["requestId"] as? String) ?? ""
            guard !requestId.isEmpty else { return }
            Task { [weak self] in
                let results = await MatixAI.search(query)
                await self?.postSearchResults(results, requestId: requestId)
            }

        default:
            break
        }
    }

    @MainActor
    private func postSearchResults(_ results: [MatixSource], requestId: String) {
        guard let webView else { return }
        let payload = results.map { source in
            [
                "title": source.title,
                "url": source.url.absoluteString,
                "snippet": source.snippet,
                "provider": source.provider
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        let escapedId = requestId.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        let js = "window.__matixSearchCallback && window.__matixSearchCallback('\(escapedId)', \(json));"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
}

extension ShellCoordinator: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
