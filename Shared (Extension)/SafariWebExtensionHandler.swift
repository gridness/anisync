//
//  SafariWebExtensionHandler.swift
//  Shared (Extension)
//
//  Created by Ivan King on 29.08.2026.
//

import SafariServices
import os

class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private let service = AniSyncService()
    private let logger = Logger(subsystem: "me.heeka.anisync", category: "NativeMessaging")

    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem
        let message = request?.userInfo?[SFExtensionMessageKey] as? [String: Any] ?? [:]
        let command = message["command"] as? String ?? "invalid"
        logger.info("Handling native command: \(command, privacy: .public)")

        Task {
            let payload = await service.handleNativeMessage(message)
            let response = NSExtensionItem()
            response.userInfo = [SFExtensionMessageKey: payload]
            context.completeRequest(returningItems: [response], completionHandler: nil)
        }
    }
}
