//
//  TarnModelContainer.swift
//  Tarn
//
//  Centralizes SwiftData schema setup and migration.
//

import Foundation
import SwiftData

enum TarnSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            ConnectionProfile.self,
            SavedQuery.self,
            QueryFolder.self,
            TabState.self,
        ]
    }
}

enum TarnSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 1, 0)

    static var models: [any PersistentModel.Type] {
        [
            ConnectionProfile.self,
            SavedQuery.self,
            QueryFolder.self,
            TabState.self,
            QueryHistory.self,
        ]
    }
}

enum TarnSchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 2, 0)

    static var models: [any PersistentModel.Type] {
        [
            ConnectionProfile.self,
            SavedQuery.self,
            QueryFolder.self,
            TabState.self,
            QueryHistory.self,
            DatabaseFileProfile.self,
        ]
    }
}

enum TarnMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            TarnSchemaV1.self,
            TarnSchemaV2.self,
            TarnSchemaV3.self,
        ]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: TarnSchemaV1.self, toVersion: TarnSchemaV2.self),
            .lightweight(fromVersion: TarnSchemaV2.self, toVersion: TarnSchemaV3.self),
        ]
    }
}

enum TarnModelContainerFactory {
    static var currentSchema: Schema {
        Schema(versionedSchema: TarnSchemaV3.self)
    }

    static func makeModelContainer(
        isStoredInMemoryOnly: Bool = false,
        url: URL? = nil
    ) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration("default", schema: currentSchema, url: url)
        } else {
            configuration = ModelConfiguration(
                "default",
                schema: currentSchema,
                isStoredInMemoryOnly: isStoredInMemoryOnly
            )
        }

        return try ModelContainer(
            for: currentSchema,
            migrationPlan: TarnMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
