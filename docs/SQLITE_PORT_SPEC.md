# SQLiteGUI — Native macOS SQLite Inspector

## Specification for Porting PostgresGUI to SQLite

**Working name:** SQLiteGUI
**Source repository:** [github.com/griffinwork40/postgresgui](https://github.com/griffinwork40/postgresgui)
**Upstream:** [github.com/postgresgui/postgresgui](https://github.com/postgresgui/postgresgui)
**Date:** 2026-08-11
**Status:** Draft specification — implementation not yet started

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Existing Architecture](#2-existing-architecture)
3. [Repository / Component Map](#3-repository--component-map)
4. [PostgreSQL Dependency Map](#4-postgresql-dependency-map)
5. [KEEP / ADAPT / REPLACE / REMOVE Analysis](#5-keep--adapt--replace--remove-analysis)
6. [Proposed SQLite Architecture](#6-proposed-sqlite-architecture)
7. [SQLite Library Recommendation](#7-sqlite-library-recommendation)
8. [MVP Product Specification](#8-mvp-product-specification)
9. [SQLite-Specific Features](#9-sqlite-specific-features)
10. [UX Flows](#10-ux-flows)
11. [Data Model / Type-Handling Strategy](#11-data-model--type-handling-strategy)
12. [Query Execution Architecture](#12-query-execution-architecture)
13. [Editing / Write Architecture](#13-editing--write-architecture)
14. [Safety Model](#14-safety-model)
15. [Performance Strategy](#15-performance-strategy)
16. [Testing Strategy](#16-testing-strategy)
17. [Migration Plan](#17-migration-plan)
18. [Licensing Findings](#18-licensing-findings)
19. [Known Technical Risks](#19-known-technical-risks)
20. [Open Questions](#20-open-questions)
21. [Implementation Phases](#21-implementation-phases)
22. [Concrete First Implementation Slice](#22-concrete-first-implementation-slice)

---

## 1. Executive Summary

PostgresGUI is a well-architected native macOS PostgreSQL client built with Swift and SwiftUI, targeting macOS 26. The codebase is 27,244 lines of Swift across 155 files with a clean protocol-oriented architecture that separates database-specific implementation from UI and business logic.

**The codebase is highly reusable for an SQLite port.** The developers anticipated backend swapping — every PostgreSQL-specific type lives behind a protocol. The migration is concentrated in a small, well-defined surface:

| Category | Files | Lines | Effort |
|----------|-------|-------|--------|
| KEEP (zero changes) | 83 | ~14,800 | None |
| ADAPT (surgical edits) | 38 | ~8,200 | Low–Medium |
| REPLACE (new implementation) | 11 | ~2,400 | Medium–High |
| REMOVE (delete) | 23 | ~1,800 | Trivial |

The core rewrite is just **4 files** (~1,400 lines) in the `Services/Postgres/` folder — the connection manager, query executor, result mapper, and database connection wrapper. Everything above that layer (services, state, view models, views) works through protocols and requires only surface-level adaptation.

**Recommended SQLite library:** GRDB.swift — it provides the best balance of SQLite feature coverage, Swift idiom alignment, performance, and maintenance activity for an inspector-class application that needs direct access to SQLite's full capability surface.

**Recommended first coding task:** Implement the minimal path from app launch → open `.sqlite` file → discover tables → select table → display rows. This slice touches exactly 4 new files and ~10 adapted files, validating the full vertical stack before building secondary features.

---

## 2. Existing Architecture

### 2.1 High-Level Architecture

PostgresGUI follows a layered MVVM architecture with protocol-oriented dependency injection:

```
┌─────────────────────────────────────────────────────────┐
│  SwiftUI Views (Containers, Components, Primitives)      │
│  ~6,800 lines across 40 files                           │
├─────────────────────────────────────────────────────────┤
│  ViewModels (@Observable, @MainActor)                    │
│  ~2,000 lines across 8 files                            │
├─────────────────────────────────────────────────────────┤
│  State (@Observable, @MainActor)                         │
│  ~2,400 lines across 6 files                            │
├─────────────────────────────────────────────────────────┤
│  Application Services (protocol-backed)                  │
│  DatabaseService, ConnectionService, QueryService,       │
│  TableService, MetadataService, TabService, etc.         │
│  ~2,300 lines across 12 files                           │
├─────────────────────────────────────────────────────────┤
│  Service Protocols (the abstraction boundary)            │
│  ~750 lines across 15 files                             │
├─────────────────────────────────────────────────────────┤
│  PostgreSQL Implementation (below the protocol line)     │
│  PostgresConnectionManager, PostgresQueryExecutor,       │
│  PostgresDatabaseConnection, PostgresResultMapper        │
│  ~1,400 lines across 4 files                            │
├─────────────────────────────────────────────────────────┤
│  SSH / Network Infrastructure                            │
│  SSHTunnelManager, SSHKeyParser, RSASHA512               │
│  ~1,230 lines across 3 files                            │
├─────────────────────────────────────────────────────────┤
│  External Dependencies                                   │
│  PostgresNIO, Citadel (SSH), swift-nio, swift-nio-ssh,   │
│  swift-nio-ssl, swift-crypto, swift-log                  │
└─────────────────────────────────────────────────────────┘
```

### 2.2 Key Architectural Properties

**Protocol-oriented DI.** Every database operation goes through a protocol boundary. The concrete PostgreSQL types (`PostgresConnectionManager`, `PostgresQueryExecutor`, etc.) are instantiated only in `DatabaseService.init()` and in test mocks. The UI, ViewModels, and upper-layer services never import `PostgresNIO`.

**Actor isolation.** The connection manager is an `actor` (thread-safe by design). Services are `@MainActor`. State classes are `@Observable @MainActor`. This provides strong concurrency safety.

**SwiftData persistence.** User data (connections, saved queries, query folders, tab state, query history) is stored via SwiftData with versioned schema migrations (`PostgresGUISchemaV1` → `V2`).

**Multi-statement execution.** The SQL statement splitter handles semicolons, quoted strings, dollar-quoting (PostgreSQL-specific), and comments. Multi-statement queries are split and executed sequentially.

**Race condition handling.** Sophisticated generation-counter and context-triple validation prevents stale query results from overwriting current state. Superseded queries are interrupted and discarded.

### 2.3 State Management

The app uses a non-hierarchical observable state model:

| State Class | Responsibility |
|-------------|---------------|
| `AppState` | Central coordinator: query execution, pagination, metadata cache, schema search path |
| `ConnectionState` | Active connection/database/table selection, table and schema lists, metadata cache |
| `QueryState` | Query text, results, errors, page cache, toast notifications |
| `NavigationState` | Sheet/form presentation state, welcome screen logic |
| `LoadingState` | Loading phases and progress for connection establishment |
| `TabManager` | Tab lifecycle (create, close, switch, persist) |

### 2.4 Query Execution Pipeline

```
User action (sidebar click or SQL editor submit)
  → AppState.requestTableQuery() or AppState.executeSQLQuery()
    → QueryService.executeDisplayQuery()
      → For table browse: makeWrappedTableBrowseQuery() [wraps in to_jsonb()]
      → ConnectionManager.withConnection { connection in
          QueryExecutor.executeQuery(connection: connection, sql: sql)
        }
        → PostgresDatabaseConnection.executeQuery(sql)
          → PostgresConnection.query(sql) [PostgresNIO]
            → PostgresRowSequence [async iteration]
      → ResultMapper.mapRowsToTableRows(rows)
        → [TableRow] (generic [String: String?] dictionaries)
    → For table browse: QueryResultNormalizer (unwraps to_jsonb)
    → TableBrowseResultCompactor (truncates long cells)
  → QueryState.queryResults = results
  → UI updates via @Observable
```

### 2.5 Connection Lifecycle

```
User enters credentials in ConnectionFormView
  → ConnectionService.connect(to: profile, password: password)
    → KeychainService.getPassword(for: profile.id) [if not provided]
    → [Optional] SSHTunnelManager.establish(config) → local forwarded port
    → DatabaseService.connect(host, port, username, password, database, sslMode)
      → PostgresConnectionManager.connect(...)
        → MultiThreadedEventLoopGroup(numberOfThreads: 2)
        → PostgresConnection.Configuration(host, port, TLS)
        → PostgresConnection.connect(configuration, on: eventLoopGroup)
    → MetadataService.fetchDatabases()
    → TableRefreshService.refresh()
```

### 2.6 Tab Management

Tabs are persisted via SwiftData (`TabState` model) and managed by `TabManager`. Each tab holds:
- Connection and database context
- Query text
- Cached results (JSON-encoded `[TableRow]`)
- Selected table/schema
- Active/order state

Tab state syncs bidirectionally between `TabViewModel` (in-memory) and `TabState` (persisted).

---

## 3. Repository / Component Map

```
postgresgui/
├── PostgresGUI/
│   ├── PostgresGUIApp.swift              # App entry point, scene setup, menu commands
│   ├── PostgresGUI.entitlements          # Sandbox, network, keychain entitlements
│   │
│   ├── Models/                           # Domain models
│   │   ├── ColumnInfo.swift              # Column metadata (name, type, nullable, PK, FK)
│   │   ├── ConnectionProfile.swift       # Connection credentials (host, port, SSL, SSH)  ← REPLACE
│   │   ├── DatabaseInfo.swift            # Database name + table count
│   │   ├── QueryFolder.swift             # Saved query folder (SwiftData)
│   │   ├── QueryHistory.swift            # Query execution history (SwiftData)
│   │   ├── QueryResult.swift             # Query result wrapper (rows + columns + timing)
│   │   ├── RowEditValue.swift            # Cell edit value (.value | .null)
│   │   ├── RowUpdate.swift               # Pending row update (column→value pairs)
│   │   ├── SavedQuery.swift              # Saved query (SwiftData)
│   │   ├── TabState.swift                # Tab persistence (SwiftData)
│   │   ├── TableInfo.swift               # Table metadata (name, schema, type)  ← ADAPT
│   │   └── TableRow.swift                # Row data: [String: String?]  (fully generic)
│   │
│   ├── State/                            # Observable state management
│   │   ├── AppState.swift                # Central state coordinator  ← ADAPT
│   │   ├── ConnectionState.swift         # Connection/selection state  ← ADAPT
│   │   ├── LoadingState.swift            # Loading phases
│   │   ├── NavigationState.swift         # UI navigation state  ← ADAPT
│   │   ├── QueryState.swift              # Query/results state  ← ADAPT
│   │   └── TabManager.swift              # Tab lifecycle management
│   │
│   ├── ViewModels/                       # View models (all @Observable @MainActor)
│   │   ├── RootViewModel.swift           # Root view coordination  ← ADAPT
│   │   ├── ConnectionFormViewModel.swift  # Connection form logic  ← REPLACE
│   │   ├── ConnectionSidebarViewModel.swift # Sidebar actions  ← ADAPT
│   │   ├── ConnectionsListViewModel.swift   # Connection list management  ← ADAPT
│   │   ├── DetailContentViewModel.swift     # Detail pane actions  ← ADAPT
│   │   ├── QueryEditorViewModel.swift       # SQL editor logic
│   │   ├── QueryResultsViewModel.swift      # Results display logic
│   │   ├── SavedQueriesViewModel.swift      # Saved queries management
│   │   ├── TabViewModel.swift               # Per-tab view model
│   │   └── TableContextMenuViewModel.swift  # Table right-click actions  ← ADAPT
│   │
│   ├── Views/
│   │   ├── Containers/                   # Structural layout views
│   │   │   ├── RootView.swift            # App root layout  ← ADAPT
│   │   │   ├── MainSplitView.swift       # Sidebar + content split  ← ADAPT
│   │   │   ├── Sidebar/
│   │   │   │   ├── ConnectionsDatabasesSidebar.swift  ← ADAPT
│   │   │   │   └── SavedQueriesSidebarSection.swift
│   │   │   ├── Content/
│   │   │   │   ├── SplitContentView.swift
│   │   │   │   ├── QueryEditorView.swift
│   │   │   │   └── QueryResultsView.swift
│   │   │   ├── Connection/
│   │   │   │   ├── ConnectionFormView.swift    ← REPLACE
│   │   │   │   └── ConnectionsListView.swift   ← ADAPT
│   │   │   ├── Database/
│   │   │   │   └── CreateDatabaseView.swift    ← REMOVE
│   │   │   ├── Tables/
│   │   │   │   └── TablesListView.swift        ← ADAPT
│   │   │   ├── TabBar/
│   │   │   │   └── TabBarView.swift
│   │   │   └── History/
│   │   │       └── QueryHistoryView.swift
│   │   │
│   │   ├── Components/                   # Reusable UI components
│   │   │   ├── Connection/
│   │   │   │   ├── ConnectionDropdown.swift     ← ADAPT
│   │   │   │   ├── ConnectionDatabasePicker.swift  ← REPLACE
│   │   │   │   └── ConnectionStatusBanner.swift    ← ADAPT
│   │   │   ├── Content/
│   │   │   │   ├── QueryEditorComponent.swift
│   │   │   │   ├── QueryResultsComponent.swift
│   │   │   │   ├── JSONViewerView.swift
│   │   │   │   ├── RowEditorView.swift         ← ADAPT
│   │   │   │   ├── ColumnRowView.swift
│   │   │   │   └── DetailContentModals.swift
│   │   │   ├── Sidebar/
│   │   │   │   ├── SchemaPicker.swift          ← REMOVE
│   │   │   │   ├── SavedQueryRowView.swift
│   │   │   │   └── QueryFolderRowView.swift
│   │   │   ├── Tables/
│   │   │   │   ├── SchemaGroupView.swift       ← REMOVE
│   │   │   │   ├── TableListRowComponent.swift ← ADAPT
│   │   │   │   └── TableContextMenuModals.swift
│   │   │   ├── Sheets/
│   │   │   │   ├── TableDDLSheet.swift
│   │   │   │   ├── TableExportSheet.swift
│   │   │   │   ├── EditQuerySheet.swift
│   │   │   │   ├── EditFolderSheet.swift
│   │   │   │   └── MoveToFolderSheet.swift
│   │   │   ├── Toast/
│   │   │   │   └── MutationToastView.swift
│   │   │   └── Toolbar/
│   │   │       └── DetailContentToolbar.swift  ← ADAPT
│   │   │
│   │   ├── Primitives/                   # Low-level UI building blocks
│   │   │   ├── Badge.swift
│   │   │   ├── EmptyQueryResultsView.swift
│   │   │   ├── LineNumberRulerView.swift
│   │   │   ├── LoadingOverlayView.swift
│   │   │   ├── ResizableSplitView.swift
│   │   │   └── SyntaxHighlightedEditor.swift   ← ADAPT (keyword list)
│   │   │
│   │   └── Pages/                        # Full-page views
│   │       ├── WelcomeView.swift           ← ADAPT
│   │       ├── SettingsView.swift          ← ADAPT
│   │       ├── HelpView.swift
│   │       └── KeyboardShortcutsView.swift
│   │
│   ├── Services/                         # Application services
│   │   ├── DatabaseService.swift         # Central DB service facade  ← ADAPT
│   │   ├── ConnectionService.swift       # Connection orchestration  ← ADAPT
│   │   ├── QueryService.swift            # Query execution wrapper  ← ADAPT
│   │   ├── TableService.swift            # Table operations (protocol-only)
│   │   ├── MetadataService.swift         # Metadata fetching (protocol-only)
│   │   ├── TableRefreshService.swift     # DB→table→schema loading  ← ADAPT
│   │   ├── TableMetadataService.swift    # PK/column cache
│   │   ├── RowOperationsService.swift    # Row CRUD
│   │   ├── TabService.swift              # Tab persistence
│   │   ├── KeychainService.swift         # macOS Keychain  ← ADAPT
│   │   ├── DatabaseManagementService.swift  # CREATE/DROP DB  ← ADAPT
│   │   │
│   │   ├── Postgres/                     # *** PostgreSQL implementation — ALL REPLACE ***
│   │   │   ├── PostgresConnectionManager.swift    (513 lines)
│   │   │   ├── PostgresQueryExecutor.swift        (543 lines)
│   │   │   ├── PostgresDatabaseConnection.swift   (219 lines)
│   │   │   └── PostgresResultMapper.swift         (121 lines)
│   │   │
│   │   ├── SSH/                          # *** SSH infrastructure — ALL REMOVE ***
│   │   │   ├── SSHTunnelManager.swift     (313 lines)
│   │   │   ├── SSHKeyParser.swift         (614 lines)
│   │   │   └── RSASHA512.swift            (304 lines)
│   │   │
│   │   └── Protocols/                    # Service abstraction protocols
│   │       ├── DatabaseConnectionProtocol.swift      # The key abstraction boundary
│   │       ├── ConnectionManagerProtocol.swift        ← ADAPT (connect signature)
│   │       ├── QueryExecutorProtocol.swift            ← ADAPT (schema params)
│   │       ├── DatabaseServiceProtocol.swift          ← ADAPT (connect signature)
│   │       ├── ResultMapperProtocol.swift
│   │       ├── ConnectionServiceProtocol.swift        ← ADAPT
│   │       ├── DatabaseManagementServiceProtocol.swift ← ADAPT
│   │       ├── KeychainServiceProtocol.swift          ← ADAPT
│   │       ├── SSHTunnelManagerProtocol.swift         ← REMOVE
│   │       ├── TableServiceProtocol.swift
│   │       ├── TableRefreshServiceProtocol.swift
│   │       ├── TableMetadataServiceProtocol.swift
│   │       ├── RowOperationsServiceProtocol.swift
│   │       ├── MetadataServiceProtocol.swift
│   │       ├── QueryServiceProtocol.swift
│   │       └── TabServiceProtocol.swift
│   │
│   ├── Types/                            # Domain value types
│   │   ├── PostgresConnectionString.swift  ← REMOVE
│   │   ├── SSLMode.swift                   ← REMOVE
│   │   └── SSHAuthMethod.swift             ← REMOVE
│   │
│   ├── Errors/                           # Error types
│   │   ├── PostgresError.swift             ← REMOVE
│   │   ├── SSHTunnelError.swift            ← REMOVE
│   │   ├── ConnectionError.swift           ← REPLACE
│   │   ├── DatabaseError.swift
│   │   ├── KeychainError.swift
│   │   └── RowOperationError.swift
│   │
│   ├── Logic/                            # Pure decision functions
│   │   ├── AppLaunchDecisions.swift
│   │   └── QueryDecisions.swift
│   │
│   ├── Utilities/                        # Utility functions
│   │   ├── Constants.swift                 ← ADAPT
│   │   ├── CSVExporter.swift
│   │   ├── ConnectionStringParser.swift    ← REPLACE
│   │   ├── DebugLog.swift
│   │   ├── JSONDocument.swift
│   │   ├── QueryEditability.swift          ← ADAPT
│   │   ├── QueryHistoryExporter.swift
│   │   ├── QueryResultNormalizer.swift     ← REMOVE
│   │   ├── QueryTypeDetector.swift
│   │   ├── QueryWrapping.swift             ← REMOVE
│   │   ├── SQLStatementSplitter.swift      ← ADAPT
│   │   ├── TableBrowseResultCompactor.swift
│   │   ├── TableGrouping.swift             ← ADAPT
│   │   ├── TimeInterval+Extensions.swift
│   │   ├── ClockProtocol.swift
│   │   ├── UserDefaultsProtocol.swift
│   │   └── Timeout.swift
│   │
│   ├── Persistence/
│   │   └── PostgresGUIModelContainer.swift ← ADAPT (rename)
│   │
│   └── Assets.xcassets/                  # App icon, accent color, logo
│
├── PostgresGUITests/                     # 17 test files, ~2,200 lines
│   ├── AppStateTests.swift               # 28 tests — race conditions, pagination
│   ├── ConnectionSidebarViewModelTests.swift
│   ├── ConnectionStateTests.swift
│   ├── ConnectionStringParserTests.swift  ← DELETE (PG-specific)
│   ├── CSVExporterTests.swift
│   ├── DatabaseServiceDeleteDatabaseTests.swift  ← DELETE (PG-specific)
│   ├── ErrorMappingTests.swift            ← ADAPT
│   ├── QueryDecisionsTests.swift
│   ├── QueryEditabilityTests.swift        ← ADAPT
│   ├── QueryHistoryTests.swift
│   ├── QueryResultNormalizerTests.swift   ← DELETE
│   ├── QueryStateTests.swift
│   ├── QueryTypeDetectorTests.swift
│   ├── SQLStatementSplitterTests.swift    ← ADAPT
│   ├── SSHKeyParserTests.swift            ← DELETE
│   ├── TableBrowseResultCompactorTests.swift
│   └── TableRefreshServiceTests.swift     ← ADAPT
│
├── PostgresGUIUITests/
│   └── PostgresGUIUITests.swift          # Empty test case
│
├── PostgresGUI.xcodeproj/
│   ├── project.pbxproj                   # Xcode project (macOS 26, Swift 5)
│   └── project.xcworkspace/
│       └── xcshareddata/swiftpm/
│           └── Package.resolved          # SPM lock file
│
├── LICENSE                               # O'Saasy license (MIT + SaaS restriction)
├── README.md
└── buildServer.json
```

---

## 4. PostgreSQL Dependency Map

### 4.1 SPM Package Dependencies

| Package | Purpose | Transitive Deps | SQLite Action |
|---------|---------|-----------------|---------------|
| **PostgresNIO** 1.29.0 | PostgreSQL wire protocol client | swift-nio, swift-nio-ssl, swift-crypto, swift-log, swift-collections, swift-atomics, swift-system, swift-metrics, swift-service-lifecycle, swift-async-algorithms | **Remove** |
| **Citadel** 0.12.1 | SSH tunnel support | swift-nio-ssh, BigInt | **Remove** |
| **swift-log** (transitive) | Logging framework | — | **Keep as direct dependency** |

Removing PostgresNIO and Citadel eliminates **14 transitive SPM packages**. The project would have only 1–2 dependencies (swift-log + GRDB).

### 4.2 Direct PostgresNIO Import Sites

| File | Import | Usage |
|------|--------|-------|
| `PostgresDatabaseConnection.swift` | `PostgresNIO`, `NIOCore`, `NIOFoundationCompat` | `PostgresConnection`, `PostgresRow`, `PostgresCell`, `PostgresBindings`, `PostgresQuery`, `PostgresRowSequence` |
| `PostgresConnectionManager.swift` | `PostgresNIO`, `NIOCore`, `NIOPosix`, `NIOSSL` | `PostgresConnection`, `PSQLError`, `MultiThreadedEventLoopGroup`, `NIOSSLContext`, `TLSConfiguration` |
| `PostgresResultMapper.swift` | `PostgresNIO` | `PostgresDatabaseRow` downcast, `PostgresDecodable`, `PostgresCell.bytes` |
| `PostgresError.swift` | `PostgresNIO` | `PSQLError`, `error.serverInfo` |

### 4.3 PostgreSQL-Specific SQL

| Location | SQL Construct | SQLite Equivalent |
|----------|--------------|-------------------|
| `PostgresQueryExecutor.fetchDatabases()` | `SELECT datname FROM pg_database` | N/A — SQLite has no server databases |
| `PostgresQueryExecutor.fetchTables()` | `pg_tables`, `information_schema.foreign_tables` | `SELECT name, type FROM sqlite_master WHERE type IN ('table','view')` |
| `PostgresQueryExecutor.fetchSchemas()` | `pg_tables`, `information_schema` | `PRAGMA database_list` (for attached DBs) |
| `PostgresQueryExecutor.fetchPrimaryKeys()` | `pg_index`, `pg_attribute`, `::regclass` | `PRAGMA table_info(table)` → `pk > 0` |
| `PostgresQueryExecutor.fetchColumns()` | `information_schema.columns` | `PRAGMA table_info(table)` |
| `PostgresQueryExecutor.generateDDL()` | `information_schema`, `pg_constraint`, `pg_get_constraintdef()` | `SELECT sql FROM sqlite_master WHERE name = ?` |
| `QueryService.makeWrappedTableBrowseQuery()` | `SELECT to_jsonb(q) AS row FROM (…) q` | `SELECT * FROM "table" LIMIT n OFFSET n` |
| `AppState.setSchemaSearchPath()` | `SET search_path TO …` | N/A — SQLite has no search path |

### 4.4 PostgreSQL Concepts with No SQLite Equivalent

| Concept | Where Used | SQLite Handling |
|---------|-----------|-----------------|
| Multiple databases per server | `fetchDatabases()`, `DatabaseInfo`, `ConnectionDatabasePicker` | One file = one database; ATTACH for multi-file |
| Schemas (`public`, `pg_catalog`, custom) | `SchemaPicker`, `SchemaGroupView`, `TableGrouping`, `TableInfo.schema` | No schemas; flat table namespace per database |
| Foreign tables (FDW) | `TableInfo.tableType == .foreign` | Remove — SQLite has no FDW |
| `search_path` | `AppState.setSchemaSearchPath()` | Remove entirely |
| Server credentials | `ConnectionProfile` (host, port, user, password) | Replace with file path |
| SSL/TLS modes | `SSLMode`, connection config | Remove — file-local access |
| SSH tunnels | Full `SSH/` directory, `SSHTunnelManager` | Remove entirely |
| `CREATE DATABASE` / `DROP DATABASE` | `CreateDatabaseView`, `DatabaseManagementService` | File creation/deletion instead |
| Dollar-quoting (`$$…$$`) | `SQLStatementSplitter` | Keep (harmless) or remove |
| `to_jsonb()` wrapping | `QueryWrapping`, `QueryResultNormalizer` | Remove — direct `SELECT *` |
| PostgreSQL-specific aggregates | `QueryEditability` (ARRAY_AGG, STRING_AGG, etc.) | Replace with SQLite aggregates (GROUP_CONCAT) |

---

## 5. KEEP / ADAPT / REPLACE / REMOVE Analysis

### 5.1 Summary by Category

**KEEP** — 83 files (~14,800 lines) require zero changes:

All view primitives (Badge, LoadingOverlay, ResizableSplitView, LineNumberRulerView, EmptyQueryResultsView), most view components (JSONViewerView, QueryResultsComponent, QueryEditorComponent, all sheets, toast, modals), data models (TableRow, ColumnInfo, QueryResult, DatabaseInfo, RowEditValue, RowUpdate, QueryFolder, QueryHistory, SavedQuery), state managers (LoadingState, TabManager), logic (AppLaunchDecisions, QueryDecisions), utilities (CSVExporter, JSONDocument, QueryTypeDetector, QueryHistoryExporter, TableBrowseResultCompactor, DebugLog, TimeInterval extensions, ClockProtocol, UserDefaultsProtocol, Timeout), protocol-only services (TableService, MetadataService, TableMetadataService, RowOperationsService, TabService), and most service protocols.

**ADAPT** — 38 files (~8,200 lines) require surgical edits:

- **Models:** `TableInfo.swift` (change default schema from `"public"` to `"main"`)
- **State:** `AppState.swift` (remove `setSchemaSearchPath`), `ConnectionState.swift` (minor), `NavigationState.swift` (rename `isShowingCreateDatabase`), `QueryState.swift` (replace `PostgresError.extractDetailedMessage`)
- **ViewModels:** Several need connection form and schema reference updates
- **Views:** Sidebar, toolbar, settings, welcome view need branding/connection UI changes
- **Services:** `DatabaseService`, `ConnectionService`, `QueryService`, `TableRefreshService` need connect-signature and PostgreSQL-SQL removal
- **Protocols:** `ConnectionManagerProtocol`, `DatabaseServiceProtocol` need `connect()` signature changes
- **Utilities:** `Constants.swift` (PostgreSQL sub-enum), `QueryEditability` (PG aggregates), `SQLStatementSplitter` (dollar-quoting), `TableGrouping` (schema sorting), `SyntaxHighlightedEditor` (keyword list)

**REPLACE** — 11 files (~2,400 lines) need new implementations:

| File | New File | Reason |
|------|----------|--------|
| `Services/Postgres/PostgresConnectionManager.swift` | `Services/SQLite/SQLiteConnectionManager.swift` | NIO → file handle |
| `Services/Postgres/PostgresQueryExecutor.swift` | `Services/SQLite/SQLiteQueryExecutor.swift` | All SQL is PostgreSQL-specific |
| `Services/Postgres/PostgresDatabaseConnection.swift` | `Services/SQLite/SQLiteDatabaseConnection.swift` | PostgresNIO types |
| `Services/Postgres/PostgresResultMapper.swift` | `Services/SQLite/SQLiteResultMapper.swift` | PostgresNIO decoding |
| `Models/ConnectionProfile.swift` | `Models/DatabaseFileProfile.swift` | host/port/SSL/SSH → file path |
| `Errors/ConnectionError.swift` | `Errors/FileOpenError.swift` | Network errors → file errors |
| `Utilities/ConnectionStringParser.swift` | *(delete or replace with file-path utilities)* | PostgreSQL URIs |
| `Views/Containers/Connection/ConnectionFormView.swift` | `Views/Containers/File/FileOpenView.swift` | Server form → file picker |
| `ViewModels/ConnectionFormViewModel.swift` | `ViewModels/FileOpenViewModel.swift` | Connection validation → file validation |
| `Views/Components/Connection/ConnectionDatabasePicker.swift` | *(simplify to file picker only)* | Server+DB picker → file picker |
| `Persistence/PostgresGUIModelContainer.swift` | `Persistence/SQLiteGUIModelContainer.swift` | Rename + swap models |

**REMOVE** — 23 files (~1,800 lines) to delete:

| Files | Reason |
|-------|--------|
| `Services/SSH/SSHTunnelManager.swift` (313 lines) | No SSH for SQLite |
| `Services/SSH/SSHKeyParser.swift` (614 lines) | No SSH for SQLite |
| `Services/SSH/RSASHA512.swift` (304 lines) | No SSH for SQLite |
| `Services/Protocols/SSHTunnelManagerProtocol.swift` (37 lines) | No SSH for SQLite |
| `Types/PostgresConnectionString.swift` | No connection strings |
| `Types/SSLMode.swift` | No SSL/TLS |
| `Types/SSHAuthMethod.swift` | No SSH |
| `Errors/PostgresError.swift` | PostgresNIO dependency |
| `Errors/SSHTunnelError.swift` | No SSH |
| `Utilities/QueryWrapping.swift` | `to_jsonb()` workaround |
| `Utilities/QueryResultNormalizer.swift` | Inverse of `to_jsonb()` |
| `Views/Components/Sidebar/SchemaPicker.swift` | No schemas |
| `Views/Components/Tables/SchemaGroupView.swift` | No schema groups |
| `Views/Containers/Database/CreateDatabaseView.swift` | No CREATE DATABASE |
| `PostgresGUITests/ConnectionStringParserTests.swift` | PG connection strings |
| `PostgresGUITests/DatabaseServiceDeleteDatabaseTests.swift` | PG maintenance DB logic |
| `PostgresGUITests/QueryResultNormalizerTests.swift` | `to_jsonb()` inverse |
| `PostgresGUITests/SSHKeyParserTests.swift` | SSH infrastructure |

### 5.2 Dependency Impact

```
Existing Dependency Graph:

SwiftUI Views ──→ ViewModels ──→ State ──→ Services (protocol-backed)
                                              │
                                    ┌─────────┴─────────┐
                                    │  Protocols         │
                                    └─────────┬─────────┘
                                              │
                              ┌───────────────┼───────────────┐
                              │               │               │
                    Postgres/ (REPLACE)   SSH/ (REMOVE)   Keychain (ADAPT)
                    4 files              3 files           1 file
                    ↓                    ↓
                    PostgresNIO          Citadel
                    + 12 transitive      + 2 transitive

Target Dependency Graph:

SwiftUI Views ──→ ViewModels ──→ State ──→ Services (protocol-backed)
                                              │
                                    ┌─────────┴─────────┐
                                    │  Protocols         │
                                    │  (minor adapt)     │
                                    └─────────┬─────────┘
                                              │
                              ┌───────────────┼───────────┐
                              │               │           │
                    SQLite/ (NEW)       Keychain (ADAPT)  │
                    4 files                               │
                    ↓                                     │
                    GRDB.swift ──→ sqlite3 (system)       │
                                                    swift-log (direct)
```

---

## 6. Proposed SQLite Architecture

### 6.1 Target Architecture

```
┌─────────────────────────────────────────────────────────┐
│  SwiftUI Views                                           │
│  (Adapted: file-open UX replaces connection form)        │
├─────────────────────────────────────────────────────────┤
│  ViewModels                                              │
│  (Adapted: FileOpenViewModel replaces ConnectionForm)    │
├─────────────────────────────────────────────────────────┤
│  State (@Observable, @MainActor)                         │
│  (Adapted: remove schema concepts, add file state)       │
├─────────────────────────────────────────────────────────┤
│  Application Services (protocol-backed, unchanged)       │
│  DatabaseService, QueryService, TableService,            │
│  MetadataService, RowOperationsService, TabService       │
├─────────────────────────────────────────────────────────┤
│  Service Protocols                                       │
│  (Adapted: connect(filePath:) instead of host/port)      │
├─────────────────────────────────────────────────────────┤
│  SQLite Implementation (NEW — replaces Postgres/)        │
│  SQLiteConnectionManager, SQLiteQueryExecutor,           │
│  SQLiteDatabaseConnection, SQLiteResultMapper            │
├─────────────────────────────────────────────────────────┤
│  GRDB.swift → sqlite3 (system library)                   │
└─────────────────────────────────────────────────────────┘
```

### 6.2 New File Structure

```
PostgresGUI/                              → rename to SQLiteGUI/ (Phase N)
├── Services/
│   ├── SQLite/                           ← NEW directory (replaces Postgres/)
│   │   ├── SQLiteConnectionManager.swift
│   │   ├── SQLiteQueryExecutor.swift
│   │   ├── SQLiteDatabaseConnection.swift
│   │   └── SQLiteResultMapper.swift
│   ├── SSH/                              ← DELETE directory
│   └── FileAccessService.swift           ← NEW (security-scoped bookmarks, recent files)
```

### 6.3 Connection Model Transformation

**Before (PostgreSQL):**
```swift
ConnectionProfile {
    host: String            // "localhost"
    port: Int               // 5432
    username: String        // "postgres"
    database: String        // "mydb"
    sslMode: SSLMode        // .prefer
    password: String        // (from Keychain)
    sshEnabled: Bool
    sshHost: String
    sshPort: Int
    sshUsername: String
    sshAuthMethod: SSHAuthMethod
    sshPrivateKeyPath: String
}
```

**After (SQLite):**
```swift
@Model
final class DatabaseFileProfile {
    @Attribute(.unique) var id: UUID
    var name: String                    // User-facing label (default: filename)
    var filePath: String                // Absolute path to .db/.sqlite/.sqlite3
    var bookmarkData: Data?             // Security-scoped bookmark for sandbox persistence
    var isFavorite: Bool
    var isReadOnly: Bool                // User preference to open read-only
    var lastOpenedAt: Date?
    var fileSize: Int64?                // Cached file size
    var sqliteVersion: String?          // Cached SQLite version string
    var journalMode: String?            // Cached journal mode (WAL, DELETE, etc.)
    var createdAt: Date
    var updatedAt: Date
}
```

### 6.4 Protocol Adaptation

The key protocol change is the `connect()` signature:

```swift
// Before
protocol ConnectionManagerProtocol {
    func connect(host: String, port: Int, username: String,
                 password: String, database: String,
                 tlsMode: DatabaseTLSMode) async throws
}

// After
protocol ConnectionManagerProtocol {
    func connect(filePath: String, readOnly: Bool) async throws
    func connect(fileURL: URL, readOnly: Bool) async throws
}
```

All downstream protocols (`DatabaseServiceProtocol`, `ConnectionServiceProtocol`) cascade this change. The adaptation is mechanical — search for the old signature, replace with the new one, update all callers.

---

## 7. SQLite Library Recommendation

### 7.1 Options Evaluated

| Library | Approach | Maturity | SQLite Feature Coverage | Swift Integration |
|---------|----------|----------|------------------------|-------------------|
| **GRDB.swift** | High-level Swift wrapper | 10+ years, active | Full: WAL, FTS, JSON, ATTACH, PRAGMAs, virtual tables | Excellent: `DatabaseValueConvertible`, `Record`, `DatabaseQueue/Pool`, async |
| **SQLite.swift** | Type-safe query builder | 10+ years, less active | Good but gaps: limited FTS, no ATTACH helpers, no PRAGMA wrappers | Good: type-safe expressions, `Connection`, transactions |
| **System sqlite3 C API** | Direct C interop | Part of macOS | Complete (it IS SQLite) | Minimal: requires manual Swift/C bridging, manual memory management |

### 7.2 Recommendation: GRDB.swift

**GRDB.swift** is the recommended library for this project. Rationale:

1. **Full SQLite feature surface.** GRDB exposes PRAGMAs, ATTACH DATABASE, FTS3/4/5, WAL mode, JSON functions, virtual tables, and `EXPLAIN QUERY PLAN` — all features the spec requires for SQLite-specific differentiation. `SQLite.swift` has gaps in these areas.

2. **Inspector-class access pattern.** Unlike ORMs that hide SQL, GRDB allows arbitrary SQL execution via `db.execute(sql:)` and `Row` iteration — exactly what a database inspector needs. The app must run user-supplied SQL, not just ORM-generated queries.

3. **Clean mapping to existing protocols.** GRDB's `DatabaseQueue` maps cleanly to the existing `ConnectionManagerProtocol.withConnection {}` pattern. GRDB's `Row` (column-name-to-value dictionary) maps directly to `TableRow` (`[String: String?]`).

4. **Async support.** GRDB 6.x supports structured concurrency with `DatabaseQueue.read {}` and `DatabaseQueue.write {}` as async functions, fitting the existing `async/await` architecture.

5. **Performance.** GRDB uses SQLite's C API directly with minimal overhead. It supports WAL mode, shared cache, and connection pooling via `DatabasePool` — important for responsive browsing of large databases.

6. **Active maintenance.** GRDB has consistent releases, an active maintainer (Gwendal Roué), and strong community adoption in the Swift/macOS ecosystem.

7. **Minimal dependency.** GRDB depends only on system SQLite (`libsqlite3`) — no additional transitive dependencies.

### 7.3 Tradeoffs

| Concern | Assessment |
|---------|------------|
| GRDB is a dependency vs. direct C API | Acceptable: GRDB is the thinnest viable wrapper. Direct C API would require ~2,000 lines of boilerplate (error handling, memory management, type conversion) that GRDB provides safely. The inspector needs to expose SQLite-specific features that even GRDB's higher-level APIs don't wrap, so some direct `sqlite3_*` calls via GRDB's `Database.sqliteConnection` escape hatch will be needed. |
| SQLite.swift is more type-safe | The type-safe query builder is valuable for applications that generate SQL programmatically, but an inspector needs to execute arbitrary user SQL. GRDB's arbitrary SQL execution is a better fit. |
| GRDB's Record/migration system | We would not use GRDB's ORM features — only the raw SQL execution, row iteration, and PRAGMA access. The ORM is opt-in and adds no overhead when unused. |

### 7.4 Integration Pattern

```swift
import GRDB

actor SQLiteConnectionManager: ConnectionManagerProtocol {
    private var dbQueue: DatabaseQueue?

    func connect(filePath: String, readOnly: Bool) async throws {
        var config = Configuration()
        config.readonly = readOnly
        config.busyMode = .timeout(5.0)  // 5 second busy timeout
        config.prepareDatabase { db in
            // Enable foreign key enforcement
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        dbQueue = try DatabaseQueue(path: filePath, configuration: config)
    }

    func withConnection<T>(_ operation: @escaping (DatabaseConnectionProtocol) async throws -> T) async throws -> T {
        guard let dbQueue else { throw FileOpenError.notConnected }
        return try await dbQueue.read { db in
            let connection = SQLiteDatabaseConnection(database: db)
            return try await operation(connection)
        }
    }
}
```

---

## 8. MVP Product Specification

### 8.1 Database Opening

**File formats supported:**
- `.db`
- `.sqlite`
- `.sqlite3`

**Opening methods:**

| Method | Implementation |
|--------|---------------|
| File → Open (⌘O) | Standard `NSOpenPanel` with file type filters for `.db`, `.sqlite`, `.sqlite3` |
| Drag and drop | `onDrop(of:)` on the main window accepting `UTType.fileURL` with supported extensions |
| macOS Open With | Register `UTType` declarations in Info.plist for all three extensions; implement `onOpenURL` |
| Recent databases | `NSDocumentController.shared.noteNewRecentDocumentURL()` + Recent menu item; additionally persist in `DatabaseFileProfile` SwiftData model |
| Reopen previous session | On launch, offer to reopen the last-used database from `DatabaseFileProfile.lastOpenedAt` |
| Read-only mode | Toggle in file-open UI and in toolbar; passes `config.readonly = true` to GRDB |
| Command-line `open` | Respond to `NSApplication` openFile delegate — `open -a SQLiteGUI database.db` |

**Security-scoped bookmarks:** In a sandboxed app, file access beyond the initial user selection requires security-scoped bookmarks. `DatabaseFileProfile.bookmarkData` stores the bookmark; the app resolves it on reopen. If the bookmark is stale (file moved/renamed), prompt the user to re-select.

### 8.2 Database Browser (Sidebar)

The sidebar should expose SQLite objects:

```
📁 database.sqlite
├── 📋 Tables (12)
│   ├── users
│   ├── orders
│   ├── products
│   └── ...
├── 👁 Views (3)
│   ├── active_users
│   └── ...
├── 📇 Indexes (8)
│   ├── idx_users_email
│   └── ...
├── ⚡ Triggers (2)
│   ├── update_timestamp
│   └── ...
├── 🔮 Virtual Tables (1)
│   └── search_index (FTS5)
└── 🔗 Attached Databases
    └── analytics.db
```

**Discovery queries:**
```sql
-- Tables (excluding SQLite internals)
SELECT name FROM sqlite_master
WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
ORDER BY name;

-- Views
SELECT name FROM sqlite_master WHERE type = 'view' ORDER BY name;

-- Indexes (excluding auto-indexes)
SELECT name, tbl_name FROM sqlite_master
WHERE type = 'index' AND name NOT LIKE 'sqlite_%'
ORDER BY name;

-- Triggers
SELECT name, tbl_name FROM sqlite_master
WHERE type = 'trigger' ORDER BY name;
```

**FTS table identification:**
```sql
-- FTS5 tables have a shadow table pattern
SELECT name FROM sqlite_master
WHERE type = 'table'
AND name NOT LIKE '%_content'
AND name NOT LIKE '%_data'
AND name NOT LIKE '%_docsize'
AND name NOT LIKE '%_config'
AND name NOT LIKE '%_idx'
AND EXISTS (
    SELECT 1 FROM sqlite_master AS m2
    WHERE m2.name = sqlite_master.name || '_content'
    AND m2.type = 'table'
);
```

**Virtual table identification:**
```sql
-- Check the CREATE statement for VIRTUAL TABLE
SELECT name FROM sqlite_master
WHERE type = 'table'
AND sql LIKE 'CREATE VIRTUAL TABLE%';
```

### 8.3 Table Inspection

Selecting a table shows:

**Columns tab:**

| Property | Source |
|----------|--------|
| Column name | `PRAGMA table_info(table)` → `name` |
| Declared type | `PRAGMA table_info(table)` → `type` |
| Primary key | `PRAGMA table_info(table)` → `pk > 0` |
| Not null | `PRAGMA table_info(table)` → `notnull` |
| Default value | `PRAGMA table_info(table)` → `dflt_value` |
| Foreign keys | `PRAGMA foreign_key_list(table)` |
| Generated columns | `PRAGMA table_xinfo(table)` → `hidden` (1=virtual, 2=stored) |
| Indexes on column | `PRAGMA index_list(table)` + `PRAGMA index_info(index)` |

**DDL tab:**
```sql
SELECT sql FROM sqlite_master WHERE name = ? AND type = 'table';
```

**SQLite-specific table properties to surface:**
- `WITHOUT ROWID` — detected by checking if the table's DDL contains `WITHOUT ROWID`
- `STRICT` — detected by checking if DDL contains `STRICT`
- `INTEGER PRIMARY KEY` (aliased rowid) vs regular PK
- Row count estimate: `SELECT COUNT(*) FROM table` (exact, since SQLite lacks table statistics)

### 8.4 Data Browser

| Feature | Implementation |
|---------|---------------|
| Browse rows | `SELECT * FROM "table" LIMIT ? OFFSET ?` |
| Pagination | Page-based with configurable page size (default 100, max 1000); maintain page cache as in existing codebase |
| Sort | `ORDER BY "column" ASC/DESC` appended to browse query; click column header to cycle |
| Filter | Text filter generates `WHERE "column" LIKE '%search%'` or exact match; support multiple column filters |
| Column resizing | Existing SwiftUI `Table` column resizing (already implemented) |
| Copy cells/rows | Existing implementation — copy selected cells as tab-separated, rows as CSV |
| NULL display | Show `NULL` in grey italic (distinct from empty string); existing `RowEditValue.null` handles this |
| BLOB handling | Show `[BLOB: N bytes]` placeholder; click to inspect (see §8.9) |
| JSON viewing | Detect JSON-shaped TEXT values; show pretty-printed view on click (existing `JSONViewerView`) |
| Inline editing | For non-read-only databases: click cell → edit; uses existing `RowEditorView` infrastructure |
| Insert rows | New row form pre-populated with defaults; uses existing row operation service |
| Delete rows | Select rows → delete with confirmation; requires identifiable PK (uses rowid if no explicit PK) |

**SQLite-specific data browsing considerations:**

- **rowid:** Every table without `WITHOUT ROWID` has an implicit `rowid`. Use `rowid` as the row identifier for editing and deletion when no explicit PK exists. Fetch with `SELECT rowid, * FROM "table"`.
- **INTEGER PRIMARY KEY:** When a column is `INTEGER PRIMARY KEY`, it is an alias for `rowid` — do not show it twice.
- **WITHOUT ROWID tables:** Cannot use implicit `rowid`. Editing/deletion requires an explicit PK; if none exists, show rows as read-only.
- **STRICT tables:** Type affinity is enforced; the editor should validate types on input.
- **Dynamic typing / type affinity:** SQLite allows storing any type in any column (unless STRICT). The data browser should show the actual storage class (via `typeof(column)`), not just the declared type. Display a visual indicator when the stored type differs from the declared type.
- **Generated columns:** Show as read-only in the editor; do not include in INSERT/UPDATE statements.

### 8.5 SQL Editor

The existing SQL editor (`SyntaxHighlightedEditor.swift`) provides:
- NSTextView-based editor with line numbers (`LineNumberRulerView`)
- Syntax highlighting via regex-based `SQLSyntaxHighlighter`
- Multi-statement execution via `SQLStatementSplitter`
- Keyboard shortcuts (⌘Enter to execute, ⌘⇧Enter for selection)

**Adaptations required:**

1. **Keyword list update.** Replace PostgreSQL keywords (`PLPGSQL`, `BYTEA`, `JSONB`, `UUID`, `SERIAL`, `BIGSERIAL`, `RETURNING`, `ILIKE`, `TABLESPACE`, `REINDEX`, `CLUSTER`, `search_path`, type casts `::`, role management keywords) with SQLite keywords:
   - Control: `AUTOINCREMENT`, `ROWID`, `WITHOUT`, `STRICT`
   - PRAGMA: `PRAGMA`, `ATTACH`, `DETACH`, `REINDEX`, `ANALYZE`, `VACUUM`, `EXPLAIN`
   - Types: `INTEGER`, `REAL`, `TEXT`, `BLOB`, `NUMERIC`, `ANY`
   - Functions: `json()`, `json_extract()`, `json_array()`, `json_object()`, `json_each()`, `json_tree()`, `group_concat()`, `total()`, `typeof()`, `unlikely()`, `likelihood()`
   - FTS: `MATCH`, `rank`, `bm25()`, `highlight()`, `snippet()`

2. **Autocomplete.** Basic SQLite-aware autocomplete:
   - Table names from `sqlite_master`
   - Column names from `PRAGMA table_info()` for the most recently referenced table
   - SQLite keywords, functions, PRAGMAs
   - Not a full language server — use heuristic word-boundary matching

3. **Multi-statement handling.** The existing `SQLStatementSplitter` works for SQLite (semicolons, single quotes, comments). Dollar-quoting paths are harmless dead code for SQLite. Remove or gate them behind a compile flag for cleanliness.

4. **Result display.** The existing `QueryResultsComponent` works unchanged. It renders `[TableRow]` with `[String]` column names — fully generic.

5. **Execution timing.** Already implemented; keep as-is.

6. **SQL history.** Existing `QueryHistory` SwiftData model and `QueryHistoryView` are fully generic — keep.

7. **Saved queries.** Existing `SavedQuery` and `QueryFolder` SwiftData models are fully generic — keep.

### 8.6 Database Health / Inspector

This is a key differentiating feature. Surface a dedicated "Database Info" inspector panel.

**Database metadata:**

| Property | Query | Display |
|----------|-------|---------|
| File size | `FileManager` | Human-readable (e.g., "142.3 MB") |
| SQLite version | `SELECT sqlite_version()` | e.g., "3.45.1" |
| Journal mode | `PRAGMA journal_mode` | WAL / DELETE / TRUNCATE / PERSIST / OFF |
| WAL status | Check for `.db-wal` file existence + `PRAGMA wal_checkpoint(PASSIVE)` return values | Active / Empty / N/A |
| Page size | `PRAGMA page_size` | e.g., "4096 bytes" |
| Page count | `PRAGMA page_count` | e.g., "34,821 pages" |
| Free pages | `PRAGMA freelist_count` | e.g., "142 pages (568 KB reclaimable)" |
| Cache size | `PRAGMA cache_size` | Pages or KB |
| Foreign keys enforced | `PRAGMA foreign_keys` | ON / OFF (with toggle action) |
| Schema version | `PRAGMA schema_version` | Integer |
| User version | `PRAGMA user_version` | Integer |
| Encoding | `PRAGMA encoding` | UTF-8 / UTF-16le / UTF-16be |
| Auto vacuum | `PRAGMA auto_vacuum` | NONE / FULL / INCREMENTAL |
| Compile options | `PRAGMA compile_options` | List of SQLite compile flags |

**Maintenance actions:**

| Action | Command | Safety | Mutates? |
|--------|---------|--------|----------|
| Integrity check | `PRAGMA integrity_check` | Safe (read-only) | No |
| Quick check | `PRAGMA quick_check` | Safe (read-only, faster) | No |
| WAL checkpoint | `PRAGMA wal_checkpoint(TRUNCATE)` | Safe but blocks writers | Yes |
| VACUUM | `VACUUM` | Requires 2× disk space; locks database | Yes — rebuilds entire file |
| ANALYZE | `ANALYZE` | Safe; updates statistics | Yes — writes to `sqlite_stat1` |
| Optimize | `PRAGMA optimize` | Safe; runs ANALYZE where beneficial | Yes |
| Enable foreign keys | `PRAGMA foreign_keys = ON` | Session-only; no permanent change | No (session) |

**UI for maintenance actions:**
- Each action shows a clear description, estimated impact, and whether it mutates data
- Mutating actions require confirmation dialog
- VACUUM shows estimated time based on file size and warns about disk space requirement
- Long-running operations show progress indicator and support cancellation where possible
- Results displayed in a dedicated output panel (integrity_check returns row-per-issue)

### 8.7 Query Plan Inspection

Support `EXPLAIN QUERY PLAN` with a structured visual representation.

**Implementation:**

```sql
EXPLAIN QUERY PLAN SELECT * FROM users WHERE email = 'test@example.com';
```

Returns rows with `id`, `parent`, `notused`, `detail` columns. The `detail` column contains human-readable descriptions:

```
SEARCH users USING INDEX idx_users_email (email=?)
SCAN products
USE TEMP B-TREE FOR ORDER BY
COMPOUND SUBQUERIES 1 AND 2 USING TEMP B-TREE (UNION)
```

**Visual representation:**
- Parse `id`/`parent` relationships into a tree structure
- Render as an indented tree view (SwiftUI `OutlineGroup` or custom tree)
- Color-code by operation type:
  - 🟢 `SEARCH … USING INDEX` — indexed lookup (efficient)
  - 🟡 `SCAN` — full table scan (potential concern)
  - 🔴 `USE TEMP B-TREE` — temporary materialization (expensive for large sets)
  - ⚪ `COMPOUND SUBQUERIES` — set operation
- Show the original SQL alongside the plan for comparison
- Add "Run with EXPLAIN QUERY PLAN" button in the SQL editor toolbar

### 8.8 Export

| Format | Implementation | Source |
|--------|---------------|--------|
| CSV | Existing `CSVExporter` — zero changes | Query results or full table |
| JSON | Existing `JSONDocument` + export logic — zero changes | Query results or full table |
| Copy results | Existing clipboard integration | Selected cells or rows |
| Schema/DDL copy | `SELECT sql FROM sqlite_master WHERE name = ?` | Selected table(s) |
| Full schema export | `SELECT sql FROM sqlite_master ORDER BY type, name` | Entire database |

### 8.9 BLOB Inspection

**Detection strategy:**
1. SQLite stores BLOBs as binary data. GRDB returns `Data` for BLOB columns.
2. Never assume a BLOB's content type — always detect from magic bytes.

**Content detection (by file signature / magic bytes):**

| Type | Magic Bytes | Display |
|------|-------------|---------|
| PNG | `89 50 4E 47` | Inline image preview (NSImage) |
| JPEG | `FF D8 FF` | Inline image preview |
| GIF | `47 49 46 38` | Inline image preview |
| WebP | `52 49 46 46 … 57 45 42 50` | Inline image preview |
| PDF | `25 50 44 46` | "PDF document, N pages" + Quick Look |
| JSON (UTF-8) | Starts with `{` or `[` after trim | Pretty-printed JSON view |
| Plain text (UTF-8) | Valid UTF-8 sequence | Text view with encoding indicator |
| SQLite database | `53 51 4C 69 74 65` | "SQLite database (N bytes)" |
| Other binary | — | Hex dump view (first 256 bytes) + "N bytes total" |

**Display in data browser:**
- Default cell display: `[BLOB: 1,234 bytes]` (no inline render in table)
- Click/double-click: Open BLOB inspector panel
- BLOB inspector shows detected type, raw size, and appropriate renderer
- For images: show actual image with dimensions
- For text/JSON: show formatted content
- For unknown binary: hex view with ASCII sidebar
- "Save to File…" button for any BLOB

---

## 9. SQLite-Specific Features

### 9.1 Database Discovery

**"Open Running App Database" flow:**

Allow users to select a directory and recursively discover SQLite databases.

**Implementation:**
1. User selects a directory via `NSOpenPanel` (directory selection mode)
2. Recursive scan with limits:
   - Max depth: 5 levels (configurable)
   - Max files scanned: 10,000
   - Skip: `.app` bundles, `node_modules`, `.git`, `__pycache__`, `.Trash`
   - Skip: symlinks to avoid cycles
   - Skip: files > 10 GB (not typical SQLite databases)
3. Detection strategy:
   - Match extensions: `.db`, `.sqlite`, `.sqlite3`
   - For extensionless files or unknown extensions: check first 16 bytes for SQLite header magic `SQLite format 3\000`
4. Present discovered databases in a list:
   - Filename
   - Full path (truncated with tooltip for long paths)
   - File size (human-readable)
   - Last modified date
   - Journal mode indicator if WAL file exists alongside

**Common discovery targets:**
- `~/.agent-afk/` — AFK agent databases
- `~/Library/Application Support/` — macOS app databases
- `~/Library/Containers/` — sandboxed app data
- Project directories — application databases

**Safety:**
- Read-only scan (no files opened or modified during discovery)
- Respect macOS sandbox permissions — user must grant directory access via `NSOpenPanel`
- Show permission-denied directories with a lock icon, not as errors
- Cancel button for long scans
- Background scan with progress indicator

### 9.2 WAL Awareness

When opening a database, detect associated WAL files:

| File | Purpose | Display |
|------|---------|---------|
| `database.db-wal` | Write-ahead log | Show WAL indicator badge; display WAL page count |
| `database.db-shm` | Shared memory for WAL | Show alongside WAL info |

**WAL information panel:**
- Current WAL size (file size of `.db-wal`)
- WAL page count (from `PRAGMA wal_checkpoint(PASSIVE)` return)
- Checkpoint status
- One-click WAL checkpoint action (with appropriate warnings)

**Safety:**
- Never suggest deleting WAL files directly — always use `PRAGMA wal_checkpoint`
- Warn if another application appears to have the database open (check for hot WAL)
- Display WAL mode as a read-only property, not a toggle (changing journal mode has implications)

### 9.3 Schema Visualization

**Lightweight ER diagram derived from foreign keys:**

```sql
-- Get all foreign key relationships
SELECT
    m.name AS source_table,
    p."from" AS source_column,
    p."table" AS target_table,
    p."to" AS target_column
FROM sqlite_master AS m
JOIN pragma_foreign_key_list(m.name) AS p
WHERE m.type = 'table';
```

**Display:**
- Render as a directed graph: boxes for tables, arrows for foreign key relationships
- Each box shows table name and primary key columns
- Arrows labeled with column names: `orders.user_id → users.id`
- Layout: auto-arranged with force-directed or hierarchical layout
- Support drag to rearrange
- Zoom and pan controls
- Click a table to navigate to its detail view

**Implementation note:** For MVP, a simple list-based relationship view (not a full graph) is sufficient. A visual graph can follow in a later phase. The key insight is that SQLite databases often lack foreign key declarations — many applications use implicit relationships (column naming conventions like `user_id` referencing `users.id`). The visualization should work from declared foreign keys only and not try to infer relationships.

### 9.4 FTS (Full-Text Search) Support

Recognize and provide useful inspection for FTS3/FTS4/FTS5 tables.

**Detection:**
- FTS5: Check for the `_content`, `_data`, `_docsize`, `_config`, `_idx` shadow table pattern
- FTS3/4: Check for `_content`, `_segments`, `_segdir` shadow table pattern
- Or: parse `CREATE VIRTUAL TABLE` DDL for `USING fts3/fts4/fts5`

**Inspection features:**
- Show FTS module type (fts3/fts4/fts5) and tokenizer
- Display content table (if external content)
- Show indexed columns
- Provide a "Search" interface that generates `MATCH` queries
- Show `rank` and `bm25()` scoring for results
- For FTS5: expose `fts5vocab` virtual table data for term statistics

### 9.5 JSON Support

Make JSON stored as TEXT particularly pleasant to inspect.

**Detection:** Attempt `json_valid(value)` or heuristic detection (starts with `{`/`[`, valid JSON parse).

**Features:**
- In-cell indicator when a TEXT value contains valid JSON
- Click to expand in the existing `JSONViewerView` (already implemented)
- Support for `json_extract()`, `json_each()`, `json_tree()` in autocomplete
- For JSONB columns (SQLite 3.45+): detect via `typeof()` returning `'blob'` and `json(column)` succeeding
- Display JSON with syntax highlighting and collapsible nodes

### 9.6 Attached Databases

Support `ATTACH DATABASE` for inspecting multiple SQLite files simultaneously.

**UI:**
- Sidebar section for "Attached Databases" showing the alias and file path
- Each attached database expands to show its own tables, views, indexes
- Queries can reference `attached_db.table_name`
- "Attach Database…" action in sidebar context menu or File menu
- "Detach" action per attached database

**Implementation:**
```sql
ATTACH DATABASE '/path/to/other.db' AS analytics;
-- Tables visible via:
SELECT name FROM analytics.sqlite_master WHERE type = 'table';
```

---

## 10. UX Flows

### 10.1 First Launch

```
App launches
  → WelcomeView shows
    → "Open Database" button (primary action)
    → "Recent Databases" list (empty on first launch)
    → "Discover Databases…" button
    → Brief feature summary
```

No connection form, no server configuration. The welcome screen should feel dramatically simpler than any database client that starts with a connection dialog.

### 10.2 Open Database

```
User clicks "Open Database" or uses ⌘O
  → NSOpenPanel with filters: .db, .sqlite, .sqlite3
  → User selects file
  → App opens file with GRDB
    → On success:
      → Create/update DatabaseFileProfile (SwiftData)
      → Save security-scoped bookmark
      → Discover tables, views, indexes, triggers
      → Show sidebar with database objects
      → Auto-select first table and display rows
    → On failure:
      → Show error sheet (file not found, permission denied, corrupt, locked)
      → Offer retry or open different file
```

### 10.3 Inspect Table

```
User clicks table name in sidebar
  → Load column metadata (PRAGMA table_info)
  → Execute SELECT * FROM "table" LIMIT 100 OFFSET 0
  → Display results in data browser
  → Show column info in inspector panel
  → Enable row editing if table has a PK and database is not read-only
```

### 10.4 Execute SQL

```
User types SQL in editor
  → ⌘Enter to execute
  → Split multi-statement SQL
  → Execute each statement sequentially
  → For SELECT: show results in table view
  → For INSERT/UPDATE/DELETE: show affected-row count + success toast
  → For DDL: show success + refresh sidebar
  → For errors: show error message with SQLite error code
  → Record in query history
```

### 10.5 Database Maintenance

```
User opens "Database Health" inspector
  → Automatically load all PRAGMA values
  → Show health dashboard with all metrics
  → User clicks "Run Integrity Check"
    → Confirmation dialog: "This may take a while for large databases"
    → Execute PRAGMA integrity_check
    → Show results (ok / list of issues)
  → User clicks "VACUUM"
    → Warning: "Requires ~142 MB free disk space. Database will be locked."
    → Confirmation dialog
    → Execute VACUUM with progress indicator
    → Show result (new file size, space saved)
```

---

## 11. Data Model / Type-Handling Strategy

### 11.1 SQLite Type Affinity

SQLite uses dynamic typing with "type affinity" — a column's declared type suggests but does not enforce a storage class (unless the table is STRICT).

| Declared Type | Affinity | Actual Storage Classes |
|--------------|----------|----------------------|
| `INT`, `INTEGER`, `TINYINT`, `BIGINT` | INTEGER | INTEGER, REAL, TEXT, BLOB, NULL |
| `CHAR`, `VARCHAR`, `TEXT`, `CLOB` | TEXT | INTEGER, REAL, TEXT, BLOB, NULL |
| `REAL`, `FLOAT`, `DOUBLE` | REAL | INTEGER, REAL, TEXT, BLOB, NULL |
| `BLOB`, (no type) | BLOB | INTEGER, REAL, TEXT, BLOB, NULL |
| `NUMERIC`, `DECIMAL`, `BOOLEAN`, `DATE` | NUMERIC | INTEGER, REAL, TEXT, BLOB, NULL |

**Display strategy:**
- Show the declared type from `PRAGMA table_info()` as the column type
- In the data browser, show the actual stored value with its storage class
- When the actual storage class differs from the affinity (e.g., TEXT stored in an INTEGER column), show a visual indicator (small badge or different text color)
- For STRICT tables, validate input against declared types on edit

### 11.2 Type Display in Data Browser

| Storage Class | Display |
|---------------|---------|
| NULL | Grey italic `NULL` |
| INTEGER | Right-aligned number |
| REAL | Right-aligned decimal (respect locale formatting) |
| TEXT | Left-aligned string |
| BLOB | `[BLOB: N bytes]` with click-to-inspect |

### 11.3 Existing TableRow Model

The existing `TableRow` is `struct TableRow: Identifiable { var values: [String: String?] }` — all values are string-encoded with `nil` for NULL. This is simple and works well for display.

For SQLite, we maintain this pattern:
- INTEGER → `String(value)` (e.g., `"42"`)
- REAL → `String(value)` (e.g., `"3.14"`)
- TEXT → value as-is
- BLOB → `"[BLOB: N bytes]"` placeholder
- NULL → `nil`

This preserves full compatibility with the existing `QueryResultsComponent`, `CSVExporter`, `JSONViewerView`, and all other consumers.

### 11.4 Type Detection for Editing

When editing a cell, the editor needs to know the target storage class to construct the correct SQL:

```swift
// For INSERT/UPDATE, use appropriate SQL parameter binding:
// "42" → INTEGER binding if column affinity is INTEGER
// "hello" → TEXT binding always
// nil → NULL binding
// BLOB → Data binding
```

GRDB handles this automatically with `DatabaseValue`:
```swift
let value: DatabaseValue = .init(value: Int64(42))  // INTEGER
let value: DatabaseValue = .init(value: "hello")     // TEXT
let value: DatabaseValue = .null                      // NULL
```

---

## 12. Query Execution Architecture

### 12.1 Query Pipeline (SQLite)

```
User action
  → AppState.requestTableQuery() or AppState.executeSQLQuery()
    → QueryService.executeDisplayQuery()
      → For table browse: simple SELECT * (no to_jsonb wrapping)
      → SQLiteConnectionManager.withConnection { connection in
          SQLiteQueryExecutor.executeQuery(connection, sql)
        }
        → SQLiteDatabaseConnection.executeQuery(sql)
          → GRDB db.execute(sql) or db.makeStatement(sql).cursor()
            → Row iteration
      → SQLiteResultMapper.mapRowsToTableRows(rows)
        → [TableRow]
    → TableBrowseResultCompactor (truncates long cells — unchanged)
  → QueryState.queryResults = results
```

Key simplification: no `to_jsonb()` wrapping/unwrapping, no `QueryResultNormalizer`.

### 12.2 SQLiteQueryExecutor Implementation Sketch

```swift
final class SQLiteQueryExecutor: QueryExecutorProtocol {
    func fetchTables(connection: DatabaseConnectionProtocol) async throws -> [TableInfo] {
        let rows = try await connection.executeQuery("""
            SELECT name, type, sql FROM sqlite_master
            WHERE type IN ('table', 'view')
            AND name NOT LIKE 'sqlite_%'
            ORDER BY type DESC, name ASC
        """)
        return try await resultMapper.mapToTableInfos(rows)
    }

    func fetchColumns(connection: DatabaseConnectionProtocol,
                      schema: String, table: String) async throws -> [ColumnInfo] {
        let rows = try await connection.executeQuery(
            "PRAGMA table_xinfo(\(table.quotedDatabaseIdentifier))")
        return try await resultMapper.mapToColumnInfos(rows)
    }

    func fetchPrimaryKeys(connection: DatabaseConnectionProtocol,
                          schema: String, table: String) async throws -> [String] {
        let rows = try await connection.executeQuery(
            "PRAGMA table_info(\(table.quotedDatabaseIdentifier))")
        // Filter rows where pk > 0, sort by pk value
        return try await resultMapper.extractPrimaryKeyNames(rows)
    }

    func generateDDL(connection: DatabaseConnectionProtocol,
                     schema: String, table: String) async throws -> String {
        let rows = try await connection.executeQuery(
            "SELECT sql FROM sqlite_master WHERE name = ? AND type IN ('table', 'view')",
            parameters: [.init(value: table, type: .string)])
        // Return the CREATE statement directly
        return try await resultMapper.extractSingleString(rows) ?? "-- No DDL found"
    }

    func fetchTableData(connection: DatabaseConnectionProtocol,
                        schema: String, table: String,
                        limit: Int, offset: Int) async throws -> [TableRow] {
        let sql = """
            SELECT rowid, * FROM \(table.quotedDatabaseIdentifier)
            LIMIT \(limit) OFFSET \(offset)
        """
        let rows = try await connection.executeQuery(sql)
        return try await resultMapper.mapRowsToTableRows(rows)
    }
}
```

### 12.3 Multi-Statement Execution

The existing `SQLStatementSplitter` handles semicolons, quoted strings, and comments correctly for SQLite. Each statement is executed sequentially:

```swift
let statements = SQLStatementSplitter.split(sql)
var results: [QueryResult] = []
for statement in statements {
    let result = try await executeStatement(connection, statement)
    results.append(result)
}
```

### 12.4 Transaction Handling

SQLite supports `BEGIN`/`COMMIT`/`ROLLBACK`. The existing transaction wrapping in `DatabaseService.executeQueryInternal` uses standard SQL and works unchanged:

```swift
try await connection.executeQuery("BEGIN")
defer { try? await connection.executeQuery("ROLLBACK") }
// ... execute statements ...
try await connection.executeQuery("COMMIT")
```

For single-statement queries, no explicit transaction is needed — SQLite auto-commits.

---

## 13. Editing / Write Architecture

### 13.1 Row Identification

| Table Type | Row Identifier | Strategy |
|-----------|---------------|----------|
| Regular table (with rowid) | `rowid` | Fetch with `SELECT rowid, * FROM table`; use rowid for UPDATE/DELETE WHERE |
| `INTEGER PRIMARY KEY` column | Column value (= rowid alias) | Same as rowid, no separate fetch needed |
| Explicit composite PK | PK column values | `WHERE pk1 = ? AND pk2 = ?` |
| `WITHOUT ROWID` table | Explicit PK columns | PK required; if no PK, table is read-only |
| Table with no PK and no rowid | — | **Read-only display only** |

### 13.2 UPDATE

```swift
func updateRow(connection: DatabaseConnectionProtocol,
               schema: String, table: String,
               primaryKeyColumns: [String],
               originalRow: TableRow,
               updatedValues: [String: String?]) async throws {
    let setClauses = updatedValues.keys.map { "\($0.quotedDatabaseIdentifier) = ?" }
    let whereClauses = primaryKeyColumns.map { "\($0.quotedDatabaseIdentifier) = ?" }

    let sql = """
        UPDATE \(table.quotedDatabaseIdentifier)
        SET \(setClauses.joined(separator: ", "))
        WHERE \(whereClauses.joined(separator: " AND "))
    """

    let params: [DatabaseParameter] = /* SET values + WHERE values */
    try await connection.executeQuery(sql, parameters: params)
}
```

### 13.3 INSERT

```swift
func insertRow(connection: DatabaseConnectionProtocol,
               schema: String, table: String,
               values: [String: String?]) async throws {
    let columns = values.keys.map { $0.quotedDatabaseIdentifier }
    let placeholders = Array(repeating: "?", count: values.count)

    let sql = """
        INSERT INTO \(table.quotedDatabaseIdentifier)
        (\(columns.joined(separator: ", ")))
        VALUES (\(placeholders.joined(separator: ", ")))
    """

    let params: [DatabaseParameter] = /* values */
    try await connection.executeQuery(sql, parameters: params)
}
```

### 13.4 DELETE

```swift
func deleteRows(connection: DatabaseConnectionProtocol,
                schema: String, table: String,
                primaryKeyColumns: [String],
                rows: [TableRow]) async throws {
    for row in rows {
        let whereClauses = primaryKeyColumns.map { "\($0.quotedDatabaseIdentifier) = ?" }
        let sql = """
            DELETE FROM \(table.quotedDatabaseIdentifier)
            WHERE \(whereClauses.joined(separator: " AND "))
        """
        let params: [DatabaseParameter] = /* PK values from row */
        try await connection.executeQuery(sql, parameters: params)
    }
}
```

### 13.5 Write Safety

- All writes execute within a transaction
- Writes are rejected for read-only databases
- Writes are rejected for tables without identifiable primary keys (no PK + no rowid)
- Generated columns are excluded from INSERT/UPDATE
- Foreign key violations surface as clear error messages (not raw SQLITE_CONSTRAINT)
- The mutation toast (existing `MutationToastView`) shows affected-row counts

---

## 14. Safety Model

### 14.1 Destructive SQL Protection

**Dangerous query detection:**
```swift
enum QueryDangerLevel {
    case safe          // SELECT, EXPLAIN, PRAGMA (read-only)
    case caution       // INSERT, UPDATE with WHERE, CREATE, ALTER
    case dangerous     // DELETE/UPDATE without WHERE, DROP, VACUUM
    case destructive   // DROP TABLE, DROP INDEX, DROP TRIGGER
}
```

**Protection rules:**
- `DELETE FROM table` without `WHERE` → confirmation dialog: "This will delete ALL rows from [table]. Are you sure?"
- `UPDATE table SET …` without `WHERE` → confirmation dialog: "This will update ALL rows in [table]. Are you sure?"
- `DROP TABLE` → confirmation dialog: "This will permanently delete table [name] and all its data."
- `VACUUM` → warning about disk space and exclusive lock
- All confirmations show the exact SQL being executed

### 14.2 Read-Only Mode

Users can open databases in read-only mode:
- GRDB `Configuration.readonly = true` — SQLite will reject all write operations at the library level
- Visual indicator in title bar and toolbar: "🔒 Read-Only"
- Write actions (edit, insert, delete) are disabled in the UI
- SQL editor shows a warning banner for write statements

**Automatic read-only:** If the file is not writable (macOS permissions), automatically open in read-only mode with a notification.

### 14.3 Database Lock Handling

SQLite's locking model differs fundamentally from client-server databases:

| Scenario | Behavior |
|----------|----------|
| Another app has a SHARED lock | Our reads succeed; our writes wait up to `busyTimeout` |
| Another app has a RESERVED/EXCLUSIVE lock | Our reads succeed (in WAL mode); our writes wait or fail |
| We have an exclusive lock (VACUUM) | Other apps' reads may fail |
| Database file is locked by a crash | Check for hot journal; offer recovery |

**Configuration:**
```swift
config.busyMode = .timeout(5.0)  // Wait 5 seconds for locks
```

**Error handling:**
- `SQLITE_BUSY` → "Database is busy. Another application may be using it. Retry?"
- `SQLITE_LOCKED` → "Database table is locked. Try again in a moment."
- Never corrupt the database by forcing locks

### 14.4 Transaction Safety

- Single-row edits auto-commit (no explicit transaction needed for simple UPDATE/DELETE)
- Multi-row deletes execute in a transaction — all-or-nothing
- Failed writes roll back completely
- Partially completed multi-statement scripts: each statement is tracked; errors show which statement failed with its position

### 14.5 Concurrent Access

SQLite handles concurrent access differently from PostgreSQL:
- WAL mode allows concurrent reads + one writer
- Non-WAL mode: readers can block writers and vice versa
- The app should display the current journal mode and explain its concurrency implications

**Practical approach:**
- Open databases with `PRAGMA busy_timeout = 5000` (5 seconds)
- Display a lock indicator when the database is busy
- Never assume exclusive access — another process may be writing
- Support "Refresh" to re-read data that may have changed externally

### 14.6 Optional Safe Mode

An optional "Safe Mode" toggle in the toolbar:
- **When enabled:**
  - All write queries require confirmation
  - `DROP`, `DELETE`, `UPDATE`, `ALTER`, `VACUUM` always show confirmation dialogs
  - DDL statements are blocked entirely
  - Visual indicator: amber toolbar tint
- **When disabled:**
  - Only WHERE-less `DELETE`/`UPDATE` and `DROP` require confirmation
  - Normal editing permitted

Safe Mode preference is persisted per-database in `DatabaseFileProfile`.

---

## 15. Performance Strategy

### 15.1 Known Bottlenecks

**SwiftUI Table performance:** SwiftUI's `Table` view struggles with more than ~10,000 visible rows. For SQLite databases with millions of rows, virtualization is essential.

**Large result sets:** Loading all rows into memory is impractical for large tables.

**BLOB-heavy tables:** Tables with large BLOBs can cause excessive memory use if all fetched eagerly.

**Large TEXT fields:** Cells with very long text can cause layout thrashing.

### 15.2 Pagination Strategy

**Page-based loading (existing pattern):**
- Default page size: 100 rows
- User-configurable: 50 / 100 / 250 / 500 / 1000
- `SELECT * FROM table LIMIT pageSize OFFSET (page * pageSize)`
- Page navigation: First / Previous / Next / Last / Jump to Page
- Page cache: LRU cache holding recent pages (existing `TableBrowsePageCacheContext`)
- Background prefetch: preload next page while user views current page

**Total row count:**
- `SELECT COUNT(*) FROM table` — executed once on table selection
- Displayed as "Showing rows 1–100 of 1,234,567"
- For very large tables (> 1M rows): use `SELECT COUNT(*) OVER() FROM table LIMIT 1` or show estimate

### 15.3 Lazy Loading

- **BLOB columns:** Do not include BLOB data in the default browse query. Instead: `SELECT rowid, col1, col2, length(blob_col) AS blob_col_size FROM table`. Load actual BLOB data only when the user clicks "Inspect."
- **Long TEXT fields:** Truncate at `Constants.tableBrowseMaxCellCharacters` (2,048 chars) in the browse view. Show full text in the detail/edit inspector.
- **Column metadata:** Fetched once per table selection, cached in `ConnectionState.metadataCache`.

### 15.4 Result Limits

- Browse queries: always use `LIMIT`/`OFFSET`
- User SQL: apply a default `LIMIT 10000` for SELECT queries without an explicit LIMIT (configurable in Settings)
- Show warning: "Results limited to 10,000 rows. Add a LIMIT clause for specific control."

### 15.5 Cancellation

- Query execution uses Swift's structured concurrency (`Task`)
- Existing `QueryService` tracks tasks and cancels superseded ones
- SQLite supports `sqlite3_interrupt()` — GRDB exposes this via `Database.interrupt()`
- Long-running queries can be cancelled via the Cancel button in the SQL editor
- Table browse cancels the in-flight query when the user switches tables (existing behavior)

### 15.6 Background Query Execution

All query execution already happens off the main thread via `async`/`await` and GRDB's `DatabaseQueue.read {}` / `DatabaseQueue.write {}` (which dispatch to GRDB's serial queue). The UI remains responsive during long queries.

### 15.7 Memory Boundaries

- Page cache limited to `Constants.maxCachedPages` pages (existing)
- BLOB data loaded on-demand, not cached
- Query results limited by `LIMIT` clauses
- Large databases (> 1 GB) display a notification suggesting performance-sensitive operations
- GRDB's `DatabasePool` for read-heavy workloads (concurrent reads)

### 15.8 SwiftUI Table Optimization

- Use `LazyVStack` within `ScrollView` instead of `List` for very large result sets (if SwiftUI `Table` performance is insufficient)
- Fixed-size rows: avoid dynamic height calculation
- Debounce column resize events
- Defer full render of off-screen cells
- Profile with Instruments on macOS 26 to validate SwiftUI `Table` limits

---

## 16. Testing Strategy

### 16.1 Existing Test Coverage

The project has 17 test files with ~2,200 lines covering:
- Race condition correctness (stale query rejection, superseded query handling)
- Pure function correctness (SQL parsing, CSV export, type detection)
- State management (cache, pagination, metadata)
- Service integration (with protocol-based mocks)

**Test portability assessment:**

| Portability | Test Files | Action |
|------------|-----------|--------|
| 100% portable | 8 files | Keep unchanged |
| 70–95% portable | 5 files | Adapt (remove PG-specific tests) |
| 0% portable | 4 files | Delete and replace |

### 16.2 New Tests Required

**SQLite connection tests:**
- Open valid database file → success
- Open nonexistent file → `FileOpenError.fileNotFound`
- Open file without permission → `FileOpenError.permissionDenied`
- Open corrupt file → `FileOpenError.corruptDatabase`
- Open locked file → `FileOpenError.fileLocked`
- Open in read-only mode → writes rejected
- Security-scoped bookmark creation and resolution

**SQLite query executor tests:**
- Fetch tables from `sqlite_master`
- Fetch columns via `PRAGMA table_info`
- Fetch primary keys (single, composite, rowid alias, WITHOUT ROWID)
- Generate DDL
- Execute SELECT with pagination
- Execute INSERT/UPDATE/DELETE
- Handle SQLite-specific types (BLOB, NULL)
- FTS table detection
- Virtual table detection
- Attached database table enumeration

**SQLite result mapper tests:**
- Map all SQLite storage classes (INTEGER, REAL, TEXT, BLOB, NULL)
- Handle type affinity mismatches
- Map PRAGMA output to domain models

**Integration tests:**
- Create in-memory SQLite database
- Insert test data
- Verify full query pipeline: SQL → execute → map → display
- Test pagination with known row counts
- Test editing: insert, update, delete
- Test transaction rollback on error

**Database health tests:**
- Parse all PRAGMA outputs
- Integrity check parsing
- WAL status detection
- File size calculation

### 16.3 Test Infrastructure

Use in-memory SQLite databases for tests — no file I/O needed, fast and isolated:

```swift
let dbQueue = try DatabaseQueue(named: "test")
try dbQueue.write { db in
    try db.execute(sql: """
        CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, email TEXT);
        INSERT INTO users VALUES (1, 'Alice', 'alice@test.com');
    """)
}
```

The existing protocol-based mock infrastructure (`MockDatabaseService`, `MockConnectionManager`, etc.) supports injecting test implementations. Create `SQLiteTestConnectionManager` wrapping an in-memory GRDB `DatabaseQueue`.

---

## 17. Migration Plan

### Phase 0: Preparation (Build Baseline)
- Configure code signing and verify the existing PostgresGUI builds on macOS 26
- Run existing tests to establish baseline (expecting all pass)
- Create a feature branch for the SQLite port

### Phase 1: Foundation (File-Based Connection)
- See §22 for the detailed first implementation slice
- Add GRDB.swift as SPM dependency
- Create `Services/SQLite/` directory with all 4 implementations
- Replace `ConnectionProfile` with `DatabaseFileProfile`
- Adapt `ConnectionManagerProtocol.connect()` signature
- Result: can open a `.sqlite` file and execute raw SQL

### Phase 2: Table Discovery and Browsing
- Implement `SQLiteQueryExecutor.fetchTables()`
- Implement `SQLiteQueryExecutor.fetchColumns()`
- Implement `SQLiteQueryExecutor.fetchPrimaryKeys()`
- Adapt sidebar to show flat table list (remove schema grouping)
- Result: sidebar shows tables; clicking a table shows rows

### Phase 3: Data Editing
- Implement `SQLiteQueryExecutor.updateRow()` and `deleteRows()`
- Handle rowid-based identification
- Handle WITHOUT ROWID and STRICT table edge cases
- Wire up existing `RowEditorView` and `RowOperationsService`
- Result: inline editing, insert, delete work

### Phase 4: Database Health Inspector
- Implement PRAGMA-based health dashboard
- Build maintenance action UI (integrity check, VACUUM, ANALYZE)
- Add WAL awareness and checkpoint action
- Result: full database health panel

### Phase 5: EXPLAIN QUERY PLAN
- Parse EXPLAIN QUERY PLAN output into tree structure
- Build tree/outline view for query plans
- Add "Explain" button to SQL editor toolbar
- Result: visual query plan inspection

### Phase 6: SQLite-Specific Features
- Database discovery ("Open Running App Database")
- FTS table recognition and search interface
- JSON pretty inspection for TEXT columns
- BLOB content detection and inspection
- Attached database support (ATTACH/DETACH)
- Result: differentiated SQLite inspector features

### Phase 7: Polish and Safety
- Implement Safe Mode
- Add destructive query confirmation dialogs
- Handle edge cases (locked databases, corrupt files, permissions)
- Security-scoped bookmarks for persistent file access
- Performance profiling and optimization for large databases
- Result: production-ready safety and performance

### Phase 8: Cleanup and Branding
- Remove all PostgreSQL code (`Services/Postgres/`, `Services/SSH/`, related types/errors)
- Remove PostgresNIO and Citadel SPM dependencies
- Update entitlements (remove network entitlements)
- Rename targets, bundle identifiers, assets
- Update README
- Result: clean SQLiteGUI codebase with no PostgreSQL vestiges

---

## 18. Licensing Findings

### 18.1 License Text

The repository uses the **O'Saasy license** — a variant of MIT with a SaaS restriction. The full text is in `/LICENSE`:

> **Copyright © 2025, Fikri Ghazi.**
>
> Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
>
> 1. The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
> 2. No licensee or downstream recipient may use the Software (including any modified or derivative versions) to directly compete with the original Licensor by offering it to third parties as a hosted, managed, or Software-as-a-Service (SaaS) product or cloud service where the primary value of the service is the functionality of the Software itself.

### 18.2 Analysis

| Question | Answer |
|----------|--------|
| **Is forking permitted?** | Yes — "to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies" |
| **Attribution requirements** | Copyright notice + permission notice must be included in all copies or substantial portions |
| **Can the derivative be redistributed via GitHub?** | Yes — distribution is explicitly permitted |
| **Can it be distributed commercially?** | Yes — "sell copies" is explicitly permitted. The only restriction is SaaS. |
| **SaaS restriction** | May NOT offer the software as a "hosted, managed, or Software-as-a-Service (SaaS) product or cloud service where the primary value of the service is the functionality of the Software itself." A native macOS desktop app is not SaaS — this restriction does not apply to our use case. |
| **Mac App Store distribution** | The license permits distribution ("sublicense", "sell copies"). The Mac App Store's EULA does not conflict with O'Saasy. However, Apple's App Store guidelines require the developer to have rights to distribute the software — the O'Saasy grant covers this. The SaaS restriction is irrelevant for App Store distribution (not a cloud service). |

### 18.3 Requirements

1. Include the original copyright notice and permission notice in the distributed application (in About dialog, LICENSE file, or similar)
2. Do not offer the derivative as a SaaS/cloud service competing with PostgresGUI
3. A native macOS desktop application distributed via GitHub or Mac App Store is fully compliant

---

## 19. Known Technical Risks

### Risk 1: macOS 26 Deployment Target (High)
The project targets macOS 26 — an unreleased OS available only in Xcode 26 betas. This means:
- Builds require Xcode 26+ (beta or release)
- Testing requires macOS 26 (beta or release)
- App Store distribution is limited to macOS 26+

**Mitigation:** Accept this constraint for now. The project already targets macOS 26; changing the deployment target risks breaking existing SwiftUI 26-specific UI.

### Risk 2: SwiftUI Table Performance with Large Datasets (Medium)
SwiftUI's `Table` view may struggle with very large result sets even with pagination. The existing codebase does not appear to have been tested with millions of rows.

**Mitigation:** Page size limits (max 1,000 rows per page), BLOB lazy loading, cell value truncation (existing), and profiling with Instruments on actual large databases.

### Risk 3: App Sandbox + File Access Persistence (Medium)
macOS sandbox restricts file access. When a user opens a `.sqlite` file, the app gets temporary access. On next launch, access must be restored via security-scoped bookmarks. If the bookmark is stale (file moved/deleted), access fails silently.

**Mitigation:** Implement robust security-scoped bookmark management in `FileAccessService`. Detect stale bookmarks and prompt for re-selection. Test bookmark persistence across app restarts.

### Risk 4: SQLite Busy/Lock Contention (Low–Medium)
SQLite databases used by running applications (e.g., an agent-afk session using its memory.db) may have active writers that cause lock contention.

**Mitigation:** WAL mode awareness, `PRAGMA busy_timeout = 5000`, read-only mode option, clear error messages for lock failures.

### Risk 5: GRDB Version Compatibility (Low)
GRDB must support macOS 26 deployment target and be compatible with Swift 5 / Xcode 26.

**Mitigation:** GRDB has historically been prompt with Xcode beta support. Verify compatibility before starting implementation.

### Risk 6: WITHOUT ROWID Tables (Low)
Some tables cannot be edited if they lack explicit primary keys and don't have a rowid. The editing architecture must handle this gracefully.

**Mitigation:** Detect WITHOUT ROWID tables from DDL; show them as read-only when no PK exists; communicate this clearly in the UI.

---

## 20. Open Questions

1. **Should we support SQLCipher (encrypted databases)?** This would require using a custom SQLite build or the SQLCipher SPM package instead of system SQLite. GRDB supports this but it adds complexity. Deferred to post-MVP.

2. **Should the schema visualizer use a proper graph rendering library or a simple list?** A force-directed graph is more useful but significantly more work. Recommend starting with a list-based relationship view and adding a graph in a later phase.

3. **Should we support opening databases from URLs (e.g., `sqlitegui://open?path=...`)?** This is useful for integration with other tools. Deferred to post-MVP.

4. **Should we support creating new empty databases?** The PostgresGUI has `CREATE DATABASE` — the SQLite equivalent is creating a new empty `.sqlite` file. Low effort to implement; decide whether it's in MVP scope.

5. **Should we preserve the multi-tab architecture or simplify to single-tab?** The existing tab system is database-agnostic and works well. Recommend keeping it — each tab can have a different query context against the same database file, which is useful for developers.

6. **macOS 26 minimum or backport to macOS 15?** The current codebase is macOS 26-only. Backporting may require removing macOS 26-specific SwiftUI features.

7. **Product name.** "SQLiteGUI" is the working name. Final naming is deferred but the spec identifies all branding locations that need updating (§Phase 8 in implementation plan, below).

---

## 21. Implementation Phases

### Phase 1: Foundation — Open SQLite File and Execute SQL
**Objective:** Minimal vertical slice from app launch to displaying SQL query results.

| Component | Action | Files | Effort |
|-----------|--------|-------|--------|
| Add GRDB dependency | Add to Xcode SPM | `project.pbxproj` | 10 min |
| SQLite connection manager | New | `Services/SQLite/SQLiteConnectionManager.swift` | 4 hours |
| SQLite database connection | New | `Services/SQLite/SQLiteDatabaseConnection.swift` | 3 hours |
| SQLite query executor | New (minimal — `executeQuery` only) | `Services/SQLite/SQLiteQueryExecutor.swift` | 4 hours |
| SQLite result mapper | New | `Services/SQLite/SQLiteResultMapper.swift` | 3 hours |
| Database file profile model | New | `Models/DatabaseFileProfile.swift` | 1 hour |
| File open error types | New | `Errors/FileOpenError.swift` | 30 min |
| Adapt connection protocol | Edit signature | `Protocols/ConnectionManagerProtocol.swift` | 1 hour |
| Adapt database service | Wire SQLite implementations | `Services/DatabaseService.swift` | 2 hours |
| File open view | New (simple file picker) | `Views/Containers/File/FileOpenView.swift` | 2 hours |
| Adapt app entry point | Wire new profile model | `PostgresGUIApp.swift` | 1 hour |
| Tests | New connection + execution tests | `PostgresGUITests/SQLite*Tests.swift` | 3 hours |
| **Total** | | | **~24 hours** |
| **Completion criteria** | Launch app → Open .sqlite file → Type SQL → See results | | |

### Phase 2: Table Discovery and Browsing
**Objective:** Sidebar table list, column inspection, paginated browsing.

| Component | Action | Effort |
|-----------|--------|--------|
| Implement `fetchTables()` | SQLite query executor | 2 hours |
| Implement `fetchColumns()` | PRAGMA table_info/table_xinfo | 2 hours |
| Implement `fetchPrimaryKeys()` | PRAGMA table_info → pk column | 1 hour |
| Implement `generateDDL()` | sqlite_master query | 30 min |
| Adapt sidebar | Remove schema picker/grouping | 3 hours |
| Adapt table list | Flat list, remove foreign table type | 1 hour |
| Syntax highlighting | SQLite keyword set | 2 hours |
| Adapt constants | Remove PostgreSQL defaults | 30 min |
| Tests | Table discovery, column parsing | 3 hours |
| **Total** | | **~15 hours** |
| **Completion criteria** | Open file → See table list → Click table → See rows with pagination | |

### Phase 3: Data Editing
**Objective:** Insert, update, delete rows in non-read-only databases.

| Component | Action | Effort |
|-----------|--------|--------|
| Implement `updateRow()` | rowid-based and PK-based | 3 hours |
| Implement `deleteRows()` | Transaction-wrapped | 2 hours |
| Implement `insertRow()` | New | 2 hours |
| Handle rowid edge cases | WITHOUT ROWID, INTEGER PRIMARY KEY alias | 3 hours |
| Handle generated columns | Exclude from write operations | 1 hour |
| Handle STRICT tables | Type validation on input | 2 hours |
| Adapt row editor view | SQLite type awareness | 2 hours |
| Tests | CRUD operations, edge cases | 4 hours |
| **Total** | | **~19 hours** |
| **Completion criteria** | Edit cell → Save → Verify change persisted | |

### Phase 4: Database Health Inspector
**Objective:** PRAGMA-based health dashboard with maintenance actions.

| Component | Action | Effort |
|-----------|--------|--------|
| Health data model | New `DatabaseHealth` struct | 1 hour |
| PRAGMA query service | Fetch all health metrics | 3 hours |
| Health dashboard view | New inspector panel | 4 hours |
| Maintenance actions | Integrity check, VACUUM, ANALYZE, checkpoint | 3 hours |
| WAL awareness | Detect WAL files, show status | 2 hours |
| Confirmation dialogs | For mutating actions | 1 hour |
| Tests | PRAGMA parsing, health model | 2 hours |
| **Total** | | **~16 hours** |
| **Completion criteria** | Open health inspector → See all metrics → Run integrity check | |

### Phase 5: Query Plan Visualization
**Objective:** Visual EXPLAIN QUERY PLAN representation.

| Component | Action | Effort |
|-----------|--------|--------|
| EQP parser | Parse id/parent/detail into tree | 2 hours |
| Tree view | SwiftUI OutlineGroup render | 3 hours |
| Color coding | Operation type → color | 1 hour |
| Editor integration | "Explain" button in toolbar | 1 hour |
| Tests | Tree parsing, various query plans | 2 hours |
| **Total** | | **~9 hours** |

### Phase 6: SQLite-Specific Differentiators
**Objective:** Features that make this tool uniquely valuable for SQLite.

| Component | Action | Effort |
|-----------|--------|--------|
| Database discovery | Directory scan + file detection | 6 hours |
| FTS table support | Detection + search interface | 4 hours |
| JSON column inspection | Detection + pretty view | 3 hours |
| BLOB inspection | Magic byte detection + renderers | 5 hours |
| Attached databases | ATTACH/DETACH UI + sidebar section | 4 hours |
| Schema visualization | FK-based relationship list/tree | 6 hours |
| **Total** | | **~28 hours** |

### Phase 7: Safety and Polish
**Objective:** Production-ready safety, error handling, and performance.

| Component | Action | Effort |
|-----------|--------|--------|
| Safe Mode | Toggle + confirmation dialogs | 3 hours |
| Destructive SQL detection | Query analysis + prompts | 2 hours |
| Lock handling | Busy timeout, error messages | 2 hours |
| Security-scoped bookmarks | FileAccessService | 4 hours |
| Recent databases | NSDocumentController integration | 2 hours |
| Performance profiling | Large database testing | 4 hours |
| Drag-and-drop file opening | onDrop handler | 1 hour |
| Open With registration | UTType declarations in Info.plist | 2 hours |
| **Total** | | **~20 hours** |

### Phase 8: Cleanup and Branding
**Objective:** Remove all PostgreSQL code, rename to SQLiteGUI.

| Component | Action | Effort |
|-----------|--------|--------|
| Delete PostgreSQL implementation | Remove `Services/Postgres/`, `Services/SSH/` | 30 min |
| Delete PostgreSQL types/errors | Remove 7 files | 30 min |
| Delete PostgreSQL utilities | Remove QueryWrapping, QueryResultNormalizer | 15 min |
| Remove PostgresNIO + Citadel SPM deps | Xcode project changes | 30 min |
| Update entitlements | Remove network entitlements | 15 min |
| Rename targets and bundle IDs | Xcode project changes | 2 hours |
| Update assets (app icon, logo) | New SQLite-themed icon | 2 hours |
| Update README | New project description | 1 hour |
| Update tests | Remove PG-specific tests, verify all pass | 2 hours |
| **Total** | | **~9 hours** |

### Estimated Total Effort

| Phase | Effort |
|-------|--------|
| Phase 1: Foundation | ~24 hours |
| Phase 2: Table Discovery | ~15 hours |
| Phase 3: Data Editing | ~19 hours |
| Phase 4: Health Inspector | ~16 hours |
| Phase 5: Query Plans | ~9 hours |
| Phase 6: SQLite Features | ~28 hours |
| Phase 7: Safety/Polish | ~20 hours |
| Phase 8: Cleanup/Branding | ~9 hours |
| **Total** | **~140 hours** |

---

## 22. Concrete First Implementation Slice

### Objective

The smallest useful first slice gets us from:

```
Launch app → Open SQLite database → Discover tables → Select table → Display rows
```

This validates the full vertical stack (UI → ViewModel → State → Service → Protocol → SQLite Implementation → GRDB → sqlite3) without implementing editing, advanced inspectors, FTS, schema visualization, or any secondary feature.

### What This Slice Includes

1. **Add GRDB.swift as SPM dependency**
2. **New: `Services/SQLite/SQLiteDatabaseConnection.swift`** — implements `DatabaseConnectionProtocol` wrapping GRDB's `Database`
3. **New: `Services/SQLite/SQLiteConnectionManager.swift`** — implements `ConnectionManagerProtocol` wrapping GRDB's `DatabaseQueue`
4. **New: `Services/SQLite/SQLiteQueryExecutor.swift`** — implements `QueryExecutorProtocol` with `fetchTables`, `fetchColumns`, `fetchPrimaryKeys`, `fetchTableData`, `executeQuery` (others can stub/throw)
5. **New: `Services/SQLite/SQLiteResultMapper.swift`** — implements `ResultMapperProtocol` mapping GRDB `Row` to `TableRow`, `ColumnInfo`, `TableInfo`
6. **New: `Models/DatabaseFileProfile.swift`** — replaces `ConnectionProfile` for file-based "connections"
7. **New: `Errors/FileOpenError.swift`** — SQLite-specific error cases (fileNotFound, permissionDenied, corruptDatabase, fileLocked)
8. **Adapt: `Services/Protocols/ConnectionManagerProtocol.swift`** — change `connect()` signature to accept file path
9. **Adapt: `Services/DatabaseService.swift`** — wire SQLite implementations instead of PostgreSQL defaults
10. **Adapt: `Views/Containers/Connection/ConnectionFormView.swift`** — replace server form with file picker (or create new `FileOpenView`)
11. **Adapt: `Views/Containers/Sidebar/ConnectionsDatabasesSidebar.swift`** — show flat table list (no schema grouping)
12. **Adapt: `PostgresGUIApp.swift`** — wire new model container with `DatabaseFileProfile`

### What This Slice Explicitly Excludes

- Row editing (insert, update, delete)
- Database health inspector
- EXPLAIN QUERY PLAN visualization
- FTS recognition
- JSON column detection
- BLOB inspection
- Database discovery
- Attached databases
- Schema visualization
- Safe Mode
- Security-scoped bookmarks (use temporary access for now)
- Branding changes
- Removal of PostgreSQL code (keep it compiling alongside for safety)

### Completion Criteria

1. App launches without errors
2. User can open a `.sqlite`, `.db`, or `.sqlite3` file via file picker
3. Sidebar shows the list of tables discovered from `sqlite_master`
4. Clicking a table displays its rows in the data browser with pagination
5. User can type arbitrary SQL in the editor and see results
6. Column metadata (name, type, PK, nullable) is shown for selected tables
7. Tests pass for the new SQLite connection, execution, and mapping code

### Dependencies

- Xcode 26 (for macOS 26 target)
- GRDB.swift (compatible with macOS 26 deployment target)
- A sample `.sqlite` database for testing

### Expected Modifications per File

| File | Type | Key Changes |
|------|------|-------------|
| `project.pbxproj` | Edit | Add GRDB SPM dependency |
| `Services/SQLite/SQLiteConnectionManager.swift` | New | ~150 lines: actor with DatabaseQueue, connect/disconnect/withConnection |
| `Services/SQLite/SQLiteDatabaseConnection.swift` | New | ~120 lines: DatabaseConnectionProtocol wrapper around GRDB Database |
| `Services/SQLite/SQLiteQueryExecutor.swift` | New | ~250 lines: fetchTables, fetchColumns, fetchPrimaryKeys, fetchTableData, executeQuery |
| `Services/SQLite/SQLiteResultMapper.swift` | New | ~100 lines: Row → TableRow, Row → ColumnInfo, Row → TableInfo |
| `Models/DatabaseFileProfile.swift` | New | ~40 lines: SwiftData model with id, name, filePath, bookmarkData, timestamps |
| `Errors/FileOpenError.swift` | New | ~30 lines: enum with file-access error cases |
| `Protocols/ConnectionManagerProtocol.swift` | Edit | Change connect() signature: host/port/… → filePath/readOnly |
| `Protocols/DatabaseServiceProtocol.swift` | Edit | Cascade connect() signature change |
| `Services/DatabaseService.swift` | Edit | Init with SQLite types; adapt connect() calls |
| `Services/ConnectionService.swift` | Edit | Remove SSH tunnel logic; adapt to file-based connect |
| `Views/Containers/Connection/ConnectionFormView.swift` | Replace | File picker instead of server form |
| `ViewModels/ConnectionFormViewModel.swift` | Replace | File validation instead of connection validation |
| `Views/Containers/Sidebar/ConnectionsDatabasesSidebar.swift` | Edit | Remove SchemaPicker reference |
| `Views/Containers/Tables/TablesListView.swift` | Edit | Remove schema grouping path |
| `PostgresGUIApp.swift` | Edit | Wire DatabaseFileProfile model |
| `Persistence/PostgresGUIModelContainer.swift` | Edit | Register DatabaseFileProfile |
| `Constants.swift` | Edit | Remove PostgreSQL sub-enum |
| `PostgresGUITests/SQLiteConnectionTests.swift` | New | ~100 lines: connection + execution tests |
| `PostgresGUITests/SQLiteQueryExecutorTests.swift` | New | ~150 lines: table discovery + data fetch tests |

---

## Appendix: Branding Locations

Places where PostgresGUI/PostgreSQL branding exists and would eventually need to change:

| Location | Current Value | Action |
|----------|--------------|--------|
| `PostgresGUIApp.swift` | `Window("PostgresGUI", id: "main")` | Rename |
| `PostgresGUIApp.swift` | `"PostgresGUI Help"` | Rename |
| `PostgresGUIApp.swift` | `postgresgui.com/support` URL | Update/remove |
| `project.pbxproj` | `com.mghazi.PostgresGUI` bundle ID | Change |
| `Constants.swift` | `PostgreSQL` sub-enum | Rename to `Database` |
| `SyntaxHighlightedEditor.swift` | PostgreSQL keyword list | Replace with SQLite keywords |
| `WelcomeView.swift` | "PostgresGUI" text + logo | Update |
| `HelpView.swift` | PostgresGUI help content | Rewrite |
| `SettingsView.swift` | Any PostgresGUI references | Update |
| `Assets.xcassets/Logo.imageset/` | PostgreSQL elephant mascot | Replace |
| `Assets.xcassets/AppIcon.appiconset/` | PostgresGUI icon | Replace |
| `PostgresGUI.entitlements` | `com.postgresgui.connections` | Update |
| `KeychainService.swift` | `com.postgresgui.connections` service name | Update |
| `README.md` | Entire content | Rewrite |
| Directory: `PostgresGUI/` | Source directory name | Rename |
| Directory: `PostgresGUITests/` | Test directory name | Rename |
| Target: `PostgresGUI` | Xcode target name | Rename |
| Target: `PostgresGUITests` | Xcode test target name | Rename |
