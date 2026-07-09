//
//  SampleImage.swift
//  PrivyMark
//
//  Generates a sample screenshot with fake sensitive data so users can try
//  the scan flow without granting photo access (PRD §7.1 "尝试示例图片").
//

import UIKit

enum SampleImage {
    static func makeData() -> Data? {
        let size = CGSize(width: 1170, height: 1600)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            let title = "Invoice — ACME Store"
            let lines = [
                "Billed to: Michael Johnson",
                "Contact: john.doe@example.com",
                "Call +1 (555) 123-4567 today",
                "Ship to: 123 Main Street, Springfield",
                "Card: 4111 1111 1111 1111",
                "Order #: AB12345678",
            ]

            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 52),
                .foregroundColor: UIColor.black,
            ]
            title.draw(at: CGPoint(x: 80, y: 120), withAttributes: titleAttrs)

            let bodyAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 44),
                .foregroundColor: UIColor.black,
            ]
            var y: CGFloat = 300
            for line in lines {
                line.draw(at: CGPoint(x: 80, y: y), withAttributes: bodyAttrs)
                y += 130
            }
        }
        return image.pngData()
    }
}
