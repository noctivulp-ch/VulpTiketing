Feature: Data Export and Sync
  As a user managing the system
  I want to backup and synchronize data without a cloud server
  So that the business operates offline seamlessly

  Scenario: Exporting data locally
    Given the user is logged in (Any role)
    When the user requests a database backup
    And provides an export password (separate from their login password)
    Then the system must bundle the SQLite database and settings
    And derive an encryption key from the export password (e.g., Argon2id)
    And encrypt the bundle with the derived key (e.g., AES-256-GCM)
    And export it as a custom extension file (e.g., .sodabak) to the local file system

  Scenario: Local Area Network Synchronization
    Given devices with role "Gerente" form one logical group and devices with role "Registradora" form another
    When a synchronization event is triggered
    Then devices must discover other devices via local network (e.g., ZeroConf/mDNS)
    And devices in the same role group synchronize directly with each other
    And each role group elects a coordinator device to synchronize with the other group once its own group has no pending intra-group sync
    And exchange SQLite records securely
    And resolve any conflicts using the "updated_at" timestamp (Last Write Wins)
    And propagate deletions as soft-deletes (a "deleted_at" timestamp) so they resolve via the same Last Write Wins mechanism