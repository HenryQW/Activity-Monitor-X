extension Array {
    /// Appends `element`, then drops the oldest elements so at most `limit` remain.
    public mutating func append(_ element: Element, keepingLast limit: Int) {
        append(element)
        if count > limit { removeFirst(count - limit) }
    }
}
