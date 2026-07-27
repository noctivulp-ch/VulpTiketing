Feature: Data Export and Sync
  As a user managing the system
  I want to backup and synchronize data without a cloud server
  So that the business operates offline seamlessly

  Scenario: Exporting data locally
    Given the user is logged in (Any role)
    When the user requests a database backup
    Then the system must bundle the SQLite database and settings
    And encrypt the bundle
    And export it as a custom extension file (e.g., .sodabak) to the local file system

  Scenario: Local Area Network Synchronization
    Given the "Gerente" desktop app and "Registradora" mobile app are on the same Wi-Fi
    When a synchronization event is triggered
    Then the devices must discover each other via local network (e.g., ZeroConf/mDNS)
    And exchange SQLite records securely
    And resolve any conflicts using the "updated_at" timestamp (Last Write Wins)