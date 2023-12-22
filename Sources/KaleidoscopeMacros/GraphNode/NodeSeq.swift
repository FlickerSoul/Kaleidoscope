//
//  NodeSeq.swift
//
//
//  Created by Larry Zeng on 12/22/23.
//

public extension Node {
    enum SeqMiss: Hashable {
        case first(NodeId)
        case anytime(NodeId)

        var miss: NodeId {
            switch self {
            case .first(let id), .anytime(let id):
                return id
            }
        }

        var anytimeMiss: NodeId? {
            switch self {
            case .anytime(let id):
                return id
            case _:
                return nil
            }
        }

        static func toFirst(_ id: NodeId?) -> Self? {
            if let id = id {
                return .first(id)
            }
            return nil
        }

        static func toAnytime(_ id: NodeId?) -> Self? {
            if let id = id {
                return .anytime(id)
            }
            return nil
        }
    }

    class SeqContent: Copy, IntoNode, Hashable, CustomStringConvertible {
        var seq: HIR.ScalarBytes
        var then: NodeId
        var miss: SeqMiss?

        required init(seq: HIR.ScalarBytes, then: NodeId, miss: SeqMiss? = nil) {
            self.seq = seq
            self.then = then
            self.miss = miss
        }

        func copy() -> Self {
            return .init(seq: seq, then: then, miss: miss)
        }

        func into() -> Node {
            return Node.Seq(self)
        }

        public func toBranch(graph: inout Graph) -> Node.BranchContent {
            let hit = seq.remove(at: 0)
            let missId = miss?.miss

            let thenId: NodeId
            if seq.count == 0 {
                thenId = then
            } else {
                thenId = graph.push(self)
            }

            return .init(branches: [hit.scalarByteRange: thenId], miss: missId)
        }

        public func asRemainder(at: Int, graph: inout Graph) -> NodeId {
            seq = Array(seq[at ..< seq.count])

            if seq.count == 0 {
                return then
            } else {
                return graph.push(self)
            }
        }

        public func split(at: Int, graph: inout Graph) -> SeqContent? {
            switch at {
            case 0:
                return nil
            case seq.count:
                return self
            case _:
                break
            }

            let current = seq[0 ..< at]
            let next = seq[at ..< seq.count]

            let nextMiss: Node.SeqMiss?
            if let miss = miss?.anytimeMiss {
                nextMiss = .anytime(miss)
            } else {
                nextMiss = nil
            }

            let nextId = graph.push(Self(seq: Array(next), then: then, miss: nextMiss))

            seq = Array(current)
            then = nextId

            return self
        }

        public func miss(first val: NodeId?) -> Self {
            if let val = val {
                miss = .first(val)
            } else {
                miss = nil
            }
            return self
        }

        public func miss(anytime val: NodeId?) -> Self {
            if let val = val {
                miss = .anytime(val)
            } else {
                miss = nil
            }

            return self
        }

        public func prefix(with other: SeqContent) -> (HIR.ScalarBytes, SeqMiss)? {
            var count = 0
            while count < other.seq.count && count < seq.count {
                if other.seq[count] == seq[count] {
                    count += 1
                } else {
                    break
                }
            }

            if count == 0 {
                return nil
            }

            let newSeq = Array(seq[0 ..< count])

            switch (miss, other.miss) {
            case (nil, .some(let newMiss)), (.some(let newMiss), nil):
                return (newSeq, newMiss)
            case _:
                return nil
            }
        }

        public static func == (lhs: Node.SeqContent, rhs: Node.SeqContent) -> Bool {
            return lhs.seq == rhs.seq && lhs.then == rhs.then && lhs.miss == rhs.miss
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(seq)
            hasher.combine(then)
            hasher.combine(miss)
        }

        public var description: String {
            var des = "`\(seq.map { Unicode.Scalar($0)!.escaped(asASCII: true) }.joined())` => \(then)"
            if let miss = miss {
                des += " | _ => \(miss)"
            }

            return des
        }
    }
}
