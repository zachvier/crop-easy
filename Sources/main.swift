import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct CropEasyApp: App {
    @StateObject private var editor = CropEditorModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(editor)
                .frame(minWidth: 980, minHeight: 680)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Image...") {
                    editor.openImage()
                }
                .keyboardShortcut("o")
            }

            CommandMenu("Crop") {
                Button("Export Crop...") {
                    editor.exportCrop()
                }
                .keyboardShortcut("e")
                .disabled(!editor.hasLoadedImage)

                Divider()

                Button(editor.aspectLocked ? "Unlock Aspect Ratio" : "Lock Aspect Ratio") {
                    editor.toggleAspectLock()
                }
                .keyboardShortcut("l")
                .disabled(!editor.hasSelection)
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var editor: CropEditorModel
    @FocusState private var focusedDimension: DimensionField?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            bodyContent
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: focusedDimension) { oldValue, newValue in
            guard oldValue != newValue else { return }

            switch oldValue {
            case .width:
                editor.applyWidthText()
            case .height:
                editor.applyHeightText()
            case nil:
                break
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            editor.openDroppedImage(from: providers)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button("Open Image...") {
                editor.openImage()
            }

            Button("Export Crop...") {
                editor.exportCrop()
            }
            .disabled(!editor.hasLoadedImage)

            Divider()
                .frame(height: 20)

            Toggle("Lock Aspect", isOn: $editor.aspectLocked)
                .toggleStyle(.switch)
                .disabled(!editor.hasSelection)
                .onChange(of: editor.aspectLocked) { _, isLocked in
                    editor.syncAspectLock(isLocked)
                }

            Toggle("Scale Export", isOn: $editor.scaleExport)
                .toggleStyle(.switch)
                .disabled(!editor.hasSelection)
                .onChange(of: editor.scaleExport) { _, isEnabled in
                    editor.syncScaleExport(isEnabled)
                }

            Text("W")
                .foregroundStyle(.secondary)

            TextField("Width", text: $editor.widthText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 88)
                .disabled(!editor.hasSelection)
                .focused($focusedDimension, equals: .width)
                .onSubmit {
                    editor.applyWidthText()
                }

            Text("H")
                .foregroundStyle(.secondary)

            TextField("Height", text: $editor.heightText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 88)
                .disabled(!editor.hasSelection)
                .focused($focusedDimension, equals: .height)
                .onSubmit {
                    editor.applyHeightText()
                }

            Spacer()

            if let image = editor.loadedImage {
                Text("\(Int(image.pixelSize.width)) x \(Int(image.pixelSize.height)) px")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var bodyContent: some View {
        if editor.hasLoadedImage {
            CropCanvasView()
                .environmentObject(editor)
                .padding(20)
        } else {
            ContentUnavailableView {
                Label("Open an Image to Start Cropping", systemImage: "crop")
            } description: {
                Text("Supports PNG, JPEG, WebP, TIFF, GIF, BMP, and other standard macOS image formats.")
            } actions: {
                Button("Choose Image...") {
                    editor.openImage()
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

enum DimensionField {
    case width
    case height
}

struct CropCanvasView: View {
    @EnvironmentObject private var editor: CropEditorModel
    @State private var dragState: DragState?

    var body: some View {
        GeometryReader { proxy in
            let canvasSize = proxy.size
            let imageRect = editor.imageRect(in: canvasSize)
            let selectionRect = editor.selectionRectInView(imageRect: imageRect)

            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(nsColor: .controlBackgroundColor))

                if let image = editor.loadedImage, !editor.scaleExport {
                    Image(nsImage: image.nsImage)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: imageRect.width, height: imageRect.height)
                        .position(x: imageRect.midX, y: imageRect.midY)
                }

                if editor.scaleExport, let image = editor.loadedImage, let selectionRect {
                    Image(nsImage: image.nsImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: selectionRect.width, height: selectionRect.height)
                        .clipped()
                        .position(x: selectionRect.midX, y: selectionRect.midY)
                }

                if let selectionRect {
                    CropOverlay(
                        imageRect: imageRect,
                        selectionRect: selectionRect,
                        label: editor.selectionLabel,
                        margins: editor.scaleExport ? nil : editor.selectionMargins
                    )
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(in: imageRect, selectionRect: selectionRect))
        }
    }

    private func dragGesture(in imageRect: CGRect, selectionRect: CGRect?) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                editor.beginIfNeeded(
                    dragState: &dragState,
                    at: value.startLocation,
                    current: value.location,
                    imageRect: imageRect,
                    selectionRect: selectionRect
                )

                guard let dragState else { return }
                editor.updateDrag(dragState, currentLocation: value.location, imageRect: imageRect)
            }
            .onEnded { value in
                if let dragState {
                    editor.updateDrag(dragState, currentLocation: value.location, imageRect: imageRect)
                }
                self.dragState = nil
            }
    }
}

struct CropOverlay: View {
    let imageRect: CGRect
    let selectionRect: CGRect
    let label: String
    let margins: CropMargins?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let margins {
                CropMarginGuides(imageRect: imageRect, selectionRect: selectionRect, margins: margins)
            }

            Rectangle()
                .fill(Color.accentColor.opacity(margins == nil ? 0 : 0.18))
                .overlay {
                    Rectangle()
                        .strokeBorder(.white.opacity(0.95), lineWidth: 2)
                }
                .frame(width: selectionRect.width, height: selectionRect.height)
                .position(x: selectionRect.midX, y: selectionRect.midY)

            Text(label)
                .font(.caption.monospacedDigit().weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
                .position(x: selectionRect.minX + 70, y: max(18, selectionRect.minY - 18))

            ForEach(CornerHandle.allCases, id: \.self) { handle in
                Circle()
                    .fill(.white)
                    .frame(width: 12, height: 12)
                    .shadow(radius: 2)
                    .position(handle.position(in: selectionRect))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct CropMarginGuides: View {
    let imageRect: CGRect
    let selectionRect: CGRect
    let margins: CropMargins

    var body: some View {
        ZStack(alignment: .topLeading) {
            if selectionRect.minX > imageRect.minX {
                marginGuide(
                    from: CGPoint(x: imageRect.minX, y: selectionRect.midY),
                    to: CGPoint(x: selectionRect.minX, y: selectionRect.midY),
                    label: "\(margins.left) px",
                    labelPosition: CGPoint(x: (imageRect.minX + selectionRect.minX) / 2, y: selectionRect.midY - 16),
                    direction: .right
                )
            }

            if selectionRect.maxX < imageRect.maxX {
                marginGuide(
                    from: CGPoint(x: imageRect.maxX, y: selectionRect.midY),
                    to: CGPoint(x: selectionRect.maxX, y: selectionRect.midY),
                    label: "\(margins.right) px",
                    labelPosition: CGPoint(x: (imageRect.maxX + selectionRect.maxX) / 2, y: selectionRect.midY - 16),
                    direction: .left
                )
            }

            if selectionRect.minY > imageRect.minY {
                marginGuide(
                    from: CGPoint(x: selectionRect.midX, y: imageRect.minY),
                    to: CGPoint(x: selectionRect.midX, y: selectionRect.minY),
                    label: "\(margins.top) px",
                    labelPosition: CGPoint(x: selectionRect.midX + 34, y: (imageRect.minY + selectionRect.minY) / 2),
                    direction: .down
                )
            }

            if selectionRect.maxY < imageRect.maxY {
                marginGuide(
                    from: CGPoint(x: selectionRect.midX, y: imageRect.maxY),
                    to: CGPoint(x: selectionRect.midX, y: selectionRect.maxY),
                    label: "\(margins.bottom) px",
                    labelPosition: CGPoint(x: selectionRect.midX + 34, y: (imageRect.maxY + selectionRect.maxY) / 2),
                    direction: .up
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func marginGuide(
        from start: CGPoint,
        to end: CGPoint,
        label: String,
        labelPosition: CGPoint,
        direction: GuideDirection
    ) -> some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: start)
                path.addLine(to: end)
            }
            .stroke(.white.opacity(0.95), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))

            GuideArrow(direction: direction)
                .fill(.white.opacity(0.95))
                .frame(width: 9, height: 9)
                .position(end)

            Text(label)
                .font(.caption2.monospacedDigit().weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.black.opacity(0.58), in: Capsule())
                .foregroundStyle(.white)
                .position(labelPosition)
        }
    }
}

struct GuideArrow: Shape {
    let direction: GuideDirection

    func path(in rect: CGRect) -> Path {
        let points: [CGPoint]
        switch direction {
        case .right:
            points = [CGPoint(x: rect.maxX, y: rect.midY), CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.minX, y: rect.maxY)]
        case .left:
            points = [CGPoint(x: rect.minX, y: rect.midY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY)]
        case .down:
            points = [CGPoint(x: rect.midX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY)]
        case .up:
            points = [CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)]
        }

        var path = Path()
        path.move(to: points[0])
        path.addLine(to: points[1])
        path.addLine(to: points[2])
        path.closeSubpath()
        return path
    }
}

enum GuideDirection {
    case right
    case left
    case down
    case up
}

struct CropMargins {
    let left: Int
    let right: Int
    let top: Int
    let bottom: Int
}

enum CornerHandle: CaseIterable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    func position(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft:
            CGPoint(x: rect.minX, y: rect.minY)
        case .topRight:
            CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft:
            CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight:
            CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    func oppositePoint(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft:
            CGPoint(x: rect.maxX, y: rect.maxY)
        case .topRight:
            CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomLeft:
            CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomRight:
            CGPoint(x: rect.minX, y: rect.minY)
        }
    }
}

enum DragState {
    case creating(anchor: CGPoint)
    case moving(start: CGPoint, initialRect: CGRect)
    case resizing(handle: CornerHandle, anchor: CGPoint)
}

struct LoadedImage {
    let url: URL
    let nsImage: NSImage
    let cgImage: CGImage
    let pixelSize: CGSize
}

@MainActor
final class CropEditorModel: ObservableObject {
    @Published var loadedImage: LoadedImage?
    @Published var cropRect: CGRect?
    @Published var aspectLocked = false
    @Published var scaleExport = false
    @Published var widthText = ""
    @Published var heightText = ""

    private var lockedAspectRatio: CGFloat?
    private var exportSize: CGSize?
    private var userChangedSelection = false
    private let minimumSelectionSize: CGFloat = 1

    var hasLoadedImage: Bool { loadedImage != nil }
    var hasSelection: Bool { cropRect != nil }

    var selectionLabel: String {
        guard let cropRect else { return "" }
        let cropSize = "\(Int(cropRect.width.rounded())) x \(Int(cropRect.height.rounded())) px"
        guard scaleExport else { return cropSize }

        if let imageSize = loadedImage?.pixelSize {
            let sourceSize = "\(Int(imageSize.width.rounded())) x \(Int(imageSize.height.rounded())) px"
            return "\(sourceSize) -> \(cropSize)"
        }

        return cropSize
    }

    var selectionMargins: CropMargins {
        guard let cropRect, let loadedImage else {
            return CropMargins(left: 0, right: 0, top: 0, bottom: 0)
        }

        return CropMargins(
            left: Int(cropRect.minX.rounded()),
            right: Int((loadedImage.pixelSize.width - cropRect.maxX).rounded()),
            top: Int(cropRect.minY.rounded()),
            bottom: Int((loadedImage.pixelSize.height - cropRect.maxY).rounded())
        )
    }

    func openImage() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = supportedOpenTypes

        guard panel.runModal() == .OK, let url = panel.url else { return }

        openImage(from: url)
    }

    func openImage(from url: URL) {
        guard isSupportedOpenURL(url) else {
            presentError("Choose a supported image file.")
            return
        }

        do {
            let loaded = try loadImage(from: url)
            loadedImage = loaded
            cropRect = defaultCropRect(for: loaded.pixelSize)
            exportSize = cropRect?.size
            userChangedSelection = false
            syncDimensionText()
            if aspectLocked {
                lockedAspectRatio = cropRect.map { $0.width / max($0.height, 1) }
            }
        } catch {
            presentError(error.localizedDescription)
        }
    }

    func openDroppedImage(from providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let droppedURL = item as? URL {
                url = droppedURL
            } else if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                url = nil
            }

            guard let url else { return }

            Task { @MainActor in
                self.openImage(from: url)
            }
        }

        return true
    }

    func exportCrop() {
        guard
            let loadedImage,
            let cropRect,
            let sourceImage = scaleExport ? loadedImage.cgImage : croppedImage(from: loadedImage.cgImage, cropRect: cropRect),
            let exportImage = exportImage(from: sourceImage)
        else {
            return
        }

        let panel = NSSavePanel()
        let width = exportImage.width
        let height = exportImage.height
        panel.nameFieldStringValue = "\(loadedImage.url.deletingPathExtension().lastPathComponent)-\(width)x\(height)_png.png"
        panel.allowedContentTypes = supportedSaveTypes

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try write(cropped: exportImage, to: url)
        } catch {
            presentError(error.localizedDescription)
        }
    }

    func toggleAspectLock() {
        aspectLocked.toggle()
        syncAspectLock(aspectLocked)
    }

    func syncAspectLock(_ isLocked: Bool) {
        if isLocked {
            guard let cropRect else { return }
            lockedAspectRatio = cropRect.width / max(cropRect.height, 1)
        } else {
            lockedAspectRatio = nil
        }
    }

    func syncScaleExport(_ isEnabled: Bool) {
        if isEnabled, !userChangedSelection, let imageSize = loadedImage?.pixelSize {
            cropRect = CGRect(origin: .zero, size: imageSize)
        }
        exportSize = cropRect?.size
        syncDimensionText()
    }

    func imageRect(in containerSize: CGSize) -> CGRect {
        guard let imageSize = loadedImage?.pixelSize, containerSize.width > 0, containerSize.height > 0 else {
            return .zero
        }

        let horizontalPadding: CGFloat = 24
        let verticalPadding: CGFloat = 24
        let bounds = CGRect(
            x: horizontalPadding,
            y: verticalPadding,
            width: max(containerSize.width - horizontalPadding * 2, 1),
            height: max(containerSize.height - verticalPadding * 2, 1)
        )

        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let fittedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)

        return CGRect(
            x: bounds.midX - fittedSize.width / 2,
            y: bounds.midY - fittedSize.height / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    func selectionRectInView(imageRect: CGRect) -> CGRect? {
        guard let cropRect, let loadedImage else { return nil }

        let x = imageRect.minX + (cropRect.minX / loadedImage.pixelSize.width) * imageRect.width
        let y = imageRect.minY + (cropRect.minY / loadedImage.pixelSize.height) * imageRect.height
        let width = (cropRect.width / loadedImage.pixelSize.width) * imageRect.width
        let height = (cropRect.height / loadedImage.pixelSize.height) * imageRect.height

        return CGRect(x: x, y: y, width: width, height: height)
    }

    func beginIfNeeded(
        dragState: inout DragState?,
        at startLocation: CGPoint,
        current: CGPoint,
        imageRect: CGRect,
        selectionRect: CGRect?
    ) {
        guard dragState == nil else { return }

        guard imageRect.contains(startLocation), let startPixel = pixelPoint(for: startLocation, imageRect: imageRect) else {
            return
        }

        if let selectionRect, let cropRect, let handle = handle(at: startLocation, in: selectionRect) {
            dragState = .resizing(handle: handle, anchor: handle.oppositePoint(in: cropRect))
            return
        }

        if let selectionRect, let cropRect, selectionRect.insetBy(dx: 8, dy: 8).contains(startLocation) {
            dragState = .moving(start: startPixel, initialRect: cropRect)
            return
        }

        dragState = .creating(anchor: startPixel)
        updateDrag(.creating(anchor: startPixel), currentLocation: current, imageRect: imageRect)
    }

    func updateDrag(_ dragState: DragState, currentLocation: CGPoint, imageRect: CGRect) {
        guard let currentPixel = pixelPoint(for: currentLocation, imageRect: imageRect) else { return }

        switch dragState {
        case .creating(let anchor):
            cropRect = clamp(rectFrom(anchor: anchor, current: currentPixel, aspectRatio: lockedAspectRatio))
        case .moving(let start, let initialRect):
            cropRect = clamp(movedRect(initialRect, delta: currentPixel - start))
        case .resizing(_, let anchor):
            cropRect = clamp(rectFrom(anchor: anchor, current: currentPixel, aspectRatio: lockedAspectRatio))
        }

        userChangedSelection = true
        exportSize = cropRect?.size
        syncDimensionText()
    }

    func applyWidthText() {
        applyDimensionText(width: widthText, height: nil)
    }

    func applyWidthTextIfValid(_ value: String) {
        guard parseDimension(value) != nil else { return }
        applyDimensionText(width: value, height: nil)
    }

    func applyHeightText() {
        applyDimensionText(width: nil, height: heightText)
    }

    func applyHeightTextIfValid(_ value: String) {
        guard parseDimension(value) != nil else { return }
        applyDimensionText(width: nil, height: value)
    }

    private func pixelPoint(for viewPoint: CGPoint, imageRect: CGRect) -> CGPoint? {
        guard let loadedImage, imageRect.width > 0, imageRect.height > 0 else { return nil }

        let clampedX = min(max(viewPoint.x, imageRect.minX), imageRect.maxX)
        let clampedY = min(max(viewPoint.y, imageRect.minY), imageRect.maxY)

        let normalizedX = (clampedX - imageRect.minX) / imageRect.width
        let normalizedY = (clampedY - imageRect.minY) / imageRect.height

        return CGPoint(
            x: normalizedX * loadedImage.pixelSize.width,
            y: normalizedY * loadedImage.pixelSize.height
        )
    }

    private func rectFrom(anchor: CGPoint, current: CGPoint, aspectRatio: CGFloat?) -> CGRect {
        var dx = current.x - anchor.x
        var dy = current.y - anchor.y

        if let aspectRatio, aspectRatio > 0 {
            let absDX = abs(dx)
            let absDY = abs(dy)
            if absDX / aspectRatio > absDY {
                dy = (absDX / aspectRatio) * (dy < 0 ? -1 : 1)
            } else {
                dx = (absDY * aspectRatio) * (dx < 0 ? -1 : 1)
            }
        }

        let end = CGPoint(x: anchor.x + dx, y: anchor.y + dy)
        let origin = CGPoint(x: min(anchor.x, end.x), y: min(anchor.y, end.y))
        let size = CGSize(width: abs(end.x - anchor.x), height: abs(end.y - anchor.y))

        return CGRect(origin: origin, size: size).standardized
    }

    private func movedRect(_ rect: CGRect, delta: CGPoint) -> CGRect {
        CGRect(x: rect.minX + delta.x, y: rect.minY + delta.y, width: rect.width, height: rect.height)
    }

    private func clamp(_ rect: CGRect) -> CGRect? {
        guard let imageSize = loadedImage?.pixelSize else { return nil }

        var clamped = rect.standardized
        if scaleExport {
            clamped.size.width = max(minimumSelectionSize, clamped.width)
            clamped.size.height = max(minimumSelectionSize, clamped.height)
            clamped.origin.x = max(0, clamped.origin.x)
            clamped.origin.y = max(0, clamped.origin.y)
        } else {
            clamped.size.width = max(minimumSelectionSize, min(clamped.width, imageSize.width))
            clamped.size.height = max(minimumSelectionSize, min(clamped.height, imageSize.height))
            clamped.origin.x = min(max(0, clamped.origin.x), imageSize.width - clamped.width)
            clamped.origin.y = min(max(0, clamped.origin.y), imageSize.height - clamped.height)
        }

        clamped.origin.x = clamped.origin.x.rounded()
        clamped.origin.y = clamped.origin.y.rounded()
        clamped.size.width = clamped.size.width.rounded()
        clamped.size.height = clamped.size.height.rounded()

        return clamped.isNull ? nil : clamped
    }

    private func handle(at point: CGPoint, in selectionRect: CGRect) -> CornerHandle? {
        let hitSize: CGFloat = 16
        return CornerHandle.allCases.first { handle in
            let handleRect = CGRect(origin: handle.position(in: selectionRect), size: .zero)
                .insetBy(dx: -hitSize, dy: -hitSize)
            return handleRect.contains(point)
        }
    }

    private func updateSelectionSize(width: CGFloat?, height: CGFloat?) {
        guard let cropRect, let imageSize = loadedImage?.pixelSize else { return }

        var newWidth = width ?? cropRect.width
        var newHeight = height ?? cropRect.height

        if aspectLocked, let ratio = lockedAspectRatio, ratio > 0 {
            if let width {
                newWidth = width
                newHeight = width / ratio
            } else if let height {
                newHeight = height
                newWidth = height * ratio
            }
        }

        if scaleExport {
            newWidth = max(newWidth.rounded(), minimumSelectionSize)
            newHeight = max(newHeight.rounded(), minimumSelectionSize)
        } else {
            newWidth = min(max(newWidth.rounded(), minimumSelectionSize), imageSize.width - cropRect.minX)
            newHeight = min(max(newHeight.rounded(), minimumSelectionSize), imageSize.height - cropRect.minY)
        }

        if !scaleExport, aspectLocked, let ratio = lockedAspectRatio, ratio > 0 {
            newHeight = min(max((newWidth / ratio).rounded(), minimumSelectionSize), imageSize.height - cropRect.minY)
            newWidth = min(max((newHeight * ratio).rounded(), minimumSelectionSize), imageSize.width - cropRect.minX)
        }

        self.cropRect = CGRect(x: cropRect.minX, y: cropRect.minY, width: newWidth, height: newHeight)
        userChangedSelection = true
        exportSize = self.cropRect?.size
        syncDimensionText()
    }

    private func applyDimensionText(width: String?, height: String?) {
        let parsedWidth = width.flatMap(parseDimension)
        let parsedHeight = height.flatMap(parseDimension)

        if width != nil, parsedWidth == nil {
            syncDimensionText()
            return
        }

        if height != nil, parsedHeight == nil {
            syncDimensionText()
            return
        }

        updateSelectionSize(width: parsedWidth, height: parsedHeight)
    }

    private func parseDimension(_ text: String) -> CGFloat? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(trimmed), value >= minimumSelectionSize else {
            return nil
        }
        return CGFloat(value)
    }

    private func syncDimensionText() {
        guard let cropRect else {
            widthText = ""
            heightText = ""
            return
        }

        widthText = String(Int(cropRect.width.rounded()))
        heightText = String(Int(cropRect.height.rounded()))
    }

    private func loadImage(from url: URL) throws -> LoadedImage {
        guard let nsImage = NSImage(contentsOf: url) else {
            throw CropError.message("macOS could not read that image file.")
        }

        var proposedRect = CGRect(origin: .zero, size: nsImage.size)
        guard let cgImage = nsImage.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            throw CropError.message("The image loaded, but its pixel data could not be decoded.")
        }

        return LoadedImage(
            url: url,
            nsImage: nsImage,
            cgImage: cgImage,
            pixelSize: CGSize(width: cgImage.width, height: cgImage.height)
        )
    }

    private func defaultCropRect(for imageSize: CGSize) -> CGRect {
        let width = max((imageSize.width * 0.8).rounded(), minimumSelectionSize)
        let height = max((imageSize.height * 0.8).rounded(), minimumSelectionSize)
        return CGRect(
            x: ((imageSize.width - width) / 2).rounded(),
            y: ((imageSize.height - height) / 2).rounded(),
            width: width,
            height: height
        )
    }

    private func croppedImage(from cgImage: CGImage, cropRect: CGRect) -> CGImage? {
        let adjusted = CGRect(
            x: cropRect.minX,
            y: CGFloat(cgImage.height) - cropRect.maxY,
            width: cropRect.width,
            height: cropRect.height
        ).integral

        return cgImage.cropping(to: adjusted)
    }

    private func exportImage(from cgImage: CGImage) -> CGImage? {
        guard scaleExport, let exportSize = exportSize ?? cropRect?.size else { return cgImage }

        let targetWidth = Int(exportSize.width.rounded())
        let targetHeight = Int(exportSize.height.rounded())
        guard targetWidth > 0, targetHeight > 0 else { return nil }

        if targetWidth == cgImage.width, targetHeight == cgImage.height {
            return cgImage
        }

        let colorSpace = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        return context.makeImage()
    }

    private func write(cropped cgImage: CGImage, to url: URL) throws {
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let type = NSBitmapImageRep.FileType(fileExtension: url.pathExtension) else {
            throw CropError.message("Choose a PNG, JPEG, or WebP file extension.")
        }

        let properties: [NSBitmapImageRep.PropertyKey: Any]
        switch type {
        case .jpeg:
            properties = [.compressionFactor: 0.92]
        default:
            properties = [:]
        }

        guard let data = bitmap.representation(using: type, properties: properties) else {
            throw CropError.message("Crop export failed while encoding the image.")
        }

        try data.write(to: url, options: .atomic)
    }

    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Crop Easy"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    private var supportedOpenTypes: [UTType] {
        var types: [UTType] = [.png, .jpeg, .webP, .tiff, .gif, .bmp, .image]
        types.removeDuplicates()
        return types
    }

    private var supportedSaveTypes: [UTType] {
        var types: [UTType] = [.png, .jpeg]
        types.removeDuplicates()
        return types
    }

    private func isSupportedOpenURL(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return true }
        return supportedOpenTypes.contains { type.conforms(to: $0) || $0.conforms(to: type) }
    }
}

enum CropError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message):
            message
        }
    }
}

private extension Array where Element: Equatable {
    mutating func removeDuplicates() {
        var values: [Element] = []
        self = filter {
            guard !values.contains($0) else { return false }
            values.append($0)
            return true
        }
    }
}

private extension CGPoint {
    static func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }
}

private extension NSBitmapImageRep.FileType {
    init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "png":
            self = .png
        case "jpg", "jpeg":
            self = .jpeg
        default:
            return nil
        }
    }
}
