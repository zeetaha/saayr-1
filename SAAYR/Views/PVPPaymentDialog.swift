import SwiftUI
import WebKit

struct PVPPaymentDialog: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var languageManager: LanguageManager
    @EnvironmentObject var userManager: UserManager

    var body: some View {
        NavigationView {
            WebView(
                url: URL(string: "https://api.saayr.sa/api/v1/user/pvp/payment-webview?token=\(UserModel.shared.user?.accessToken ?? "")")!
            ) { message in
                
                print("✅ Received:", message)
                

                    if let dict = message as? [String: Any],
                       let type = dict["type"] as? String,
                       type == "navigate_back" {
                        
                        print("🔙 Closing WebView")
                        isPresented = false
                    }
            }
                .edgesIgnoringSafeArea(.bottom)
                
        }
    }
}
struct WebView: UIViewRepresentable {
    let url: URL
    var onMessage: (Any) -> Void   // 👈 callback to SwiftUI

    func makeCoordinator() -> Coordinator {
        Coordinator(onMessage: onMessage)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        
        // 👇 Add message handler
        config.userContentController.add(
            context.coordinator,
            name: "saayrBridge"
        )
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        
        webView.load(URLRequest(url: url))
        
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var onMessage: (Any) -> Void
        
        init(onMessage: @escaping (Any) -> Void) {
            self.onMessage = onMessage
        }

        // 👇 Receive message from JS
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            
            if message.name == "saayrBridge" {
                print("📩 Message from Web:", message.body)
                
                onMessage(message.body)   // send to SwiftUI
            }
        }
    }
}

#Preview {
    PVPPaymentDialog(isPresented: .constant(true))
        .environmentObject(LanguageManager())
        .environmentObject(UserManager())
}
