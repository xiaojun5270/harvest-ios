import SafariServices

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private static let messageKey = "message"

    func beginRequest(with context: NSExtensionContext) {
        guard let item = context.inputItems.first as? NSExtensionItem,
              let message = item.userInfo?[Self.messageKey] else {
            context.completeRequest(returningItems: [], completionHandler: nil)
            return
        }

        let response = NSExtensionItem()
        response.userInfo = [
            Self.messageKey: [
                "status": "ready",
                "message": message
            ]
        ]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
