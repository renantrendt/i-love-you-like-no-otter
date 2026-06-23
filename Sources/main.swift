import AppKit
import CoreImage
import ServiceManagement

// MARK: - Otter image

func loadFrame(_ name: String) -> NSImage {
    if let url = Bundle.main.url(forResource: name, withExtension: "png"),
       let img = NSImage(contentsOf: url) { return img }
    // Fallback so the app still runs if a resource is missing.
    return NSImage(size: NSSize(width: 227, height: 236))
}
let FRAMES = [loadFrame("frame0"), loadFrame("frame1")]   // the Piskel animation frames
let OTTER = FRAMES[0]   // representative frame for the menu-bar icon, aspect, and dissolve
let OTTER_ASPECT: CGFloat = OTTER.size.width > 0 ? OTTER.size.height / OTTER.size.width : 236.0 / 227.0
let FRAME_INTERVAL: TimeInterval = 0.25   // 4 fps, from the Piskel file

// Dog yip when the buddy appears; otter chirp when it's clicked to fade away.
func loadSound(_ name: String) -> NSSound? {
    if let url = Bundle.main.url(forResource: name, withExtension: "wav") {
        return NSSound(contentsOf: url, byReference: true)
    }
    return nil
}
let BARK = loadSound("bark")
let OTTER_CHIRP = loadSound("otter")
func play(_ sound: NSSound?) {
    guard Settings.shared.sound else { return }
    sound?.stop()   // restart from the top if it's still ringing out
    sound?.play()
}

func otterIcon(height: CGFloat) -> NSImage {
    let aspect = OTTER.size.height > 0 ? OTTER.size.width / OTTER.size.height : 143.0 / 213.0
    let w = max(1, height * aspect)
    let img = NSImage(size: NSSize(width: w, height: height))
    img.lockFocus()
    OTTER.draw(in: NSRect(x: 0, y: 0, width: w, height: height),
               from: .zero, operation: .sourceOver, fraction: 1)
    img.unlockFocus()
    return img
}

// Pixelate the otter to a given block size (in source-image pixels), keeping transparency.
let ciContext = CIContext(options: nil)
func pixelated(_ src: NSImage, scale: CGFloat) -> NSImage {
    guard let tiff = src.tiffRepresentation,
          let ci = CIImage(data: tiff),
          let filter = CIFilter(name: "CIPixellate") else { return src }
    let extent = ci.extent
    filter.setValue(ci, forKey: kCIInputImageKey)
    filter.setValue(CIVector(x: extent.midX, y: extent.midY), forKey: kCIInputCenterKey)
    filter.setValue(max(1, scale), forKey: kCIInputScaleKey)
    guard let out = filter.outputImage?.cropped(to: extent),
          let cg = ciContext.createCGImage(out, from: extent) else { return src }
    return NSImage(cgImage: cg, size: NSSize(width: extent.width, height: extent.height))
}

// MARK: - Settings

final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard

    private func reg() {
        d.register(defaults: [
            "interval": 30,
            "startMin": 0,
            "endMin": 1439,                                       // 00:00–23:59, all day
            "days": [true, true, true, true, true, true, true],   // every day
            "placement": 0,
            "size": 110,
            "sound": true
        ])
    }
    init() { reg() }

    var interval: Int { get { d.integer(forKey: "interval") } set { d.set(newValue, forKey: "interval") } }
    var startMin: Int { get { d.integer(forKey: "startMin") } set { d.set(newValue, forKey: "startMin") } }
    var endMin: Int { get { d.integer(forKey: "endMin") } set { d.set(newValue, forKey: "endMin") } }
    var days: [Bool] {
        get { (d.array(forKey: "days") as? [Bool]) ?? [true, true, true, true, true, false, false] }
        set { d.set(newValue, forKey: "days") }
    }
    var placement: Int { get { d.integer(forKey: "placement") } set { d.set(newValue, forKey: "placement") } }
    var size: Int { get { max(60, d.integer(forKey: "size")) } set { d.set(newValue, forKey: "size") } }
    var sound: Bool { get { d.bool(forKey: "sound") } set { d.set(newValue, forKey: "sound") } }
    var hasDrop: Bool { d.bool(forKey: "hasDrop") }
    var lastDrop: NSPoint {
        get { NSPoint(x: d.double(forKey: "lastDropX"), y: d.double(forKey: "lastDropY")) }
        set {
            d.set(newValue.x, forKey: "lastDropX")
            d.set(newValue.y, forKey: "lastDropY")
            d.set(true, forKey: "hasDrop")
        }
    }

    // Weekday: Calendar uses 1=Sun..7=Sat. Our array is 0=Mon..6=Sun.
    func isActiveDay(_ date: Date) -> Bool {
        let wd = Calendar.current.component(.weekday, from: date) // 1=Sun
        let idx = (wd + 5) % 7 // Sun(1)->6, Mon(2)->0 ... Sat(7)->5
        return days[idx]
    }
    func minutesOfDay(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
    func isActiveNow(_ date: Date = Date()) -> Bool {
        guard isActiveDay(date) else { return false }
        let m = minutesOfDay(date)
        if startMin <= endMin { return m >= startMin && m < endMin }
        return m >= startMin || m < endMin // overnight window
    }
}

// MARK: - Buddy view + window

final class BuddyView: NSView {
    var image: NSImage?
    var onClick: (() -> Void)?
    private var downScreen: NSPoint = .zero
    private var originAtDown: NSPoint = .zero
    private var dragDistance: CGFloat = 0
    override var isFlipped: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        image?.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
    }
    override func mouseDown(with event: NSEvent) {
        downScreen = NSEvent.mouseLocation
        originAtDown = window?.frame.origin ?? .zero
        dragDistance = 0
        NSCursor.closedHand.set()
    }
    override func mouseDragged(with event: NSEvent) {
        guard let win = window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - downScreen.x
        let dy = now.y - downScreen.y
        dragDistance = max(dragDistance, hypot(dx, dy))
        win.setFrameOrigin(NSPoint(x: originAtDown.x + dx, y: originAtDown.y + dy))
    }
    override func mouseUp(with event: NSEvent) {
        NSCursor.openHand.set()
        if dragDistance < 4 {
            onClick?()                       // a real click → dismiss
        } else if let win = window {
            // dragged → remember the spot and make it stick on future appearances
            Settings.shared.lastDrop = win.frame.origin
            Settings.shared.placement = 3
        }
    }
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}

final class BuddyController {
    private var window: NSWindow?
    private var view: BuddyView?
    private var dismissTimer: Timer?
    private var frameTimer: Timer?
    private var frameIndex = 0
    var isVisible: Bool { window?.isVisible ?? false }
    var onDismiss: (() -> Void)?

    func show() {
        if isVisible { return }
        let frame = targetFrame(width: CGFloat(Settings.shared.size))

        let win = NSWindow(contentRect: frame, styleMask: .borderless,
                           backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.level = .floating
        win.ignoresMouseEvents = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let v = BuddyView(frame: NSRect(origin: .zero, size: frame.size))
        v.image = FRAMES[0]
        v.onClick = { [weak self] in self?.dismiss() }
        win.contentView = v
        self.view = v
        self.window = win
        startCycling()

        // Pop-in: fade + slide up
        win.alphaValue = 0
        var start = frame
        start.origin.y -= 14
        win.setFrame(start, display: false)
        win.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            win.animator().alphaValue = 1
            win.animator().setFrame(frame, display: true)
        }
        play(BARK)   // dog yips on arrival
    }

    private func startCycling() {
        frameIndex = 0
        let t = Timer(timeInterval: FRAME_INTERVAL, repeats: true) { [weak self] _ in
            guard let self = self, let v = self.view else { return }
            self.frameIndex = (self.frameIndex + 1) % FRAMES.count
            v.image = FRAMES[self.frameIndex]
            v.needsDisplay = true
        }
        RunLoop.main.add(t, forMode: .common)
        frameTimer = t
    }

    private func stopCycling() {
        frameTimer?.invalidate()
        frameTimer = nil
    }

    // Click → pixel-dissolve: the otter breaks into growing blocks while fading out.
    private func dismiss() {
        guard let win = window, let v = view else { return }
        dismissTimer?.invalidate()
        stopCycling()
        play(OTTER_CHIRP ?? BARK)   // otter chirps as it fades (falls back to the yip if no chirp is bundled)
        let dissolveBase = FRAMES[frameIndex]   // dissolve whichever frame is showing
        let duration: TimeInterval = 0.7
        let startTime = Date()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            var p = Date().timeIntervalSince(startTime) / duration
            if p > 1 { p = 1 }
            let scale = 1 + p * p * 22            // block size grows toward the end
            win.alphaValue = max(0, 1 - pow(p, 1.8))
            v.image = pixelated(dissolveBase, scale: CGFloat(scale))
            v.needsDisplay = true
            if p >= 1 {
                t.invalidate()
                self.dismissTimer = nil
                win.orderOut(nil)
                self.window = nil
                self.view = nil
                self.onDismiss?()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        dismissTimer = timer
    }

    func hideImmediately() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        stopCycling()
        window?.orderOut(nil)
        window = nil
        view = nil
    }

    private func targetFrame(width: CGFloat) -> NSRect {
        let size = width
        let h = width * OTTER_ASPECT
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let vf = screen.visibleFrame
        let margin: CGFloat = 24
        func rand(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + CGFloat(Double.random(in: 0...1)) * (b - a) }
        func clamp(_ p: NSPoint) -> NSRect {
            let x = min(max(vf.minX + margin, p.x), vf.maxX - size - margin)
            let y = min(max(vf.minY + margin, p.y), vf.maxY - h - margin)
            return NSRect(x: x, y: y, width: size, height: h)
        }
        switch Settings.shared.placement {
        case 3: // where I last left it
            if Settings.shared.hasDrop { return clamp(Settings.shared.lastDrop) }
            return clamp(NSPoint(x: vf.maxX - size - margin, y: vf.minY + margin))
        case 1: // random spot
            let x = rand(vf.minX + margin, vf.maxX - size - margin)
            let y = rand(vf.minY + margin, vf.maxY - h - margin)
            return NSRect(x: x, y: y, width: size, height: h)
        case 2: // near cursor
            let p = NSEvent.mouseLocation
            var x = p.x + 18, y = p.y - h - 18
            x = min(max(vf.minX + margin, x), vf.maxX - size - margin)
            y = min(max(vf.minY + margin, y), vf.maxY - h - margin)
            return NSRect(x: x, y: y, width: size, height: h)
        default: // bottom-right with jitter
            let x = vf.maxX - size - margin - rand(0, 40)
            let y = vf.minY + margin + rand(0, 40)
            return NSRect(x: x, y: y, width: size, height: h)
        }
    }
}

// MARK: - Preferences window

final class PreferencesController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var sizeLabel: NSTextField?
    private let dayTitles = ["M", "T", "W", "T", "F", "S", "S"]
    private var dayButtons: [NSButton] = []

    func show() {
        if window == nil { build() }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    private func label(_ text: String, _ frame: NSRect) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.frame = frame
        l.textColor = .secondaryLabelColor
        return l
    }

    private func build() {
        let w: CGFloat = 400, h: CGFloat = 320
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                           styleMask: [.titled, .closable],
                           backing: .buffered, defer: false)
        win.title = "I love you like no otter — Preferences"
        win.isReleasedWhenClosed = false
        win.delegate = self
        let c = win.contentView!
        let s = Settings.shared

        func rowY(_ i: Int) -> CGFloat { h - 44 - CGFloat(i) * 42 }
        let labelX: CGFloat = 22, labelW: CGFloat = 118, ctrlX: CGFloat = 148

        // Remind me every
        c.addSubview(label("Remind me every", NSRect(x: labelX, y: rowY(0), width: labelW, height: 22)))
        let intervalPop = NSPopUpButton(frame: NSRect(x: ctrlX, y: rowY(0) - 3, width: 140, height: 26))
        let intervals = [20, 30, 45, 60]
        intervalPop.addItems(withTitles: intervals.map { $0 == 60 ? "1 hour" : "\($0) minutes" })
        intervalPop.selectItem(at: intervals.firstIndex(of: s.interval) ?? 1)
        intervalPop.target = self; intervalPop.action = #selector(intervalChanged(_:))
        c.addSubview(intervalPop)

        // Active hours
        c.addSubview(label("Active hours", NSRect(x: labelX, y: rowY(1), width: labelW, height: 22)))
        let startPicker = timePicker(min: s.startMin, x: ctrlX, y: rowY(1) - 3, tag: 1)
        let toLabel = label("to", NSRect(x: ctrlX + 86, y: rowY(1), width: 22, height: 22))
        let endPicker = timePicker(min: s.endMin, x: ctrlX + 110, y: rowY(1) - 3, tag: 2)
        c.addSubview(startPicker); c.addSubview(toLabel); c.addSubview(endPicker)

        // Active days
        c.addSubview(label("Active days", NSRect(x: labelX, y: rowY(2), width: labelW, height: 22)))
        for i in 0..<7 {
            let b = NSButton(frame: NSRect(x: ctrlX + CGFloat(i) * 32, y: rowY(2) - 4, width: 30, height: 30))
            b.setButtonType(.pushOnPushOff)
            b.bezelStyle = .rounded
            b.title = dayTitles[i]
            b.state = s.days[i] ? .on : .off
            b.tag = i
            b.target = self; b.action = #selector(dayToggled(_:))
            dayButtons.append(b)
            c.addSubview(b)
        }

        // Appears
        c.addSubview(label("Appears", NSRect(x: labelX, y: rowY(3), width: labelW, height: 22)))
        let placePop = NSPopUpButton(frame: NSRect(x: ctrlX, y: rowY(3) - 3, width: 180, height: 26))
        placePop.addItems(withTitles: ["Bottom-right corner", "Random spot", "Near the cursor", "Where I last left it"])
        placePop.selectItem(at: s.placement)
        placePop.target = self; placePop.action = #selector(placeChanged(_:))
        c.addSubview(placePop)

        // Buddy size
        c.addSubview(label("Buddy size", NSRect(x: labelX, y: rowY(4), width: labelW, height: 22)))
        let slider = NSSlider(frame: NSRect(x: ctrlX, y: rowY(4) - 2, width: 150, height: 24))
        slider.minValue = 60; slider.maxValue = 160; slider.doubleValue = Double(s.size)
        slider.target = self; slider.action = #selector(sizeChanged(_:))
        c.addSubview(slider)
        let sl = label("\(s.size)px", NSRect(x: ctrlX + 158, y: rowY(4), width: 50, height: 22))
        sizeLabel = sl; c.addSubview(sl)

        // Sound
        let soundBox = NSButton(checkboxWithTitle: "Bark when it appears", target: self, action: #selector(soundToggled(_:)))
        soundBox.frame = NSRect(x: ctrlX, y: rowY(5) - 2, width: 240, height: 22)
        soundBox.state = s.sound ? .on : .off
        c.addSubview(soundBox)

        self.window = win
    }

    private func timePicker(min: Int, x: CGFloat, y: CGFloat, tag: Int) -> NSDatePicker {
        let p = NSDatePicker(frame: NSRect(x: x, y: y, width: 80, height: 26))
        p.datePickerStyle = .textFieldAndStepper
        p.datePickerElements = .hourMinute
        var comp = DateComponents(); comp.hour = min / 60; comp.minute = min % 60
        p.dateValue = Calendar.current.date(from: comp) ?? Date()
        p.tag = tag
        p.target = self; p.action = #selector(timeChanged(_:))
        return p
    }

    @objc private func intervalChanged(_ s: NSPopUpButton) {
        let intervals = [20, 30, 45, 60]
        Settings.shared.interval = intervals[s.indexOfSelectedItem]
        AppState.shared?.rescheduleFromNow()
    }
    @objc private func timeChanged(_ p: NSDatePicker) {
        let m = Settings.shared.minutesOfDay(p.dateValue)
        if p.tag == 1 { Settings.shared.startMin = m } else { Settings.shared.endMin = m }
    }
    @objc private func dayToggled(_ b: NSButton) {
        var d = Settings.shared.days
        d[b.tag] = (b.state == .on)
        Settings.shared.days = d
    }
    @objc private func placeChanged(_ s: NSPopUpButton) { Settings.shared.placement = s.indexOfSelectedItem }
    @objc private func sizeChanged(_ s: NSSlider) {
        Settings.shared.size = Int(s.doubleValue.rounded())
        sizeLabel?.stringValue = "\(Settings.shared.size)px"
    }
    @objc private func soundToggled(_ b: NSButton) { Settings.shared.sound = (b.state == .on) }
}

// MARK: - App

final class AppState {
    static var shared: AppDelegate?
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let buddy = BuddyController()
    private let prefs = PreferencesController()
    private var ticker: Timer?
    private var menuTimer: Timer?
    private var nextNudge = Date().addingTimeInterval(3)   // first appearance ~3s after launch
    private var pausedUntil: Date?
    private var statusLine: NSMenuItem!
    private var launchItem: NSMenuItem!

    func applicationDidFinishLaunching(_ note: Notification) {
        AppState.shared = self
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            btn.image = otterIcon(height: 18)
            btn.imagePosition = .imageOnly
        }
        buildMenu()
        buddy.onDismiss = { [weak self] in self?.rescheduleFromNow() }
        ticker = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(ticker!, forMode: .common)
        tick()
    }

    private func buildMenu() {
        let menu = NSMenu()
        let title = NSMenuItem(title: "I love you like no otter", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        statusLine = NSMenuItem(title: "—", action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Show otter now", action: #selector(showNow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Snooze 15 min", action: #selector(snooze), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Pause for today", action: #selector(pauseToday), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Preferences…", action: #selector(openPrefs), keyEquivalent: ","))
        launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchItem)
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items where item.action != nil { item.target = self }
        menu.delegate = self
        statusItem.menu = menu
    }

    // Live-refresh the countdown once per second while the menu is open.
    func menuWillOpen(_ menu: NSMenu) {
        updateStatus()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.updateStatus() }
        RunLoop.main.add(t, forMode: .common)   // .common so it fires during menu tracking
        menuTimer = t
    }
    func menuDidClose(_ menu: NSMenu) {
        menuTimer?.invalidate()
        menuTimer = nil
    }

    func rescheduleFromNow() {
        nextNudge = Date().addingTimeInterval(TimeInterval(Settings.shared.interval * 60))
        updateStatus()
    }

    private func tick() {
        let now = Date()
        if let until = pausedUntil, now >= until { pausedUntil = nil }
        if pausedUntil == nil, Settings.shared.isActiveNow(now),
           now >= nextNudge, !buddy.isVisible {
            buddy.show()
            nextNudge = now.addingTimeInterval(TimeInterval(Settings.shared.interval * 60))
        }
        updateStatus()
    }

    private func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded()))
        if s >= 3600 { return String(format: "%dh %02dm", s / 3600, (s % 3600) / 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    // The next moment the active window opens, scanning up to a week ahead.
    private func nextActiveStart(after date: Date) -> Date {
        let cal = Calendar.current
        let s = Settings.shared
        for offset in 0...8 {
            guard let day = cal.date(byAdding: .day, value: offset, to: date), s.isActiveDay(day) else { continue }
            let start = cal.startOfDay(for: day).addingTimeInterval(TimeInterval(s.startMin * 60))
            if start >= date { return start }
        }
        return date
    }

    private func updateStatus() {
        if let until = pausedUntil {
            statusLine.title = "⏸ Paused — \(clock(until.timeIntervalSinceNow)) left"
        } else if !Settings.shared.isActiveNow() {
            let when = nextActiveStart(after: Date())
            statusLine.title = "Sleeping — wakes in \(clock(when.timeIntervalSinceNow))"
        } else if buddy.isVisible {
            statusLine.title = "Otter is on screen — click it!"
        } else {
            let remaining = nextNudge.timeIntervalSinceNow
            statusLine.title = remaining <= 0 ? "Nudging now…" : "Next otter in \(clock(remaining))"
        }
    }

    @objc private func showNow() { buddy.show() }
    @objc private func snooze() {
        buddy.hideImmediately()
        nextNudge = Date().addingTimeInterval(15 * 60)
        updateStatus()
    }
    @objc private func pauseToday() {
        buddy.hideImmediately()
        let cal = Calendar.current
        pausedUntil = cal.startOfDay(for: Date().addingTimeInterval(86400)) // next midnight
        updateStatus()
    }
    @objc private func openPrefs() { prefs.show() }
    @objc private func toggleLaunchAtLogin() {
        let svc = SMAppService.mainApp
        do {
            if svc.status == .enabled { try svc.unregister() } else { try svc.register() }
        } catch {}
        launchItem.state = svc.status == .enabled ? .on : .off
    }
    @objc private func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
