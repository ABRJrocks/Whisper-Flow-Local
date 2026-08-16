// Renders AppIcon.png (1024x1024) — run via Scripts/make-app.sh when the icns is missing.
// Design: indigo-violet gradient squircle, white waveform capsules (the dictation bar).
import AppKit

let canvas: CGFloat = 1024
let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

// macOS icon grid: squircle inset ~10% with continuous corners.
let inset: CGFloat = 100
let rect = NSRect(x: inset, y: inset, width: canvas - 2 * inset, height: canvas - 2 * inset)
let squircle = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)

// Soft shadow so the icon doesn't float flat on light backgrounds.
NSGraphicsContext.current?.cgContext.setShadow(
    offset: CGSize(width: 0, height: -12), blur: 36,
    color: NSColor.black.withAlphaComponent(0.35).cgColor
)
NSColor(calibratedRed: 0.24, green: 0.23, blue: 0.85, alpha: 1).setFill()
squircle.fill()
NSGraphicsContext.current?.cgContext.setShadow(offset: .zero, blur: 0, color: nil)

squircle.setClip()
let gradient = NSGradient(
    starting: NSColor(calibratedRed: 0.16, green: 0.55, blue: 0.95, alpha: 1), // sky blue
    ending: NSColor(calibratedRed: 0.45, green: 0.20, blue: 0.90, alpha: 1)    // violet
)
gradient?.draw(in: rect, angle: -60)

// Subtle top sheen.
let sheen = NSGradient(
    starting: NSColor.white.withAlphaComponent(0.28),
    ending: NSColor.white.withAlphaComponent(0.0)
)
sheen?.draw(in: NSRect(x: rect.minX, y: rect.midY + 60, width: rect.width, height: rect.height / 2 - 60), angle: -90)

// Waveform: 7 white capsules, center-weighted heights.
let fractions: [CGFloat] = [0.22, 0.42, 0.68, 0.92, 0.68, 0.42, 0.22]
let barWidth: CGFloat = 58
let gap: CGFloat = 42
let totalWidth = CGFloat(fractions.count) * barWidth + CGFloat(fractions.count - 1) * gap
var x = (canvas - totalWidth) / 2
let maxBar: CGFloat = 520

NSGraphicsContext.current?.cgContext.setShadow(
    offset: .zero, blur: 26, color: NSColor.white.withAlphaComponent(0.45).cgColor
)
NSColor.white.setFill()
for fraction in fractions {
    let height = maxBar * fraction
    let bar = NSRect(x: x, y: (canvas - height) / 2, width: barWidth, height: height)
    NSBezierPath(roundedRect: bar, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
    x += barWidth + gap
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:])
else { fatalError("render failed") }
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
