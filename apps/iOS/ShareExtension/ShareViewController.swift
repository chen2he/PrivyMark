//
//  ShareViewController.swift
//  ShareExtension
//
//  PRD §7.7: the extension only RECEIVES the image and hands it off to the
//  main app via the App Group inbox — no scanning or rendering here
//  (extension memory budget is too small for Vision + 4K compositing).
//

import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    private let appGroupID = "group.jiamin.chen.PrivyMark"
    private let openURL = URL(string: "privymark://inbox")!

    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let openButton = UIButton(type: .system)
    private let doneButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        receiveImage()
    }

    // MARK: UI

    private func buildUI() {
        view.backgroundColor = .systemBackground

        let title = UILabel()
        title.text = "PrivyMark"
        title.font = .preferredFont(forTextStyle: .headline)

        statusLabel.text = "Receiving image…"
        statusLabel.font = .preferredFont(forTextStyle: .subheadline)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center

        spinner.startAnimating()

        openButton.setTitle("Open PrivyMark", for: .normal)
        openButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        openButton.isHidden = true
        openButton.addTarget(self, action: #selector(openMainApp), for: .touchUpInside)
        openButton.accessibilityLabel = "Open PrivyMark to review and redact"

        doneButton.setTitle("Done", for: .normal)
        doneButton.isHidden = true
        doneButton.addTarget(self, action: #selector(finish), for: .touchUpInside)
        doneButton.accessibilityLabel = "Close and return"

        let stack = UIStackView(arrangedSubviews: [title, spinner, statusLabel, openButton, doneButton])
        stack.axis = .vertical
        stack.spacing = 14
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])
    }

    private func showResult(success: Bool) {
        spinner.stopAnimating()
        spinner.isHidden = true
        if success {
            statusLabel.text = "Image received. Open PrivyMark to scan and redact it — everything stays on your device."
            openButton.isHidden = false
        } else {
            statusLabel.text = "Couldn't read that image. Please try another one."
        }
        doneButton.isHidden = false
    }

    // MARK: Receive → App Group inbox

    private func receiveImage() {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem])?
            .compactMap(\.attachments).flatMap { $0 } ?? []
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
        }) else {
            showResult(success: false)
            return
        }

        provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] url, _ in
            let handled: Bool
            if let url, let data = try? Data(contentsOf: url) {
                handled = self?.deposit(data, fileExtension: url.pathExtension) ?? false
            } else {
                handled = false
            }
            DispatchQueue.main.async {
                if handled {
                    self?.showResult(success: true)
                } else {
                    self?.receiveImageAsData(provider)
                }
            }
        }
    }

    /// Fallback for providers that don't offer a file representation.
    private func receiveImageAsData(_ provider: NSItemProvider) {
        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, _ in
            let handled = data.map { self?.deposit($0, fileExtension: "jpg") ?? false } ?? false
            DispatchQueue.main.async { self?.showResult(success: handled) }
        }
    }

    private func deposit(_ data: Data, fileExtension: String) -> Bool {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return false }
        let dir = container.appendingPathComponent("Inbox", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let ext = fileExtension.isEmpty ? "jpg" : fileExtension
            let url = dir.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    // MARK: Actions

    @objc private func openMainApp() {
        // Extensions can't call UIApplication.open directly; walk the
        // responder chain for the host's openURL: (standard workaround).
        let selector = sel_registerName("openURL:")
        var responder: UIResponder? = self
        while let current = responder {
            if current.responds(to: selector), !(current is UIViewController) {
                current.perform(selector, with: openURL)
                break
            }
            responder = current.next
        }
        finish()
    }

    @objc private func finish() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
