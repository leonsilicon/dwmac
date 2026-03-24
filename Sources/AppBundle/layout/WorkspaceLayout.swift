import AppKit
import Common

struct MasterStackLayoutMetrics {
    let workspaceRect: Rect
    let tilingHeight: CGFloat
    let gapH: CGFloat
    let gapV: CGFloat
    let orientation: Orientation
    let masterPosition: MasterPosition
    let windows: [Window]
    let mfact: CGFloat

    var width: CGFloat { workspaceRect.width }
    var height: CGFloat { tilingHeight }
    var hasSplit: Bool { windows.count > 1 }
    var masterWindow: Window? { windows.first }

    var splitLength: CGFloat {
        switch orientation {
            case .h: width - gapH
            case .v: height - gapV
        }
    }

    var masterWidth: CGFloat {
        guard hasSplit else { return width }
        return orientation == .h ? splitLength * mfact : width
    }

    var masterHeight: CGFloat {
        guard hasSplit else { return height }
        return orientation == .h ? height : splitLength * mfact
    }

    var stackWidth: CGFloat {
        guard hasSplit else { return 0 }
        return orientation == .h
            ? width - masterWidth - gapH
            : (width - CGFloat(windows.count - 2) * gapH) / CGFloat(windows.count - 1)
    }

    var stackHeight: CGFloat {
        guard hasSplit else { return 0 }
        return orientation == .h
            ? (height - CGFloat(windows.count - 2) * gapV) / CGFloat(windows.count - 1)
            : height - masterHeight - gapV
    }

    var masterOrigin: CGPoint {
        switch orientation {
            case .h where masterPosition == .right:
                workspaceRect.topLeftCorner.addingXOffset(stackWidth + gapH)
            case .h:
                workspaceRect.topLeftCorner
            case .v:
                workspaceRect.topLeftCorner
        }
    }

    var stackOrigin: CGPoint {
        switch orientation {
            case .h where masterPosition == .right:
                workspaceRect.topLeftCorner
            case .h:
                workspaceRect.topLeftCorner.addingXOffset(masterWidth + gapH)
            case .v:
                workspaceRect.topLeftCorner.addingYOffset(masterHeight + gapV)
        }
    }

    func resizedMfact(for window: Window, currentRect: Rect) -> CGFloat? {
        guard hasSplit else { return nil }
        guard splitLength > 0 else { return nil }
        guard let masterWindow else { return nil }
        guard windows.contains(window) else { return nil }

        let newMasterSpan: CGFloat = switch orientation {
            case .h:
                if window == masterWindow {
                    switch masterPosition {
                        case .left:
                            currentRect.maxX - workspaceRect.minX
                        case .right:
                            splitLength - (currentRect.minX - workspaceRect.minX - gapH)
                    }
                } else {
                    switch masterPosition {
                        case .left:
                            currentRect.minX - workspaceRect.minX - gapH
                        case .right:
                            splitLength - (currentRect.maxX - workspaceRect.minX)
                    }
                }
            case .v:
                if window == masterWindow {
                    currentRect.maxY - workspaceRect.minY
                } else {
                    currentRect.minY - workspaceRect.minY - gapV
                }
        }

        let clampedMasterSpan = newMasterSpan.coerceIn(0 ... splitLength)
        return (clampedMasterSpan / splitLength).coerceIn(0.05 ... 0.95)
    }
}

extension Workspace {
    @MainActor
    func layoutWorkspace() async throws {
        if isEffectivelyEmpty { return }
        let context = LayoutContext(self)

        // Layout tiling windows
        if let metrics = masterStackLayoutMetrics(context.resolvedGaps) {
            try await layoutMasterStack(metrics, context)
        }

        // Layout floating windows
        for window in children.filterIsInstance(of: Window.self).filter({ $0.isFloating }) {
            window.lastAppliedLayoutPhysicalRect = nil
            window.lastAppliedLayoutVirtualRect = nil
            try await window.layoutFloatingWindow(context)
        }
    }

    @MainActor
    private func layoutMasterStack(_ metrics: MasterStackLayoutMetrics, _ context: LayoutContext) async throws {
        if metrics.windows.count == 1 {
            let window = metrics.windows[0]
            try await layoutWindow(window, metrics.workspaceRect.topLeftCorner, metrics.width, metrics.height, metrics.workspaceRect, context)
            return
        }

        // Master window (first in list)
        try await layoutWindow(metrics.windows[0], metrics.masterOrigin, metrics.masterWidth, metrics.masterHeight, metrics.workspaceRect, context)

        // Stack windows
        for i in 1 ..< metrics.windows.count {
            let stackPoint: CGPoint = if metrics.orientation == .h {
                metrics.stackOrigin.addingYOffset(CGFloat(i - 1) * (metrics.stackHeight + metrics.gapV))
            } else {
                metrics.stackOrigin.addingXOffset(CGFloat(i - 1) * (metrics.stackWidth + metrics.gapH))
            }
            try await layoutWindow(metrics.windows[i], stackPoint, metrics.stackWidth, metrics.stackHeight, metrics.workspaceRect, context)
        }
    }

    @MainActor
    func masterStackLayoutMetrics() -> MasterStackLayoutMetrics? {
        masterStackLayoutMetrics(ResolvedGaps(gaps: config.gaps, monitor: workspaceMonitor))
    }

    @MainActor
    private func masterStackLayoutMetrics(_ resolvedGaps: ResolvedGaps) -> MasterStackLayoutMetrics? {
        let windows = tilingWindows
        guard !windows.isEmpty else { return nil }
        guard layout != .floating else { return nil }

        return MasterStackLayoutMetrics(
            workspaceRect: workspaceMonitor.visibleRectPaddedByOuterGaps,
            tilingHeight: workspaceMonitor.visibleRectPaddedByOuterGaps.height - 1,
            gapH: CGFloat(resolvedGaps.inner.horizontal),
            gapV: CGFloat(resolvedGaps.inner.vertical),
            orientation: orientation,
            masterPosition: config.masterPosition,
            windows: windows,
            mfact: mfact,
        )
    }

    @MainActor
    private func layoutWindow(_ window: Window, _ point: CGPoint, _ width: CGFloat, _ height: CGFloat, _ virtual: Rect, _ context: LayoutContext) async throws {
        let physicalRect = Rect(topLeftX: point.x, topLeftY: point.y, width: width, height: height)

        if window.windowId != currentlyManipulatedWithMouseWindowId {
            window.lastAppliedLayoutVirtualRect = virtual
            // In flat model, no rootTilingContainer. Check if window is fullscreen and matches criteria.
            // Assuming mostRecentWindowRecursive logic works on Workspace now.
            if window.isFullscreen && window == context.workspace.mostRecentWindowRecursive {
                window.lastAppliedLayoutPhysicalRect = nil
                window.layoutFullscreen(context)
            } else {
                window.lastAppliedLayoutPhysicalRect = physicalRect
                window.isFullscreen = false
                window.setAxFrame(point, CGSize(width: width, height: height))
            }
        }
    }
}

private struct LayoutContext {
    let workspace: Workspace
    let resolvedGaps: ResolvedGaps

    @MainActor
    init(_ workspace: Workspace) {
        self.workspace = workspace
        self.resolvedGaps = ResolvedGaps(gaps: config.gaps, monitor: workspace.workspaceMonitor)
    }
}

extension Window {
    @MainActor
    fileprivate func layoutFloatingWindow(_ context: LayoutContext) async throws {
        let workspace = context.workspace
        let targetMonitor = workspace.workspaceMonitor

        if config.centerFloatingWindows && windowId != currentlyManipulatedWithMouseWindowId {
            if let windowSize = try await getAxSize() ?? lastFloatingSize {
                let monitorRect = targetMonitor.visibleRect
                let topLeft = CGPoint(
                    x: monitorRect.topLeftX + (monitorRect.width - windowSize.width) / 2,
                    y: monitorRect.topLeftY + (monitorRect.height - windowSize.height) / 2
                )
                setAxFrame(topLeft, nil)
            }
        } else {
            // Optimization: Only check for monitor drift if the workspace's monitor has changed
            // since the last layout of this window.
            // This avoids expensive AX calls (getCenter/getAxTopLeftCorner) on every layout cycle.
            if lastLayoutMonitor?.rect.topLeftCorner != targetMonitor.rect.topLeftCorner {
                let currentMonitor = try await getCenter()?.monitorApproximation
                if let currentMonitor, let windowTopLeftCorner = try await getAxTopLeftCorner(), workspace != currentMonitor.activeWorkspace {
                    let xProportion = (windowTopLeftCorner.x - currentMonitor.visibleRect.topLeftX) / currentMonitor.visibleRect.width
                    let yProportion = (windowTopLeftCorner.y - currentMonitor.visibleRect.topLeftY) / currentMonitor.visibleRect.height

                    let moveTo = workspace.workspaceMonitor
                    setAxFrame(CGPoint(
                        x: moveTo.visibleRect.topLeftX + xProportion * moveTo.visibleRect.width,
                        y: moveTo.visibleRect.topLeftY + yProportion * moveTo.visibleRect.height,
                    ), nil)
                }
            }
        }
        lastLayoutMonitor = targetMonitor

        if isFullscreen {
            layoutFullscreen(context)
            isFullscreen = false
        }
    }

    @MainActor
    fileprivate func layoutFullscreen(_ context: LayoutContext) {
        let monitorRect = noOuterGapsInFullscreen
            ? context.workspace.workspaceMonitor.visibleRect
            : context.workspace.workspaceMonitor.visibleRectPaddedByOuterGaps
        setAxFrame(monitorRect.topLeftCorner, CGSize(width: monitorRect.width, height: monitorRect.height))
    }
}
