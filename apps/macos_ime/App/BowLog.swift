// BowLog.swift
// ------------
// Log chẩn đoán của bộ gõ, ĐỌC ĐƯỢC trong Console.app / `log show`.
//
// VÌ SAO KHÔNG NSLog? Trên macOS mới, nội dung NSLog của app được ghi vào unified
// log dưới dạng "<private>" — dòng có ghi nhưng không ai đọc được nội dung, nên khi
// người dùng báo lỗi (vd "bấm phím tắt chụp màn hình không thấy gì") không có gì để
// chẩn đoán. Log ở đây đánh dấu PUBLIC. Không bao giờ ghi nội dung người dùng gõ.
//
// Xem:  log show --last 10m --predicate 'subsystem == "com.bowgo.keyboard"'

import os

private let logger = Logger(subsystem: "com.bowgo.keyboard", category: "app")

func bowLog(_ message: String) {
    logger.notice("\(message, privacy: .public)")
}
