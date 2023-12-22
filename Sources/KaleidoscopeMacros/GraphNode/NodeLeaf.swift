//
//  NodeLeaf.swift
//
//
//  Created by Larry Zeng on 12/22/23.
//

public extension Node {
    struct LeafContent: Hashable, Copy, IntoNode {
        var endId: EndsId

        init(endId: EndsId) {
            self.endId = endId
        }

        public static func == (lhs: Node.LeafContent, rhs: Node.LeafContent) -> Bool {
            return lhs.endId == rhs.endId
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(endId)
        }

        public func copy() -> Self {
            return .init(endId: endId)
        }

        public func into() -> Node {
            return .Leaf(self)
        }
    }
}

extension Node.LeafContent: CustomStringConvertible {
    public var description: String {
        return "@\(endId)"
    }
}
