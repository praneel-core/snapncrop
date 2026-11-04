/// Generic snapshot-based undo/redo. Because annotations are value types, storing a snapshot
/// of the whole array per step is cheap and avoids writing an inverse for every operation.
public struct History<State> {
    public private(set) var current: State
    private var undoStack: [State] = []
    private var redoStack: [State] = []

    public init(initial: State) { current = initial }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// Record a new state. Clears redo (a new edit forks history).
    public mutating func commit(_ newState: State) {
        undoStack.append(current)
        current = newState
        redoStack.removeAll()
    }

    @discardableResult
    public mutating func undo() -> Bool {
        guard let previous = undoStack.popLast() else { return false }
        redoStack.append(current)
        current = previous
        return true
    }

    @discardableResult
    public mutating func redo() -> Bool {
        guard let next = redoStack.popLast() else { return false }
        undoStack.append(current)
        current = next
        return true
    }
}
