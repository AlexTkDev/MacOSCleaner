import Foundation

public struct DatabaseToolsRule: ApplicationRule {
    public let displayName = "Database Tools"
    public let supportedBundleIDs: Set<String> = [
        "com.tableplus.TablePlus",
        "com.tinyapp.TablePlus",
        "org.jkiss.dbeaver.core.product",
        "com.sequel-ace.sequel-ace",
        "com.oracle.mysql.workbench",
        "org.pgadmin.pgadmin4",
        "com.mongodb.compass",
        "com.redis.RedisInsight",
        "com.postgresapp.Postgres2",
    ]
    public let supportedTeamIDs: Set<String> = []
    public let supportedAppNames: Set<String> = [
        "TablePlus", "DBeaver", "Sequel Ace", "MySQL Workbench",
        "pgAdmin", "MongoDB Compass", "RedisInsight", "PostgreSQL",
    ]

    public init() {}

    public func evidence(for candidate: URL, identity: AppIdentity) -> [ArtifactEvidence] {
        let path = candidate.path.lowercased()
        var evidence: [ArtifactEvidence] = []

        if path.contains("/containers/com.tableplus.tableplus") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 90))
        }
        if path.contains("/containers/com.tinyapp.tableplus") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 90))
        }
        if path.contains("/preferences/com.tableplus.tableplus.plist") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }
        if path.contains("/preferences/com.tinyapp.tableplus.plist") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }
        if path.contains("/caches/com.tableplus.tableplus") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 50))
        }
        if path.contains("/caches/com.tinyapp.tableplus") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 50))
        }

        if path.contains("/dbeaverdata") || path.contains("/.dbeaver") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 90))
        }
        if path.contains("/application support/dbeaverdata") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/caches/org.jkiss.dbeaver") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 50))
        }
        if path.contains("/preferences/org.jkiss.dbeaver") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }

        if path.contains("/containers/com.sequel-ace.sequel-ace") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 90))
        }
        if path.contains("/group containers/") && path.contains("com.sequel-ace.sequel-ace") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 85))
        }

        if path.contains("/application support/mysql/workbench") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/preferences/com.oracle.mysql.workbench.plist") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }

        if path.contains("/application support/pgadmin") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/caches/org.pgadmin.pgadmin4") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 50))
        }

        if path.contains("/application support/mongodb compass") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/caches/com.mongodb.compass") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 50))
        }

        if path.contains("/application support/redisinsight") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/caches/com.redis.redisinsight") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 50))
        }

        if path.contains("/application support/postgres") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/containers/com.postgresapp.postgres2") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 90))
        }
        if path.contains("/preferences/com.postgresapp.postgres2.plist") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }
        if path.contains("/saved application state/com.postgresapp.postgres2") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 60))
        }
        if path.contains("/usr/local/var/postgres") || path.contains("/opt/homebrew/var/postgresql") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 80))
        }

        return evidence
    }
}
