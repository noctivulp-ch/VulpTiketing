Feature: Data Export, Import, and Sync
  As a user managing the system
  I want to backup, share catalog data, and synchronize without a cloud server
  So that the business operates offline seamlessly

  Scenario: Exporting a full backup
    Given the user is logged in (Any role)
    When the user requests a full database backup
    And provides an export password (separate from their login password)
    Then the system must bundle the SQLite database and settings
    And derive an encryption key from the export password (e.g., Argon2id)
    And encrypt the bundle with the derived key (e.g., AES-256-GCM)
    And export it as a ".tiketback" file to the local file system

  Scenario: Restoring a full backup
    Given the user is logged in as "Gerente"
    When the user selects a ".tiketback" file and provides its export password
    Then the system decrypts and validates the bundle
    And fully replaces the local database and settings with the backup's contents
    And no "merge" option is offered — merging two independent sales histories is not meaningful

  Scenario: Exporting a catalog package
    Given the user is logged in as "Gerente"
    When the user exports the current catalog
    Then the exported file contains only "Producto" and "Categoria" records, never "Venta"
    And it is saved as an unencrypted ".tiketdata" file, meant to be shared between installations

  Scenario: Importing a catalog package in replace mode
    Given the user is logged in as "Gerente"
    When the user imports a ".tiketdata" file choosing "Reemplazar"
    Then every local "Producto" and "Categoria" not present in the file is discontinued (soft-delete, never a hard delete)
    And every "Producto" and "Categoria" present in the file is created or updated using the same Last Write Wins mechanism as device sync

  Scenario: Importing a catalog package in merge mode
    Given the user is logged in as "Gerente"
    When the user imports a ".tiketdata" file choosing "Fusionar"
    Then every "Producto" and "Categoria" present in the file is created or updated using the same Last Write Wins mechanism as device sync
    And nothing else in the local catalog is discontinued or modified

  Scenario: Local Area Network Synchronization
    Given devices with role "Gerente" form one logical group and devices with role "Registradora" form another
    When a synchronization event is triggered
    Then devices must discover other devices via local network (e.g., ZeroConf/mDNS)
    And devices in the same role group synchronize directly with each other
    And each role group elects a coordinator device to synchronize with the other group once its own group has no pending intra-group sync
    And exchange SQLite records securely
    And resolve any conflicts using the "updated_at" timestamp (Last Write Wins)
    And propagate deletions as soft-deletes (a "deleted_at" timestamp) so they resolve via the same Last Write Wins mechanism