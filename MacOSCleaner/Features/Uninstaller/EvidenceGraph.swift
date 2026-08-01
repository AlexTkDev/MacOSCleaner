import Foundation

public struct EvidenceGraphNode: Sendable, Hashable {
    public let url: URL
    public var evidence: Set<Evidence>
    public var parents: Set<URL>
    public var children: Set<URL>

    public init(url: URL, evidence: Set<Evidence> = [], parents: Set<URL> = [], children: Set<URL> = []) {
        self.url = NormalizedPath.canonicalize(url)
        self.evidence = evidence
        self.parents = Set(parents.map(NormalizedPath.canonicalize))
        self.children = Set(children.map(NormalizedPath.canonicalize))
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(url) }
    public static func == (lhs: EvidenceGraphNode, rhs: EvidenceGraphNode) -> Bool { lhs.url == rhs.url }
}

public actor EvidenceGraph {
    private var nodes: [URL: EvidenceGraphNode] = [:]
    private let identity: AppIdentity

    public static let boundaryRoots: Set<String> = [
        "Application Support", "Caches", "Containers", "Group Containers",
        "WebKit", "HTTPStorages", "Application Scripts",
        "Preferences", "ByHost", "Saved Application State",
    ]

    public init(identity: AppIdentity) {
        self.identity = identity
        let seedURL = NormalizedPath.canonicalize(identity.bundleURL)
        let seed = EvidenceGraphNode(url: seedURL, evidence: [.bundleIDExact])
        nodes[seedURL] = seed
    }

    public func record(_ evidence: Evidence, for url: URL) {
        let u = NormalizedPath.canonicalize(url)
        var node = nodes[u] ?? EvidenceGraphNode(url: u)
        node.evidence.insert(evidence)
        nodes[u] = node
    }

    public func record(_ evidences: Set<Evidence>, for url: URL) {
        let u = NormalizedPath.canonicalize(url)
        var node = nodes[u] ?? EvidenceGraphNode(url: u)
        node.evidence.formUnion(evidences)
        nodes[u] = node
    }

    public func attach(_ url: URL, to parent: URL, via: Evidence) {
        let childURL = NormalizedPath.canonicalize(url)
        let parentURL = NormalizedPath.canonicalize(parent)

        var child = nodes[childURL] ?? EvidenceGraphNode(url: childURL)
        child.parents.insert(parentURL)
        child.evidence.insert(via)
        nodes[childURL] = child

        var parentNode = nodes[parentURL] ?? EvidenceGraphNode(url: parentURL)
        parentNode.children.insert(childURL)
        nodes[parentURL] = parentNode
    }

    public func node(for url: URL) -> EvidenceGraphNode? {
        nodes[NormalizedPath.canonicalize(url)]
    }

    public func allNodes() -> [EvidenceGraphNode] {
        Array(nodes.values)
    }

    public func allURLs() -> Set<URL> {
        Set(nodes.keys)
    }

    public func propagateFromSeeds(maxDepth: Int = 5) {
        let strongEvidence: Set<Evidence> = [
            .bundleIDExact, .bundleIDPrefix, .appNameExact, .appNamePrefix,
            .packageReceipt, .container, .appGroup, .spotlightBundleAttr,
        ]
        let seeds = nodes.filter { !strongEvidence.isDisjoint(with: $0.value.evidence) }
        for seed in seeds.values {
            propagate(from: seed.url, depth: 0, maxDepth: maxDepth)
        }
    }

    private func propagate(from url: URL, depth: Int, maxDepth: Int) {
        guard depth < maxDepth else { return }
        let u = NormalizedPath.canonicalize(url)
        guard let node = nodes[u] else { return }

        let isBoundary = EvidenceGraph.boundaryRoots.contains(u.lastPathComponent)
        if depth > 0 && isBoundary { return }

        for child in node.children {
            let childKey = NormalizedPath.canonicalize(child)
            if var childNode = nodes[childKey] {
                if !childNode.evidence.contains(.parentDirectory) {
                    childNode.evidence.insert(.parentDirectory)
                    nodes[childKey] = childNode
                }
                propagate(from: childKey, depth: depth + 1, maxDepth: maxDepth)
            }
        }
    }

    public func count() -> Int { nodes.count }
}
