import Foundation

public struct EvidenceGraphNode: Sendable, Hashable {
    public let url: URL
    public var evidence: Set<Evidence>
    public var parents: Set<URL>
    public var children: Set<URL>

    public init(url: URL, evidence: Set<Evidence> = [], parents: Set<URL> = [], children: Set<URL> = []) {
        self.url = url
        self.evidence = evidence
        self.parents = parents
        self.children = children
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
        let seed = EvidenceGraphNode(url: identity.bundleURL, evidence: [.bundleIDExact])
        nodes[identity.bundleURL] = seed
    }

    public func record(_ evidence: Evidence, for url: URL) {
        var node = nodes[url] ?? EvidenceGraphNode(url: url)
        node.evidence.insert(evidence)
        nodes[url] = node
    }

    public func record(_ evidences: Set<Evidence>, for url: URL) {
        var node = nodes[url] ?? EvidenceGraphNode(url: url)
        node.evidence.formUnion(evidences)
        nodes[url] = node
    }

    public func attach(_ url: URL, to parent: URL, via: Evidence) {
        var child = nodes[url] ?? EvidenceGraphNode(url: url)
        child.parents.insert(parent)
        nodes[url] = child

        var parentNode = nodes[parent] ?? EvidenceGraphNode(url: parent)
        parentNode.children.insert(url)
        nodes[parent] = parentNode

        child.evidence.insert(via)
        nodes[url] = child
    }

    public func node(for url: URL) -> EvidenceGraphNode? {
        nodes[url]
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
        guard let node = nodes[url] else { return }

        let isBoundary = EvidenceGraph.boundaryRoots.contains(url.lastPathComponent)
        if depth > 0 && isBoundary { return }

        for child in node.children {
            if var childNode = nodes[child] {
                if !childNode.evidence.contains(.parentDirectory) {
                    childNode.evidence.insert(.parentDirectory)
                    nodes[child] = childNode
                }
                propagate(from: child, depth: depth + 1, maxDepth: maxDepth)
            }
        }
    }

    public func count() -> Int { nodes.count }
}
