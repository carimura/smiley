import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import Vision

struct Stamp: Identifiable {
    let id = UUID()
    var pos: CGPoint      // normalized 0-1, origin top-left
    var frac: CGFloat     // emoji size as fraction of image width
    let emoji: String
}

final class Doc: ObservableObject {
    static let shared = Doc()
    @Published var cgImage: CGImage?
    @Published var stamps: [Stamp] = []
    @Published var selected: UUID?
    @Published var emoji = "😀"
    @Published var selectMode = false
    @Published var frac: CGFloat = 0.15   // default size for new stamps
    @Published var note: String?
    var url: URL?

    var image: NSImage? {
        cgImage.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
    }

    func open(_ url: URL) {
        // Decode via ImageIO with transform applied so EXIF-rotated iPhone photos come in upright
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 20000,
        ]
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
            NSSound.beep()
            return
        }
        cgImage = cg
        stamps = []
        selected = nil
        selectMode = false
        self.url = url
        autoSmiley()
    }

    func autoSmiley() {
        guard let cg = cgImage else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNDetectFaceRectanglesRequest()
            try? VNImageRequestHandler(cgImage: cg).perform([request])
            let faces = request.results ?? []
            DispatchQueue.main.async {
                guard self.cgImage === cg else { return }  // image changed while detecting
                guard !faces.isEmpty else { self.flash("No faces found"); return }
                let W = CGFloat(cg.width), H = CGFloat(cg.height)
                for f in faces {
                    let b = f.boundingBox  // normalized, bottom-left origin
                    // Vision's box hugs the face; pad so the emoji covers chin and hair.
                    // frac is width-relative, so convert the box height into width units.
                    let size = max(b.width, b.height * H / W) * 1.4
                    self.stamps.append(Stamp(
                        pos: CGPoint(x: b.midX, y: 1 - b.midY),
                        frac: min(max(size, 0.02), 0.8),
                        emoji: self.emoji))
                }
                self.selectMode = true   // ready to tweak: click a face, drag, ⌘+/⌘−
                self.flash("Added \(faces.count) smiley\(faces.count == 1 ? "" : "s")")
            }
        }
    }

    func close() {
        cgImage = nil
        stamps = []
        selected = nil
        selectMode = false
        url = nil
        note = nil
    }

    func undoLast() {
        guard let last = stamps.popLast() else { return }
        if selected == last.id { selected = nil }
    }

    func deleteSelected() {
        guard let sel = selected else { return }
        stamps.removeAll { $0.id == sel }
        selected = nil
    }

    func resize(by m: CGFloat) {
        if let sel = selected, let i = stamps.firstIndex(where: { $0.id == sel }) {
            stamps[i].frac = min(max(stamps[i].frac * m, 0.02), 0.8)
        } else {
            frac = min(max(frac * m, 0.05), 0.4)
        }
    }

    func save() {
        guard let cg = cgImage, let url else { return }
        let W = CGFloat(cg.width), H = CGFloat(cg.height)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: cg.width, pixelsHigh: cg.height,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.cgContext.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))
        for s in stamps {
            let str = NSAttributedString(string: s.emoji,
                                         attributes: [.font: NSFont.systemFont(ofSize: s.frac * W)])
            let sz = str.size()
            str.draw(at: NSPoint(x: s.pos.x * W - sz.width / 2,
                                 y: (1 - s.pos.y) * H - sz.height / 2))
        }
        NSGraphicsContext.restoreGraphicsState()

        let data = NSMutableData()
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let type = CGImageSourceGetType(source),
              let rendered = rep.cgImage,
              let destination = CGImageDestinationCreateWithData(data, type, 1, nil) else {
            flash("Save failed: image format cannot be written")
            return
        }
        CGImageDestinationAddImage(destination, rendered,
                                  [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            flash("Save failed: image could not be encoded")
            return
        }
        do {
            try (data as Data).write(to: url, options: .atomic)
            flash("Saved \(url.lastPathComponent) ✓")
        } catch {
            flash("Save failed: \(error.localizedDescription)")
        }
    }

    private func flash(_ msg: String) {
        note = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.note = nil }
    }
}

func fitRect(_ imageSize: CGSize, in container: CGSize) -> CGRect {
    let scale = min(container.width / imageSize.width, container.height / imageSize.height)
    let w = imageSize.width * scale, h = imageSize.height * scale
    return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
}

func openImagePanel() {
    let p = NSOpenPanel()
    p.allowedContentTypes = [.image]
    if p.runModal() == .OK, let u = p.url { Doc.shared.open(u) }
}

struct ContentView: View {
    @ObservedObject var doc = Doc.shared
    @State private var hover: CGPoint?
    @State private var dragBegan = false
    @State private var dragID: UUID?
    @State private var dragOrigin: CGPoint = .zero
    @State private var resizing = false
    @State private var dragFrac: CGFloat = 0
    @State private var dragRadius: CGFloat = 0

    static let emojis = ["😀", "😁", "😊", "🙂", "😎", "🤪"]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            canvas
        }
        .frame(minWidth: 640, minHeight: 480)
        .background(hiddenShortcuts)
    }

    // ⌘⇧= produces "+" — catch it so both ⌘= and ⌘⇧= mean "bigger"
    private var hiddenShortcuts: some View {
        Group {
            Button("") { doc.resize(by: 1.2) }.keyboardShortcut("+", modifiers: .command)
            Button("") { doc.resize(by: 1 / 1.2) }.keyboardShortcut("_", modifiers: .command)
        }
        .opacity(0)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button { doc.selectMode = true } label: {
                Image(systemName: "cursorarrow")
                    .font(.system(size: 18))
                    .frame(width: 26, height: 26)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .fill(doc.selectMode ? Color.accentColor.opacity(0.3) : .clear))
            }
            .buttonStyle(.plain)
            Divider().frame(height: 26)
            ForEach(Self.emojis, id: \.self) { e in
                Button { doc.emoji = e; doc.selectMode = false; doc.selected = nil } label: {
                    Text(e).font(.system(size: 24)).padding(4)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(e == doc.emoji && !doc.selectMode ? Color.accentColor.opacity(0.3) : .clear))
                }
                .buttonStyle(.plain)
            }
            Divider().frame(height: 26)
            Button {
                doc.autoSmiley()
            } label: {
                Label("Auto Smiley", systemImage: "wand.and.stars")
            }
            .keyboardShortcut("d")
            .disabled(doc.cgImage == nil)
            Button {
                doc.undoLast()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(doc.stamps.isEmpty)
            Spacer()
            if let note = doc.note {
                Text(note).foregroundStyle(.secondary)
            }
            Text("Size").foregroundStyle(.secondary)
            Slider(value: $doc.frac, in: 0.05...0.4).frame(width: 140)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var canvas: some View {
        GeometryReader { geo in
            ZStack {
                Color(nsColor: .underPageBackgroundColor)
                if let img = doc.image {
                    let fit = fitRect(img.size, in: geo.size)
                    Image(nsImage: img)
                        .resizable()
                        .frame(width: fit.width, height: fit.height)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    ForEach(doc.stamps) { s in
                        Text(s.emoji)
                            .font(.system(size: s.frac * fit.width))
                            .position(x: fit.minX + s.pos.x * fit.width,
                                      y: fit.minY + s.pos.y * fit.height)
                    }
                    if let sel = doc.selected,
                       let s = doc.stamps.first(where: { $0.id == sel }) {
                        Circle()
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                            .frame(width: s.frac * fit.width + 10, height: s.frac * fit.width + 10)
                            .position(x: fit.minX + s.pos.x * fit.width,
                                      y: fit.minY + s.pos.y * fit.height)
                            .allowsHitTesting(false)
                    }
                    if let h = hover, !doc.selectMode {
                        Text(doc.emoji)
                            .font(.system(size: doc.frac * fit.width))
                            .opacity(0.5)
                            .position(h)
                            .allowsHitTesting(false)
                    }
                } else {
                    Text("Drop a photo here, or press ⌘O to open one")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .onTapGesture { loc in
                guard !doc.selectMode, let img = doc.image else { return }
                let fit = fitRect(img.size, in: geo.size)
                guard fit.contains(loc) else { return }
                doc.stamps.append(Stamp(
                    pos: CGPoint(x: (loc.x - fit.minX) / fit.width,
                                 y: (loc.y - fit.minY) / fit.height),
                    frac: doc.frac, emoji: doc.emoji))
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        guard doc.selectMode, let img = doc.image else { return }
                        let fit = fitRect(img.size, in: geo.size)
                        if !dragBegan {
                            dragBegan = true
                            resizing = false
                            if let s = doc.stamps.first(where: { $0.id == doc.selected }) {
                                let center = CGPoint(x: fit.minX + s.pos.x * fit.width,
                                                     y: fit.minY + s.pos.y * fit.height)
                                let radius = (s.frac * fit.width + 10) / 2
                                let distance = hypot(v.startLocation.x - center.x,
                                                     v.startLocation.y - center.y)
                                if abs(distance - radius) <= min(8, radius * 0.35) {
                                    resizing = true
                                    dragFrac = s.frac
                                    dragRadius = distance
                                    dragID = s.id
                                }
                            }
                            if !resizing { dragID = hitTest(v.startLocation, fit: fit) }
                            doc.selected = dragID
                            if let id = dragID, let s = doc.stamps.first(where: { $0.id == id }) {
                                dragOrigin = s.pos
                            }
                        }
                        guard let id = dragID,
                              let i = doc.stamps.firstIndex(where: { $0.id == id }) else { return }
                        if resizing {
                            let center = CGPoint(x: fit.minX + dragOrigin.x * fit.width,
                                                 y: fit.minY + dragOrigin.y * fit.height)
                            let radius = hypot(v.location.x - center.x, v.location.y - center.y)
                            doc.stamps[i].frac = min(max(dragFrac + 2 * (radius - dragRadius) / fit.width, 0.02), 0.8)
                        } else {
                            doc.stamps[i].pos = CGPoint(
                                x: min(max(dragOrigin.x + v.translation.width / fit.width, 0), 1),
                                y: min(max(dragOrigin.y + v.translation.height / fit.height, 0), 1))
                        }
                    }
                    .onEnded { _ in dragBegan = false; dragID = nil; resizing = false }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): hover = p
                case .ended: hover = nil
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let u = urls.first else { return false }
            doc.open(u)
            return true
        }
    }

    private func hitTest(_ p: CGPoint, fit: CGRect) -> UUID? {
        for s in doc.stamps.reversed() {
            let c = CGPoint(x: fit.minX + s.pos.x * fit.width,
                            y: fit.minY + s.pos.y * fit.height)
            let half = max(s.frac * fit.width / 2, 12)
            if abs(p.x - c.x) <= half && abs(p.y - c.y) <= half { return s.id }
        }
        return nil
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        if let u = urls.first { Doc.shared.open(u) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct SmileyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @ObservedObject var doc = Doc.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .navigationTitle(doc.url?.lastPathComponent ?? "Smiley")
        }
        .defaultSize(width: 960, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { openImagePanel() }.keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { Doc.shared.save() }.keyboardShortcut("s")
                Button("Close Photo") { Doc.shared.close() }.keyboardShortcut("w")
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo Stamp") { Doc.shared.undoLast() }.keyboardShortcut("z")
                Button("Delete Face") { Doc.shared.deleteSelected() }
                    .keyboardShortcut(.delete, modifiers: [])
                Divider()
                Button("Bigger Face") { Doc.shared.resize(by: 1.2) }.keyboardShortcut("=")
                Button("Smaller Face") { Doc.shared.resize(by: 1 / 1.2) }.keyboardShortcut("-")
            }
        }
    }
}
