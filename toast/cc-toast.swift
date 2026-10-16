// cc-toast: a banner that stays as long as you ask. macOS banners go after ~5s and no API
// changes that, so this draws its own, styled like a native one but living in WezTerm:
// top right of its frontmost window under the tab bar, ordered just above that window so
// an app in front covers it, stacked by rank, highest on top. No WezTerm window on screen:
// top right of the main screen. The countdown waits while WezTerm is not frontmost, and while nothing
// has been touched for AWAY_SECONDS (walked away, locked, asleep).
//
//   cc-toast --title T --body B [--seconds 20 | --sticky] [--pane P] [--colour #hex]
//            [--rank R] [--compact] [--quiet]
//
// Click: `wz go <pane>`, then WezTerm to the front. Hover holds the countdown and shows
// the close button. --colour tints the glass with the session's identity hue; --sticky has
// no countdown, and goes only once you are on its pane, click it, or its pane closes.
// The stack is in LEADER+t's order (wezterm.lua's kev-pick); --rank (0-1, default 0.5)
// stands in when that does not list the pane, and decides the shimmer and the breathing. --compact is a one-line pill that opens to the full toast on hover.
// Build: swiftc -O toast/cc-toast.swift -o bin/cc-toast (setup.sh)

import AppKit

struct Options {
	var title = ""
	var body = ""
	var seconds = 20.0
	var pane = ""
	var quiet = false
	var sticky = false
	var compact = false
	var rank = 0.5
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
		case "--compact": o.compact = true
		case "--rank": o.rank = min(max(Double(args.next() ?? "") ?? o.rank, 0), 1)
		case "--colour": o.colour = hexColour(args.next() ?? "")
		default:
			FileHandle.standardError.write(
				("usage: cc-toast --title T --body B [--seconds S | --sticky] [--pane P] "
					+ "[--colour #hex] [--rank R] [--compact] [--quiet]\n")
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
let MAX_SLOTS = 12
// past this many on screen the last in the order gives way, one that is not sticky first
let MAX_SHOWN = 5
let COMPACT_H: CGFloat = 36
let COMPACT_ICON: CGFloat = 18
// from here a toast shimmers as it lands; from PULSE a sticky one's dot and edge breathe
let SHIMMER_RANK = 0.5
let PULSE_RANK = 0.6
// Posted whenever a slot changes, so every toast restacks on the same frame rather than on
// its next 0.1s tick, one after another
let STACK_NOTE = "net.smart-numbers.cc-toast.stack" as CFString

func announce() {
	CFNotificationCenterPostNotification(
		CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(STACK_NOTE), nil, nil,
		true)
}

/// A damped spring stepped every display frame. Retargeting keeps its velocity, so a
/// reorder landing mid-glide bends the path instead of restarting a fixed-length curve
struct Spring {
	var value: CGFloat
	var target: CGFloat
	var velocity: CGFloat = 0
	// seconds for one undamped swing; 1 is critically damped, below it overshoots
	var response: CGFloat = 0.4
	var damping: CGFloat = 0.8
	let epsilon: CGFloat

	init(_ v: CGFloat, epsilon: CGFloat = 0.1) {
		value = v
		target = v
		self.epsilon = epsilon
	}

	mutating func aim(_ t: CGFloat, response r: CGFloat, damping d: CGFloat) {
		target = t
		response = r
		damping = d
	}

	mutating func snap(_ v: CGFloat) {
		value = v
		target = v
		velocity = 0
	}

	mutating func step(_ dt: CGFloat) {
		let k = pow(2 * .pi / response, 2)
		let c = 4 * .pi * damping / response
		velocity += (-k * (value - target) - c * velocity) * dt
		value += velocity * dt
	}

	var settled: Bool { abs(value - target) < epsilon && abs(velocity) < epsilon * 10 }
}
// how often a toast checks its pane still exists, so a sticky one cannot outlive it
let PANE_CHECK_SECONDS = 10.0
// A check wezterm has not answered by then is killed: a hung `cli list` holds a mux
// subscription whose queue grows without bound, and hundreds of them wedged the GUI
let PANE_CHECK_TIMEOUT = 3.0
// No input for this long counts as walked away: past a pause to read or think, short of
// the screensaver. CC_TOAST_AWAY overrides it, for testing
let AWAY_SECONDS = Double(ProcessInfo.processInfo.environment["CC_TOAST_AWAY"] ?? "") ?? 60
// back from away, a toast gets at least this long, so it is seen before it goes
let BACK_SECONDS = 8.0

/// Since the last key, click or mouse move anywhere; keeps growing while locked or asleep
func idleSeconds() -> Double {
	CGEventSource.secondsSinceLastEventType(
		.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
}

let titleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
let bodyFont = NSFont.systemFont(ofSize: 13, weight: .regular)

// One file per slot, "<pid> <height> <sticky 0|1> <started_ms> <rank> <pane>"; O_EXCL claims
// it, a dead pid frees it. The slot is only an id: each toast places itself below every live
// one ahead of it in the order, so a closed one closes the gap and a higher one pushes in
let slotDir = NSString(string: "~/.claude/cache/cc-toast").expandingTildeInPath
var slot = -1

struct Slot {
	var pid: String
	var height: CGFloat
	var sticky: Bool
	var started: Int
	var rank: Double
	var pane: String
	var line: String {
		"\(pid) \(Int(height)) \(sticky ? 1 : 0) \(started) \(rank) \(pane.isEmpty ? "-" : pane)"
	}
	var score: Double { pickScores()[pane] ?? rank }
	/// LEADER+t's order, newer first on a tie
	func ahead(of o: Slot) -> Bool {
		let (a, b) = (score, o.score)
		return a != b ? a > b : started > o.started
	}
}

var mine = Slot(
	pid: "\(getpid())", height: 56, sticky: false,
	started: Int(Date().timeIntervalSince1970 * 1000), rank: 0.5, pane: "")

// wezterm.lua's ranking, `#epoch\tfrom <pane>` then `i\tpane\tscore\t...`, rewritten every
// 2s while toasts are up. Older than PICK_STALE and wezterm is gone: --rank alone
let pickFile = NSString(string: "~/.claude/cache/kev-pick").expandingTildeInPath
let PICK_STALE = 10.0
var pickCache: (read: Date, scores: [String: Double]) = (.distantPast, [:])

func pickScores() -> [String: Double] {
	if Date().timeIntervalSince(pickCache.read) < 0.1 { return pickCache.scores }
	var scores: [String: Double] = [:]
	if let text = try? String(contentsOfFile: pickFile, encoding: .utf8) {
		let lines = text.split(separator: "\n")
		let epoch = lines.first.flatMap { Double($0.dropFirst().split(separator: "\t").first ?? "") }
		if let epoch, Date().timeIntervalSince1970 - epoch < PICK_STALE {
			for l in lines.dropFirst() {
				let f = l.split(separator: "\t", omittingEmptySubsequences: false)
				if f.count > 2, let v = Double(f[2]) { scores[String(f[1])] = v }
			}
		}
	}
	pickCache = (Date(), scores)
	return scores
}

func alive(_ text: String) -> Bool {
	guard let pid = Int32(text.split(separator: " ").first ?? "") else { return false }
	return kill(pid, 0) == 0 || errno != ESRCH
}

func liveSlots() -> [Slot] {
	(0..<MAX_SLOTS).compactMap { n in
		guard let text = try? String(contentsOfFile: "\(slotDir)/\(n)", encoding: .utf8),
			alive(text)
		else { return nil }
		let f = text.split(whereSeparator: \.isWhitespace).map(String.init)
		// a toast from before ranks wrote four fields: it sits mid-stack
		return Slot(
			pid: f[0], height: CGFloat(f.count > 1 ? Double(f[1]) ?? 56 : 56),
			sticky: f.count > 2 && f[2] == "1", started: f.count > 3 ? Int(f[3]) ?? 0 : 0,
			rank: f.count > 4 ? Double(f[4]) ?? 0.5 : 0.5,
			pane: f.count > 5 && f[5] != "-" ? f[5] : "")
	}
}

func claimSlot() -> Int {
	try? FileManager.default.createDirectory(
		atPath: slotDir, withIntermediateDirectories: true)
	for _ in 0..<2 {
		for n in 0..<MAX_SLOTS {
			let path = "\(slotDir)/\(n)"
			let fd = open(path, O_WRONLY | O_CREAT | O_EXCL, 0o644)
			if fd >= 0 {
				_ = mine.line.withCString { write(fd, $0, strlen($0)) }
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

func owned() -> Bool {
	guard slot >= 0,
		let owner = try? String(contentsOfFile: "\(slotDir)/\(slot)", encoding: .utf8)
	else { return false }
	return owner.split(separator: " ").first.map(String.init) == mine.pid
}

/// The pill opening or closing: renamed in, so a neighbour never reads half a line
func rewriteSlot() {
	guard owned() else { return }
	let tmp = "\(slotDir)/.\(slot).\(mine.pid)"
	guard (try? mine.line.write(toFile: tmp, atomically: false, encoding: .utf8)) != nil
	else { return }
	rename(tmp, "\(slotDir)/\(slot)")
	announce()
}

func releaseSlot() {
	if owned() {
		unlink("\(slotDir)/\(slot)")
		announce()
	}
}

func offsetAbove() -> CGFloat {
	liveSlots().filter { $0.pid != mine.pid && $0.ahead(of: mine) }
		.reduce(0) { $0 + $1.height + GAP }
}

/// Whether this toast is the one to go while too many are showing: it stays in `wz toasts`
/// and LEADER+t
func shouldGiveWay() -> Bool {
	let live = liveSlots()
	guard live.count > MAX_SHOWN else { return false }
	let loose = live.filter { !$0.sticky }
	let last = (loose.isEmpty ? live : loose).max { $0.ahead(of: $1) }
	return last?.pid == mine.pid
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
	let kill = DispatchWorkItem { if p.isRunning { p.terminate() } }
	DispatchQueue.global().asyncAfter(deadline: .now() + PANE_CHECK_TIMEOUT, execute: kill)
	let data = out.fileHandleForReading.readDataToEndOfFile()
	p.waitUntilExit()
	kill.cancel()
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
func queueAction(_ line: String) -> Bool {
	let dir = NSString(string: "~/.claude/fleet/actions.d").expandingTildeInPath
	try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
	let name = "\(Int(Date().timeIntervalSince1970))-\(getpid())-\(Int.random(in: 0..<32768))"
	let tmp = "\(dir)/\(name).tmp"
	guard (try? line.write(toFile: tmp, atomically: false, encoding: .utf8))
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
	let fullHeight: CGFloat
	var height: CGFloat
	let screen: NSScreen
	let close = CloseButton(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
	// the full toast and the pill's one line; a compact toast fades between them on hover
	let full = NSView()
	let pill = NSView()
	var opened = false
	var shimmer: CALayer?
	var left: Double
	var hovering = false
	var closing = false
	var timer: Timer?
	var seenTicks = 0
	var placedAt: CGFloat = -1
	var lastPaneCheck = Date()
	var paneCheckRunning = false
	var host: (number: Int, frame: NSRect)?
	var ticks = 0
	var away = false
	var lastIdle = 0.0
	var shownAt = Date()
	// the panel's left edge, top edge (so the pill grows downward), height and alpha
	var sx = Spring(0)
	var stop = Spring(0)
	var sh = Spring(0)
	var sa = Spring(0, epsilon: 0.004)
	var link: CADisplayLink?
	var lastFrame: CFTimeInterval = 0
	var settled: (() -> Void)?

	init(_ o: Options) {
		self.o = o
		left = o.seconds
		// the fallback when no WezTerm window is on screen
		screen = NSScreen.screens.first ?? NSScreen.main!

		let textW = WIDTH - TEXT_X - PAD
		let title = label(o.title, titleFont, 0.9, lines: 1)
		// the hue, lifted a little toward white: Mocha's accents are pastel already, so this
		// keeps the dark ones (mauve, blue) as readable as the pale ones on the glass
		let hue = o.colour.map { $0.blended(withFraction: 0.18, of: .white) ?? $0 }
		if let hue { title.textColor = hue }
		let body = label(o.body, bodyFont, 0.85, lines: 2)
		let titleH = ceil(title.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: textW, height: 100)).height)
		let bodyH =
			o.body.isEmpty
			? 0 : ceil(body.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: textW, height: 100)).height)
		let textH = titleH + (bodyH > 0 ? bodyH : 0)
		fullHeight = max(56, textH + 2 * 11)
		height = o.compact ? COMPACT_H : fullHeight
		mine.height = height
		mine.sticky = o.sticky
		mine.rank = o.rank
		mine.pane = o.pane
		slot = claimSlot()

		panel = Panel(
			contentRect: NSRect(x: 0, y: 0, width: WIDTH + 2 * BLEED, height: fullHeight + 2 * BLEED),
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

		// Laid out at full height, then the panel shrinks to the pill if compact: the banner
		// stretches with it, everything else is pinned to its top
		let root = RootView(frame: NSRect(origin: .zero, size: panel.frame.size))
		root.autoresizesSubviews = true
		root.onClick = { [unowned self] in self.clicked() }
		root.onHover = { [unowned self] in self.hover($0) }
		root.close = close

		let banner = NSRect(x: BLEED, y: BLEED, width: WIDTH, height: fullHeight)
		let glass = NSVisualEffectView(frame: banner)
		glass.autoresizingMask = [.height]
		glass.material = .popover
		glass.blendingMode = .behindWindow
		glass.state = .active
		let corner = NSSize(width: 2 * RADIUS + 1, height: 2 * RADIUS + 1)
		glass.maskImage = NSImage(size: corner, flipped: false) { r in
			NSColor.black.setFill()
			NSBezierPath(roundedRect: r, xRadius: RADIUS, yRadius: RADIUS).fill()
			return true
		}
		glass.maskImage?.capInsets = NSEdgeInsets(
			top: RADIUS, left: RADIUS, bottom: RADIUS, right: RADIUS)
		glass.maskImage?.resizingMode = .stretch
		root.addSubview(glass)

		// Tint over the blur, not instead of it: strongest at the leading edge and fading
		// across, so the glass still reads as glass and the text sits on the quieter end.
		// Its layers are full height and clipped, so the pill needs no relayout
		let wash = NSView(frame: banner)
		wash.autoresizingMask = [.height]
		wash.wantsLayer = true
		wash.layer?.cornerRadius = RADIUS
		wash.layer?.cornerCurve = .continuous
		wash.layer?.masksToBounds = true
		var edge: CALayer?
		if let c = o.colour {
			let g = CAGradientLayer()
			g.frame = CGRect(origin: .zero, size: banner.size)
			g.startPoint = CGPoint(x: 0, y: 0.5)
			g.endPoint = CGPoint(x: 1, y: 0.5)
			g.colors = [c.withAlphaComponent(0.26).cgColor, c.withAlphaComponent(0.08).cgColor]
			wash.layer?.addSublayer(g)
			let e = CALayer()
			e.frame = CGRect(x: 0, y: 0, width: 3, height: banner.height)
			e.backgroundColor = c.withAlphaComponent(0.85).cgColor
			wash.layer?.addSublayer(e)
			edge = e
		}
		// one bright band swept across as it lands, for the ones worth turning round for
		if o.rank >= SHIMMER_RANK {
			let band = CAGradientLayer()
			band.frame = CGRect(x: -140, y: 0, width: 140, height: banner.height)
			band.startPoint = CGPoint(x: 0, y: 0.35)
			band.endPoint = CGPoint(x: 1, y: 0.65)
			band.colors = [
				NSColor.white.withAlphaComponent(0).cgColor,
				NSColor.white.withAlphaComponent(0.16).cgColor,
				NSColor.white.withAlphaComponent(0).cgColor,
			]
			wash.layer?.addSublayer(band)
			shimmer = band
		}
		root.addSubview(wash)

		let rim = NSView(frame: banner)
		rim.autoresizingMask = [.height]
		rim.wantsLayer = true
		rim.layer?.cornerRadius = RADIUS
		rim.layer?.cornerCurve = .continuous
		rim.layer?.borderWidth = 0.5
		rim.layer?.borderColor = (o.colour?.withAlphaComponent(0.35) ?? NSColor.white.withAlphaComponent(0.2)).cgColor
		root.addSubview(rim)

		full.frame = banner
		full.autoresizingMask = [.minYMargin]
		full.wantsLayer = true
		pill.wantsLayer = true
		if let img = appIcon() {
			let icon = NSImageView(
				frame: NSRect(x: PAD, y: (fullHeight - ICON) / 2, width: ICON, height: ICON))
			icon.image = img
			icon.imageScaling = .scaleProportionallyUpOrDown
			full.addSubview(icon)
		}
		let top = (fullHeight + textH) / 2
		title.frame = NSRect(x: TEXT_X, y: top - titleH, width: textW, height: titleH)
		body.frame = NSRect(x: TEXT_X, y: top - titleH - bodyH, width: textW, height: bodyH)
		full.addSubview(title)
		if bodyH > 0 { full.addSubview(body) }
		root.addSubview(full)

		if o.compact {
			pill.frame = NSRect(
				x: BLEED, y: BLEED + fullHeight - COMPACT_H, width: WIDTH, height: COMPACT_H)
			pill.autoresizingMask = [.minYMargin]
			if let img = appIcon() {
				let icon = NSImageView(
					frame: NSRect(
						x: PAD + 2, y: (COMPACT_H - COMPACT_ICON) / 2, width: COMPACT_ICON,
						height: COMPACT_ICON))
				icon.image = img
				icon.imageScaling = .scaleProportionallyUpOrDown
				pill.addSubview(icon)
			}
			// the field's own lineBreakMode does not reach an attributed string: the … needs this
			let tail = NSMutableParagraphStyle()
			tail.lineBreakMode = .byTruncatingTail
			let line = NSMutableAttributedString(
				string: o.title,
				attributes: [
					.font: titleFont, .paragraphStyle: tail,
					.foregroundColor: hue ?? NSColor.white.withAlphaComponent(0.9),
				])
			if !o.body.isEmpty {
				line.append(
					NSAttributedString(
						string: "  " + o.body,
						attributes: [
							.font: bodyFont, .paragraphStyle: tail,
							.foregroundColor: NSColor.white.withAlphaComponent(0.6),
						]))
			}
			let x = PAD + 2 + COMPACT_ICON + 10
			let one = NSTextField(labelWithAttributedString: line)
			one.lineBreakMode = .byTruncatingTail
			one.maximumNumberOfLines = 1
			one.isSelectable = false
			let h = ceil(one.cell!.cellSize.height)
			one.frame = NSRect(x: x, y: (COMPACT_H - h) / 2, width: WIDTH - x - PAD - 4, height: h)
			pill.addSubview(one)
			root.addSubview(pill)
			full.alphaValue = 0
		}

		// a sticky toast waits for you: a small pin of a dot, top right, says so
		if o.sticky {
			let d: CGFloat = 7
			let dot = NSView(
				frame: NSRect(x: BLEED + WIDTH - PAD - d, y: BLEED + fullHeight - PAD - d, width: d, height: d))
			dot.autoresizingMask = [.minYMargin]
			dot.wantsLayer = true
			dot.layer?.cornerRadius = d / 2
			dot.layer?.backgroundColor = (o.colour ?? NSColor.white.withAlphaComponent(0.7)).cgColor
			root.addSubview(dot)
			if o.rank >= PULSE_RANK {
				breathe(dot.layer, to: 0.3)
				breathe(edge, to: 0.4)
			}
		}

		close.isBordered = false
		close.title = ""
		close.target = self
		close.action = #selector(dismiss)
		close.frame.origin = NSPoint(x: BLEED - 6, y: BLEED + fullHeight - 14)
		close.autoresizingMask = [.minYMargin]
		close.isHidden = true
		root.addSubview(close)

		panel.contentView = root
		panel.alphaValue = 0  // place() orders it in; show() fades it up
		place(animated: false)
		link = root.displayLink(target: self, selector: #selector(onFrame(_:)))
		link?.isPaused = true
		link?.add(to: .main, forMode: .common)
		announce()
	}

	/// Snaps the springs to `f`, for placing before anything is seen and following WezTerm
	func snap(to f: NSRect) {
		sx.snap(f.minX)
		stop.snap(f.maxY)
		sh.snap(f.height)
		apply()
	}

	func glide(to f: NSRect, response: CGFloat = 0.42, damping: CGFloat = 0.82) {
		sx.aim(f.minX, response: response, damping: damping)
		stop.aim(f.maxY, response: response, damping: damping)
		sh.aim(f.height, response: response, damping: damping)
		run()
	}

	func run() {
		if link?.isPaused == true {
			lastFrame = 0
			link?.isPaused = false
		}
	}

	@objc func onFrame(_ l: CADisplayLink) {
		// one long frame (a hitch, a wake) must not fling the spring: cap it, and substep so
		// a stiff spring stays stable at 60Hz as at 120
		let dt = lastFrame == 0 ? l.duration : min(l.timestamp - lastFrame, 1.0 / 30)
		lastFrame = l.timestamp
		let n = max(1, Int(ceil(dt * 480)))
		for _ in 0..<n {
			let d = CGFloat(dt) / CGFloat(n)
			sx.step(d)
			stop.step(d)
			sh.step(d)
			sa.step(d)
		}
		if sx.settled && stop.settled && sh.settled && sa.settled {
			sx.snap(sx.target)
			stop.snap(stop.target)
			sh.snap(sh.target)
			sa.snap(sa.target)
			l.isPaused = true
			apply()
			panel.invalidateShadow()
			let done = settled
			settled = nil
			done?()
			return
		}
		apply()
	}

	/// Whole device pixels, so text does not shimmer as it moves
	func apply() {
		let s = panel.backingScaleFactor
		let px = { (v: CGFloat) in (v * s).rounded() / s }
		let h = px(sh.value)
		let r = NSRect(
			x: px(sx.value), y: px(stop.value) - h, width: WIDTH + 2 * BLEED, height: h)
		if r != panel.frame { panel.setFrame(r, display: r.height != panel.frame.height) }
		panel.alphaValue = min(max(sa.value, 0), 1)
	}

	/// Another toast's slot changed: make room, or close a gap, now
	func restack() {
		if timer != nil && !closing { place(animated: true) }
	}

	/// A slow fade down and back, for as long as the toast is up
	func breathe(_ layer: CALayer?, to low: Float) {
		let a = CABasicAnimation(keyPath: "opacity")
		a.fromValue = 1
		a.toValue = low
		a.duration = 1.1
		a.autoreverses = true
		a.repeatCount = .infinity
		a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
		layer?.add(a, forKey: "breathe")
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
			// a higher one pushing in above, or a gap closing: glide there and settle
			glide(to: frameFor(offset: off))
		} else {
			snap(to: frameFor(offset: off))
		}
	}

	/// Out of sight while another app is in front: hold the countdown so it gets its time
	var unseen: Bool {
		host != nil && NSWorkspace.shared.frontmostApplication?.bundleIdentifier != WEZTERM
	}

	func show() {
		// placed again now the ranking that came of the `pick` below has had time to land
		placedAt = -1
		place(animated: false)
		// in from the right edge, as native banners do, a touch past its place and back
		let end = panel.frame
		snap(to: end.offsetBy(dx: 56, dy: 0))
		sa.snap(0)
		apply()
		if let h = host {
			panel.order(.above, relativeTo: h.number)
		} else {
			panel.orderFrontRegardless()
		}
		panel.invalidateShadow()
		glide(to: end, response: 0.5, damping: 0.72)
		sa.aim(1, response: 0.28, damping: 1)
		if let band = shimmer {
			let sweep = CABasicAnimation(keyPath: "position.x")
			sweep.fromValue = -70
			sweep.toValue = WIDTH + 70
			sweep.duration = 0.9
			sweep.beginTime = CACurrentMediaTime() + 0.3
			sweep.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
			band.add(sweep, forKey: "sweep")
		}
		if !o.quiet { NSSound(named: "Glass")?.play() }
		shownAt = Date()
		timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [unowned self] _ in
			if self.closing { return }
			self.place(animated: true)
			self.seenTicks += 1
			if lookingAt(self.o.pane) || (self.seenTicks % 5 == 0 && shouldGiveWay()) {
				self.dismiss()
				return
			}
			// a CLI round trip: off the main thread, or every toast hitches each check
			if !self.paneCheckRunning
				&& Date().timeIntervalSince(self.lastPaneCheck) >= PANE_CHECK_SECONDS
			{
				self.lastPaneCheck = Date()
				self.paneCheckRunning = true
				let pane = self.o.pane
				DispatchQueue.global(qos: .utility).async {
					let exists = paneExists(pane)
					DispatchQueue.main.async {
						self.paneCheckRunning = false
						if !exists { self.dismiss() }
					}
				}
			}
			if self.o.sticky || self.hovering || self.unseen { return }
			self.tick()
		}
	}

	/// The countdown, held while nobody is at the machine
	func tick() {
		let idle = idleSeconds()
		if away {
			// idle only ever shrinks on input
			if idle >= lastIdle { lastIdle = idle; return }
			away = false
			left = max(left, min(o.seconds, BACK_SECONDS))
		}
		if idle >= AWAY_SECONDS { away = true; lastIdle = idle; return }
		left -= 0.1
		if left <= 0 {
			// left inside AWAY_SECONDS of it coming up, and nothing touched since: wait too
			if idle >= Date().timeIntervalSince(shownAt) {
				away = true
				lastIdle = idle
				return
			}
			dismiss()
		}
	}

	func hover(_ on: Bool) {
		hovering = on
		close.isHidden = !on
		if o.compact { open(on) }
	}

	/// The pill grows down into the full toast, and the ones below make room
	func open(_ on: Bool) {
		guard on != opened, !closing else { return }
		opened = on
		height = on ? fullHeight : COMPACT_H
		mine.height = height
		rewriteSlot()
		// opening springs a touch past and settles; closing tucks away without a bounce
		glide(to: frameFor(offset: placedAt), response: on ? 0.38 : 0.3, damping: on ? 0.78 : 1)
		NSAnimationContext.runAnimationGroup {
			$0.duration = on ? 0.2 : 0.14
			$0.timingFunction = CAMediaTimingFunction(name: .easeOut)
			full.animator().alphaValue = on ? 1 : 0
			pill.animator().alphaValue = on ? 0 : 1
		}
	}

	// The jump is a `jump` line queued straight into actions.d, which wezterm.lua drains
	// every 0.1s and runs in-process: no wz go, no CLI round trips. wz go only if that fails
	func clicked() {
		if !o.pane.isEmpty && queueAction("jump\t\(o.pane)\t\n") {
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
		// the slot goes first, so the ones below close the gap while this one leaves
		releaseSlot()
		// flicked off to the right: it leaves already moving rather than easing away
		sx.velocity += 420
		sx.aim(sx.target + 60, response: 0.34, damping: 1)
		sa.aim(0, response: 0.22, damping: 1)
		settled = { exit(0) }
		run()
		// a panel off screen gets no display frames, and nothing would ever settle it
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { exit(0) }
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
CFNotificationCenterAddObserver(
	CFNotificationCenterGetDarwinNotifyCenter(), nil,
	{ _, _, _, _, _ in DispatchQueue.main.async { toast.restack() } }, STACK_NOTE, nil,
	.deliverImmediately)
// wezterm.lua drains actions every 0.1s: a fresh ranking with this toast's pane in it, so
// it lands in its place rather than gliding there a moment later
_ = queueAction("pick\t\t\n")
DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { toast.show() }
app.run()
