@testable import AppBundle
import XCTest

@MainActor
final class ResizeWithMouseTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testResizeMasterWithMouseAdjustsHorizontalMfactAndRelayoutsStack() async throws {
        config.gaps = Gaps(
            inner: .init(vertical: 10, horizontal: 10),
            outer: .zero,
        )

        let workspace = Workspace.get(byName: name).apply {
            $0.layout = .masterStack
            $0.orientation = .h
        }
        let master = TestWindow.new(id: 1, parent: workspace, rect: Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100))
        let stack = TestWindow.new(id: 2, parent: workspace, rect: Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100))

        try await workspace.layoutWorkspace()

        master.setAxFrame(nil, CGSize(width: 1200, height: 1079))
        try await resizeWithMouse(master)

        XCTAssertEqual(workspace.mfact, 1200 / 1910, accuracy: 0.001)
        try await workspace.layoutWorkspace()

        XCTAssertEqual(master.lastAppliedLayoutPhysicalRect?.width ?? -1, 1200, accuracy: 0.001)
        XCTAssertEqual(stack.lastAppliedLayoutPhysicalRect?.topLeftX ?? -1, 1210, accuracy: 0.001)
    }

    func testResizeStackWithMouseAdjustsHorizontalMfactForRightMaster() async throws {
        config.gaps = Gaps(
            inner: .init(vertical: 10, horizontal: 10),
            outer: .zero,
        )
        config.masterPosition = .right

        let workspace = Workspace.get(byName: name).apply {
            $0.layout = .masterStack
            $0.orientation = .h
        }
        _ = TestWindow.new(id: 1, parent: workspace, rect: Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100))
        let stack = TestWindow.new(id: 2, parent: workspace, rect: Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100))

        try await workspace.layoutWorkspace()

        stack.setAxFrame(nil, CGSize(width: 800, height: 1079))
        try await resizeWithMouse(stack)

        XCTAssertEqual(workspace.mfact, 1110 / 1910, accuracy: 0.001)
    }

    func testResizeStackOuterEdgeDoesNotAdjustHorizontalMfact() async throws {
        config.gaps = Gaps(
            inner: .init(vertical: 10, horizontal: 10),
            outer: .zero,
        )

        let workspace = Workspace.get(byName: name).apply {
            $0.layout = .masterStack
            $0.orientation = .h
        }
        _ = TestWindow.new(id: 1, parent: workspace, rect: Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100))
        let stack = TestWindow.new(id: 2, parent: workspace, rect: Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100))

        try await workspace.layoutWorkspace()
        let originalMfact = workspace.mfact

        stack.setAxFrame(nil, CGSize(width: 800, height: 1079))
        try await resizeWithMouse(stack)

        XCTAssertEqual(workspace.mfact, originalMfact, accuracy: 0.001)
    }

    func testResizeStackWithMouseAdjustsVerticalMfact() async throws {
        config.gaps = Gaps(
            inner: .init(vertical: 10, horizontal: 10),
            outer: .zero,
        )

        let workspace = Workspace.get(byName: name).apply {
            $0.layout = .masterStack
            $0.orientation = .v
        }
        _ = TestWindow.new(id: 1, parent: workspace, rect: Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100))
        let stack = TestWindow.new(id: 2, parent: workspace, rect: Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100))

        try await workspace.layoutWorkspace()

        stack.setAxFrame(CGPoint(x: 0, y: 600), CGSize(width: 1920, height: 479))
        try await resizeWithMouse(stack)

        XCTAssertEqual(workspace.mfact, 590 / 1069, accuracy: 0.001)
    }
}
