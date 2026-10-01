// cc-toast: a banner that stays as long as you ask. macOS banners go after ~5s and no API
// changes that, so this draws its own, styled like a native one but living in WezTerm:
// top right of its frontmost window under the tab bar, ordered just above that window so
// an app in front covers it, stacked by slot. No WezTerm window on screen: top right of
// the main screen. The countdown waits while WezTerm is not frontmost.
//
//   cc-toast --title T --body B [--seconds 20 | --sticky] [--pane P] [--colour #hex] [--quiet]
//
// Click: `wz go <pane>`, then WezTerm to the front. Hover holds the countdown and shows
// the close button. --colour tints the glass with the session's identity hue; --sticky has
// no countdown, and goes only once you are on its pane, click it, or its pane closes. Build: swiftc -O toast/cc-toast.swift -o bin/cc-toast (setup.sh)

import AppKit

struct Options {
	var title = ""
	var body = ""
	var seconds = 20.0
	var pane = ""
	var quiet = false
	var sticky = false
	var colour: NSColor?
}

func hexColour(_ text: String) -> NSColor? {
	let hex = text.hasPrefix("#") ? String(text.dropFirst()) : text
	guard hex.count == 6, let v = UInt32(hex, radix: 16) else { return nil }
	return NSColor(
		srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
		blue: CGFloat(v & 0xff) / 255, alpha: 1)
}

func parse() -> Options {
	var o = Options()
	var args = CommandLine.arguments.dropFirst().makeIterator()
	while let a = args.next() {
		switch a {
		case "--title": o.title = args.next() ?? ""
		case "--body": o.body = args.next() ?? ""
		case "--seconds": o.seconds = Double(args.next() ?? "") ?? o.seconds
		case "--pane": o.pane = args.next() ?? ""
		case "--quiet": o.quiet = true
		case "--sticky": o.sticky = true
		case "--colour": o.colour = hexColour(args.next() ?? "")
		default:
			FileHandle.standardError.write(
				("usage: cc-toast --title T --body B [--seconds S | --sticky] [--pane P] "
					+ "[--colour #hex] [--quiet]\n")
					.data(using: .utf8)!)
			exit(2)
		}
	}
	if o.title.isEmpty && o.body.isEmpty { exit(2) }
	return o
}

// Measured off native banners at 2x: 342 wide, 56 tall with one body line, 71 with two
let WIDTH: CGFloat = 344
let PAD: CGFloat = 12
let ICON: CGFloat = 32
let TEXT_X: CGFloat = PAD + ICON + 13
let RADIUS: CGFloat = 18
let RIGHT: CGFloat = 16
let TOP: CGFloat = 8
let GAP: CGFloat = 8
// inside a WezTerm window: the fancy tab bar is 26pt (measured), then this inset
let TAB_BAR: CGFloat = 26
let INSET: CGFloat = 12
let WEZTERM = "com.github.wez.wezterm"
// room round the banner for the close button, which overhangs its top-left corner
let BLEED: CGFloat = 10
let MAX_SLOTS = 8
// past this many on screen the oldest that is not sticky gives way
let MAX_SHOWN = 5
// how often a toast checks its pane still exists, so a sticky one cannot outlive it
let PANE_CHECK_SECONDS = 10.0

let titleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
let bodyFont = NSFont.systemFont(ofSize: 13, weight: .regular)

// One file per slot, "<pid> <height> <sticky 0|1> <started>"; O_EXCL claims it, a dead pid
// frees it. Every toast places itself below the live slots above it, so a closed one
// closes the gap
let slotDir = NSString(string: "~/.claude/cache/cc-toast").expandingTildeInPath
var slot = -1

func alive(_ text: String) -> Bool {
	guard let pid = Int32(text.split(separator: " ").first ?? "") else { return false }
	return kill(pid, 0) == 0 || errno != ESRCH
}

func claimSlot(height: CGFloat, sticky: Bool) -> Int {
	try? FileManager.default.createDirectory(
		atPath: slotDir, withIntermediateDirectories: true)
	let me = "\(getpid()) \(Int(height)) \(sticky ? 1 : 0) \(Int(Date().timeIntervalSince1970 * 1000))"
	for _ in 0..<2 {
		for n in 0..<MAX_SLOTS {
			let path = "\(slotDir)/\(n)"
			let fd = open(path, O_WRONLY | O_CREAT | O_EXCL, 0o644)
			if fd >= 0 {
				_ = me.withCString { write(fd, $0, strlen($0)) }
				close(fd)
				return n
			}
			if !alive((try? String(contentsOfFile: path, encoding: .utf8)) ?? "") {
				unlink(path)
			}
		}
	}
	return MAX_SLOTS - 1  // all taken: overlap the last rather than not show
}

func releaseSlot() {
	guard slot >= 0 else { return }
	let path = "\(slotDir)/\(slot)"
	if let owner = try? String(contentsOfFile: path, encoding: .utf8),
		owner.split(separator: " ").first == "\(getpid())"
	{
		unlink(path)
	}
}

func offsetAbove() -> CGFloat {
	var y: CGFloat = 0
	for n in 0..<max(slot, 0) {
		guard let text = try? String(contentsOfFile: "\(slotDir)/\(n)", encoding: .utf8),
			alive(text)
		else { continue }
		let h = text.split(separator: " ").dropFirst().first.flatMap { Double($0) } ?? 56
		y += CGFloat(h) + GAP
	}
	return y
}

/// Whether this toast is the oldest one that is not sticky while too many are showing
func shouldGiveWay() -> Bool {
	var live: [(pid: String, sticky: Bool, started: Int)] = []
	for n in 0..<MAX_SLOTS {
		guard let text = try? String(contentsOfFile: "\(slotDir)/\(n)", encoding: .utf8),
			alive(text)
		else { continue }
		let f = text.split(separator: " ").map(String.init)
		live.append((f[0], f.count > 2 && f[2] == "1", f.count > 3 ? Int(f[3]) ?? 0 : 0))
	}
	guard live.count > MAX_SHOWN,
		let oldest = live.filter({ !$0.sticky }).min(by: { $0.started < $1.started })
	else { return false }
	return oldest.pid == "\(getpid())"
}

func weztermBinary() -> String? {
	if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: WEZTERM) {
		let inApp = url.appendingPathComponent("Contents/MacOS/wezterm").path
		if FileManager.default.isExecutableFile(atPath: inApp) { return inApp }
	}
	for p in ["/opt/homebrew/bin/wezterm", "/usr/local/bin/wezterm"]
	where FileManager.default.isExecutableFile(atPath: p) {
		return p
	}
	return nil
}

/// false only when wezterm answers and the pane is not in its list; any doubt keeps it
func paneExists(_ pane: String) -> Bool {
	guard !pane.isEmpty, let bin = weztermBinary() else { return true }
	let p = Process()
	let out = Pipe()
	p.executableURL = URL(fileURLWithPath: bin)
	p.arguments = ["cli", "--no-auto-start", "list", "--format", "json"]
	p.standardOutput = out
	p.standardError = FileHandle.nullDevice
	guard (try? p.run()) != nil else { return true }
	let data = out.fileHandleForReading.readDataToEndOfFile()
	p.waitUntilExit()
	guard p.terminationStatus == 0,
		let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
		!list.isEmpty
	else { return true }
	return list.contains { "\($0["pane_id"] ?? "")" == pane }
}

// wezterm.lua's mirror of where you are: `focus\t<pane|->\t<looking 0|1>` on line one.
// Once you are on the toast's pane, by its key, a click or any other way, it has been seen
let paneRead = NSString(string: "~/.claude/cache/pane-read").expandingTildeInPath

func lookingAt(_ pane: String) -> Bool {
	guard !pane.isEmpty,
		let text = try? String(contentsOfFile: paneRead, encoding: .utf8),
		let line = text.split(separator: "\n").first
	else { return false }
	let f = line.split(separator: "\t").map(String.init)
	return f.count >= 3 && f[0] == "focus" && f[1] == pane && f[2] == "1"
}

/// The frontmost on-screen WezTerm window: its number and frame in Cocoa coordinates
func wezHost() -> (number: Int, frame: NSRect)? {
	guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: WEZTERM)
		.first?.processIdentifier,
		let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
			kCGNullWindowID) as? [[String: Any]],
		let primary = NSScreen.screens.first?.frame
	else { return nil }
	for w in list {  // front to back
		guard (w[kCGWindowOwnerPID as String] as? pid_t) == pid,
			(w[kCGWindowLayer as String] as? Int) == 0,
			let n = w[kCGWindowNumber as String] as? Int,
			let b = w[kCGWindowBounds as String] as? [String: CGFloat],
			let x = b["X"], let y = b["Y"], let wd = b["Width"], let h = b["Height"],
			wd > WIDTH + 2 * INSET, h > 120
		else { continue }
		return (n, NSRect(x: x, y: primary.maxY - y - h, width: wd, height: h))
	}
	return nil
}

/// Whether our panel already sits above `host` with nothing but other toasts between
func orderedAbove(_ mine: Int, _ host: Int) -> Bool {
	guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
		as? [[String: Any]]
	else { return false }
	var seenMine = false
	for w in list {
		let n = w[kCGWindowNumber as String] as? Int
		if n == mine { seenMine = true; continue }
		if n == host { return seenMine }
		if seenMine && (w[kCGWindowOwnerName as String] as? String) != "cc-toast" { return false }
	}
	return false
}

/// Written aside and renamed in, as wz queue_action does, so Lua never reads half a line
func queueJump(_ pane: String) -> Bool {
	let dir = NSString(string: "~/.claude/fleet/actions.d").expandingTildeInPath
	try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
	let name = "\(Int(Date().timeIntervalSince1970))-\(getpid())-\(Int.random(in: 0..<32768))"
	let tmp = "\(dir)/\(name).tmp"
	guard (try? "jump\t\(pane)\t\n".write(toFile: tmp, atomically: false, encoding: .utf8))
		!= nil
	else { return false }
	return rename(tmp, "\(dir)/\(name)") == 0
}

func appIcon() -> NSImage? {
	for id in ["com.github.wez.wezterm", "com.anthropic.claudefordesktop"] {
		if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
			return NSWorkspace.shared.icon(forFile: url.path)
		}
	}
	return nil
}

func label(_ text: String, _ font: NSFont, _ alpha: CGFloat, lines: Int) -> NSTextField {
	let f = NSTextField(wrappingLabelWithString: text)
	f.font = font
	f.textColor = NSColor.white.withAlphaComponent(alpha)
	f.maximumNumberOfLines = lines
	f.lineBreakMode = lines == 1 ? .byTruncatingTail : .byWordWrapping
	f.cell?.wraps = lines > 1
	f.cell?.truncatesLastVisibleLine = true
	f.isSelectable = false
	return f
}

final class Panel: NSPanel {
	override var canBecomeKey: Bool { false }
	override var canBecomeMain: Bool { false }
}

final class RootView: NSView {
	var onClick: () -> Void = {}
	var onHover: (Bool) -> Void = { _ in }
	var close: NSButton?

	override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

	// the labels would take the click otherwise; only the close button keeps its own
	override func hitTest(_ point: NSPoint) -> NSView? {
		guard let hit = super.hitTest(point) else { return nil }
		if let close, !close.isHidden, hit === close || hit.isDescendant(of: close) {
			return hit
		}
		return self
	}

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		trackingAreas.forEach(removeTrackingArea)
		addTrackingArea(
			NSTrackingArea(
				rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
				owner: self))
	}

	override func mouseEntered(with event: NSEvent) { onHover(true) }
	override func mouseExited(with event: NSEvent) { onHover(false) }
	override func mouseDown(with event: NSEvent) {}
	override func mouseUp(with event: NSEvent) { onClick() }
}

// The native close button: a small round blurred disc with an x, top-left, on hover
final class CloseButton: NSButton {
	override func draw(_ dirtyRect: NSRect) {
		let r = bounds.insetBy(dx: 0.5, dy: 0.5)
		NSColor(white: 0.24, alpha: 0.95).setFill()
		NSBezierPath(ovalIn: r).fill()
		NSColor.white.withAlphaComponent(0.14).setStroke()
		let ring = NSBezierPath(ovalIn: r)
		ring.lineWidth = 0.5
		ring.stroke()
		let x = NSBezierPath()
		let c = NSPoint(x: bounds.midX, y: bounds.midY)
		let d: CGFloat = 3.2
		x.move(to: NSPoint(x: c.x - d, y: c.y - d))
		x.line(to: NSPoint(x: c.x + d, y: c.y + d))
		x.move(to: NSPoint(x: c.x - d, y: c.y + d))
		x.line(to: NSPoint(x: c.x + d, y: c.y - d))
		x.lineWidth = 1.4
		x.lineCapStyle = .round
		NSColor.white.withAlphaComponent(0.8).setStroke()
		x.stroke()
	}
}

final class Toast: NSObject {
	let o: Options
	let panel: Panel
	let height: CGFloat
	let screen: NSScreen
	let close = CloseButton(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
	var left: Double
	var hovering = false
	var closing = false
	var timer: Timer?
	var seenTicks = 0
	var placedAt: CGFloat = -1
	var lastPaneCheck = Date()
	var host: (number: Int, frame: NSRect)?
	var ticks = 0

	init(_ o: Options) {
		self.o = o
		left = o.seconds
		// the fallback when no WezTerm window is on screen
		screen = NSScreen.screens.first ?? NSScreen.main!

		let textW = WIDTH - TEXT_X - PAD
		let title = label(o.title, titleFont, 0.9, lines: 1)
		if let c = o.colour {
			// the hue, lifted a little toward white: Mocha's accents are pastel already, so this
			// keeps the dark ones (mauve, blue) as readable as the pale ones on the glass
			title.textColor = c.blended(withFraction: 0.18, of: .white) ?? c
		}
		let body = label(o.body, bodyFont, 0.85, lines: 2)
		let titleH = ceil(title.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: textW, height: 100)).height)
		let bodyH =
			o.body.isEmpty
			? 0 : ceil(body.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: textW, height: 100)).height)
		let textH = titleH + (bodyH > 0 ? bodyH : 0)
		height = max(56, textH + 2 * 11)
		slot = claimSlot(height: height, sticky: o.sticky)

		panel = Panel(
			contentRect: NSRect(x: 0, y: 0, width: WIDTH + 2 * BLEED, height: height + 2 * BLEED),
			styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
		super.init()

		// normal level: it belongs to WezTerm's layer, so whatever covers WezTerm covers it
		panel.isFloatingPanel = false
		panel.level = .normal
		panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
		panel.hidesOnDeactivate = false
		panel.becomesKeyOnlyIfNeeded = true
		panel.isOpaque = false
		panel.backgroundColor = .clear
		panel.hasShadow = true
		panel.appearance = NSAppearance(named: .darkAqua)

		let root = RootView(frame: NSRect(origin: .zero, size: panel.frame.size))
		root.onClick = { [unowned self] in self.clicked() }
		root.onHover = { [unowned self] in self.hover($0) }
		root.close = close

		let banner = NSRect(x: BLEED, y: BLEED, width: WIDTH, height: height)
		let glass = NSVisualEffectView(frame: banner)
		glass.material = .popover
		glass.blendingMode = .behindWindow
		glass.state = .active
		glass.maskImage = NSImage(size: banner.size, flipped: false) { r in
			NSColor.black.setFill()
			NSBezierPath(roundedRect: r, xRadius: RADIUS, yRadius: RADIUS).fill()
			return true
		}
		glass.maskImage?.capInsets = NSEdgeInsets(
			top: RADIUS, left: RADIUS, bottom: RADIUS, right: RADIUS)
		root.addSubview(glass)

		// Tint over the blur, not instead of it: strongest at the leading edge and fading
		// across, so the glass still reads as glass and the text sits on the quieter end
		if let c = o.colour {
			let wash = NSView(frame: banner)
			wash.wantsLayer = true
			wash.layer?.cornerRadius = RADIUS
			wash.layer?.cornerCurve = .continuous
			wash.layer?.masksToBounds = true
			let g = CAGradientLayer()
			g.frame = wash.bounds
			g.startPoint = CGPoint(x: 0, y: 0.5)
			g.endPoint = CGPoint(x: 1, y: 0.5)
			g.colors = [c.withAlphaComponent(0.26).cgColor, c.withAlphaComponent(0.08).cgColor]
			wash.layer?.addSublayer(g)
			let edge = CALayer()
			edge.frame = CGRect(x: 0, y: 0, width: 3, height: banner.height)
			edge.backgroundColor = c.withAlphaComponent(0.85).cgColor
			wash.layer?.addSublayer(edge)
			root.addSubview(wash)
		}

		let rim = NSView(frame: banner)
		rim.wantsLayer = true
		rim.layer?.cornerRadius = RADIUS
		rim.layer?.cornerCurve = .continuous
		rim.layer?.borderWidth = 0.5
		rim.layer?.borderColor = (o.colour?.withAlphaComponent(0.35) ?? NSColor.white.withAlphaComponent(0.2)).cgColor
		root.addSubview(rim)

		// a sticky toast waits for you: a small pin of a dot, top right, says so
		if o.sticky {
			let d: CGFloat = 7
			let dot = NSView(
				frame: NSRect(x: BLEED + WIDTH - PAD - d, y: BLEED + height - PAD - d, width: d, height: d))
			dot.wantsLayer = true
			dot.layer?.cornerRadius = d / 2
			dot.layer?.backgroundColor = (o.colour ?? NSColor.white.withAlphaComponent(0.7)).cgColor
			root.addSubview(dot)
		}

		if let img = appIcon() {
			let icon = NSImageView(
				frame: NSRect(x: BLEED + PAD, y: BLEED + (height - ICON) / 2, width: ICON, height: ICON))
			icon.image = img
			icon.imageScaling = .scaleProportionallyUpOrDown
			root.addSubview(icon)
		}

		let top = BLEED + (height + textH) / 2
		title.frame = NSRect(x: BLEED + TEXT_X, y: top - titleH, width: textW, height: titleH)
		body.frame = NSRect(x: BLEED + TEXT_X, y: top - titleH - bodyH, width: textW, height: bodyH)
		root.addSubview(title)
		if bodyH > 0 { root.addSubview(body) }

		close.isBordered = false
		close.title = ""
		close.target = self
		close.action = #selector(dismiss)
		close.frame.origin = NSPoint(x: BLEED - 6, y: BLEED + height - 14)
		close.isHidden = true
		root.addSubview(close)

		panel.contentView = root
		panel.alphaValue = 0  // place() orders it in; show() fades it up
		place(animated: false)
	}

	func frameFor(offset: CGFloat) -> NSRect {
		let size = NSSize(width: WIDTH + 2 * BLEED, height: height + 2 * BLEED)
		if let h = host?.frame {
			return NSRect(
				origin: NSPoint(
					x: h.maxX - INSET - WIDTH - BLEED,
					y: h.maxY - TAB_BAR - INSET - offset - height - BLEED), size: size)
		}
		let vf = screen.visibleFrame
		return NSRect(
			origin: NSPoint(
				x: vf.maxX - RIGHT - WIDTH - BLEED, y: vf.maxY - TOP - offset - height - BLEED),
			size: size)
	}

	/// Every 0.2s: find WezTerm's window, follow it, stay just above it in the stack
	func place(animated: Bool) {
		var moved = false
		if ticks % 2 == 0 {
			let found = wezHost()
			moved = found?.frame != host?.frame || found?.number != host?.number
			host = found
			if let h = host {
				if !orderedAbove(panel.windowNumber, h.number) {
					panel.order(.above, relativeTo: h.number)
				}
			} else if !panel.isVisible || moved {
				panel.orderFrontRegardless()
			}
		}
		ticks += 1
		let off = offsetAbove()
		if off == placedAt && !moved { return }
		let stackOnly = !moved
		placedAt = off
		if animated && stackOnly {
			NSAnimationContext.runAnimationGroup {
				$0.duration = 0.25
				panel.animator().setFrame(frameFor(offset: off), display: true)
			}
		} else {
			panel.setFrame(frameFor(offset: off), display: true)
		}
	}

	/// Out of sight while another app is in front: hold the countdown so it gets its time
	var unseen: Bool {
		host != nil && NSWorkspace.shared.frontmostApplication?.bundleIdentifier != WEZTERM
	}

	func show() {
		// slide in from the right edge, as native banners do
		let end = panel.frame
		panel.setFrame(end.offsetBy(dx: 24, dy: 0), display: false)
		panel.alphaValue = 0
		if let h = host {
			panel.order(.above, relativeTo: h.number)
		} else {
			panel.orderFrontRegardless()
		}
		panel.invalidateShadow()
		NSAnimationContext.runAnimationGroup {
			$0.duration = 0.2
			$0.timingFunction = CAMediaTimingFunction(name: .easeOut)
			panel.animator().setFrame(end, display: true)
			panel.animator().alphaValue = 1
		}
		if !o.quiet { NSSound(named: "Glass")?.play() }
		timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [unowned self] _ in
			if self.closing { return }
			self.place(animated: true)
			self.seenTicks += 1
			if lookingAt(self.o.pane) || (self.seenTicks % 5 == 0 && shouldGiveWay()) {
				self.dismiss()
				return
			}
			// a CLI round trip: off the main thread, or every toast hitches each check
			if Date().timeIntervalSince(self.lastPaneCheck) >= PANE_CHECK_SECONDS {
				self.lastPaneCheck = Date()
				let pane = self.o.pane
				DispatchQueue.global(qos: .utility).async {
					if !paneExists(pane) {
						DispatchQueue.main.async { self.dismiss() }
					}
				}
			}
			if self.o.sticky || self.hovering || self.unseen { return }
			self.left -= 0.1
			if self.left <= 0 { self.dismiss() }
		}
	}

	func hover(_ on: Bool) {
		hovering = on
		close.isHidden = !on
	}

	// The jump is a `jump` line queued straight into actions.d, which wezterm.lua drains
	// every 0.1s and runs in-process: no wz go, no CLI round trips. wz go only if that fails
	func clicked() {
		if !o.pane.isEmpty && queueJump(o.pane) {
			NSRunningApplication.runningApplications(withBundleIdentifier: WEZTERM)
				.first?.activate()
		} else if !o.pane.isEmpty {
			let wz = Process()
			wz.executableURL = URL(
				fileURLWithPath: NSString(string: "~/.claude/bin/wz").expandingTildeInPath)
			wz.arguments = ["go", o.pane]
			wz.standardOutput = FileHandle.nullDevice
			wz.standardError = FileHandle.nullDevice
			try? wz.run()
			NSRunningApplication.runningApplications(withBundleIdentifier: WEZTERM)
				.first?.activate()
		}
		dismiss()
	}

	@objc func dismiss() {
		if closing { return }
		closing = true
		timer?.invalidate()
		NSAnimationContext.runAnimationGroup(
			{
				$0.duration = 0.18
				$0.timingFunction = CAMediaTimingFunction(name: .easeIn)
				panel.animator().setFrame(panel.frame.offsetBy(dx: 24, dy: 0), display: true)
				panel.animator().alphaValue = 0
			},
			completionHandler: {
				releaseSlot()
				exit(0)
			})
	}
}

let opts = parse()
signal(SIGTERM) { _ in
	releaseSlot()
	exit(0)
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let toast = Toast(opts)
toast.show()
app.run()
