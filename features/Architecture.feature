Feature: Core Architecture Setup
  As a developer
  I want to define the strict technology stack and architecture
  So that the codebase remains offline-first, decoupled, and highly scalable

  Background:
    Given the framework is "Flutter" (Dart)
    And the database engine is "SQLite"
    And all primary keys across all tables use "UUID v4"
    And all database tables include an "updated_at" column in ISO-8601 format
    And syncable tables whose business lifecycle allows discontinuation (e.g. "Producto") include a nullable "deleted_at" column (soft-delete / tombstone)
    And tables whose business lifecycle never allows deletion (e.g. "Venta" and its line items, which can only be created or reverted) do not have a "deleted_at" column
    And the state management solution is strictly decoupled from the UI (e.g., Riverpod or BLoC)
    And the conflict resolution strategy for synchronization is "Last Write Wins" (LWW)

  Scenario: Application Compilation Targets
    When the application is built
    Then it must support compiling to "Android" as a mobile APK/AAB
    And it must support compiling to "Windows/Linux" as a native desktop executable