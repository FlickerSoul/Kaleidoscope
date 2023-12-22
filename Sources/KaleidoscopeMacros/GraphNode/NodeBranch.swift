//
//  NodeBranch.swift
//
//
//  Created by Larry Zeng on 12/22/23.
//

public extension Node {
    typealias BranchHit = HIR.ScalarByteRange

    struct BranchContent: Hashable, Copy, IntoNode {
        var branches: [BranchHit: NodeId] = [:]
        var miss: NodeId? = nil

        init(branches: [BranchHit: NodeId] = [:], miss: NodeId? = nil) {
            self.branches = branches
            self.miss = miss
        }

        public static func == (lhs: Node.BranchContent, rhs: Node.BranchContent) -> Bool {
            return lhs.branches == rhs.branches && lhs.miss == rhs.miss
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(branches)
            hasher.combine(miss)
        }

        public func copy() -> Self {
            return .init(
                branches: branches,
                miss: miss
            )
        }

        public func into() -> Node {
            return .Branch(self)
        }

        mutating func merge(other: BranchContent, graph: inout Graph) throws {
            switch (miss, other.miss) {
            case (nil, _):
                // if branch's miss is empty, use other's
                miss = other.miss
            case (.some(let lhs), .some(let rhs)) where lhs != rhs:
                // if both have misses, merge two misses
                miss = try graph.merge(lhs, rhs)
            case _:
                // otherwise, we don't care
                break
            }

            var combined: [Node.BranchHit: NodeId] = branches

            for (hit, hitId) in other.branches {
                // if current branch has the same jump, merge
                // otherwise, merge the jump to the current table
                if let val = combined[hit] {
                    if val == hitId {
                        // if they are the same branch, skip, otherwise
                        // will be an infinite loop
                        continue
                    }
                    combined[hit] = try graph.merge(hitId, val)
                } else {
                    combined[hit] = hitId
                }
            }

            let sortedHits: [Node.BranchHit] = combined.keys.sorted()
            var merged: [Node.BranchHit] = []
            var mergedId: [NodeId] = []

            if sortedHits.count > 0 {
                // add initial thing
                merged.append(sortedHits[0])
                mergedId.append(combined[sortedHits[0]]!)

                // looping through others
                var index = 1

                // go through all sorted hits
                while index < sortedHits.count {
                    // get the one we are merging
                    var curr: HIR.ScalarByteRange? = sortedHits[index]
                    let currId = combined[curr!]!

                    // prepare spaces, and get every ranges that have intersection with curr
                    var stack: [Node.BranchHit] = []
                    var stackId: [NodeId] = []

                    var queued = merged.last

                    // if the queued's upper bound is creater or equal to curr.lowerBound,
                    // they are intersecting. e.g.
                    //  ---- -- -
                    //     -------  or
                    //  -------
                    //        -------
                    while let queuedRes = queued, queuedRes.upperBound >= curr!.lowerBound {
                        stack.append(merged.removeLast())
                        stackId.append(mergedId.removeLast())

                        queued = merged.last
                    }

                    while stack.count > 0 {
                        guard let currUnwrapped = curr else {
                            throw GraphError.MergingRangeError
                        }

                        let comp = stack.removeLast()
                        let compId = stackId.removeLast()

                        if comp.lowerBound < currUnwrapped.lowerBound {
                            let left = comp.lowerBound ... (currUnwrapped.lowerBound - 1)
                            merged.append(left)
                            mergedId.append(compId)

                            let mid = currUnwrapped.lowerBound ... comp.upperBound
                            merged.append(mid)
                            try mergedId.append(graph.merge(currId, compId))

                            if comp.upperBound < currUnwrapped.upperBound {
                                curr = comp.upperBound + 1 ... currUnwrapped.upperBound
                            } else {
                                curr = nil
                            }
                        } else if currUnwrapped.lowerBound <= comp.lowerBound {
                            if currUnwrapped.lowerBound < comp.lowerBound {
                                let left = currUnwrapped.lowerBound ... comp.lowerBound - 1
                                merged.append(left)
                                mergedId.append(currId)
                            }

                            let mid = comp
                            merged.append(mid)
                            try mergedId.append(graph.merge(currId, compId))

                            if comp.upperBound < currUnwrapped.upperBound {
                                curr = comp.upperBound + 1 ... currUnwrapped.upperBound
                            } else {
                                curr = nil
                            }
                        }
                    }

                    if let curr = curr {
                        merged.append(curr)
                        mergedId.append(currId)
                    }

                    index += 1
                }
            }

            branches = Dictionary(uniqueKeysWithValues: zip(merged, mergedId))
        }

        func contains(_ val: HIR.ScalarByte) -> NodeId? {
            for (range, nodeId) in branches {
                if range.contains(val) {
                    return nodeId
                }
            }

            return nil
        }
    }
}

extension Node.BranchContent: CustomStringConvertible {
    public var description: String {
        return "{" +
            branches.map { key, val in
                "\(key) => \(val)"
            }.joined(separator: ", ") +
            (miss == nil ? "" : " | _ => \(miss!)") +
            "}"
    }
}
