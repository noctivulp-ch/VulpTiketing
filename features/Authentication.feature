Feature: Simple Authentication and Roles
  As a system administrator
  I want a hardcoded authentication system
  So that I can prevent unauthorized access without needing a backend

  Background:
    Given the system has two predefined roles: "Gerente" and "Registradora"
    And each device is configured with a role and a local app password
    And the local app password can be changed later from device settings
    And the password is stored using the device's native secure storage, not in the SQLite database

  Scenario: Login routing based on role
    When a user logs in successfully
    Then the app must render the UI conditioned by their role
    And if the role is "Gerente", grant access to full system features
    And if the role is "Registradora", hide administrative settings and render the POS UI