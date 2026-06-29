// main.swift
// ----------
// Điểm vào của app. Tạo NSApplication, gắn AppDelegate, chạy.
// App là "accessory" (LSUIElement) — không hiện trên Dock, chỉ có icon menu bar.

import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
