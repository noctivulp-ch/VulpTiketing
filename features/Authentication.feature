Feature: Simple Authentication and Roles
  As a system administrator
  I want a hardcoded authentication system
  So that I can prevent unauthorized access without needing a backend

  Background:
    Given the system has two predefined roles: "Gerente" and "Registradora"
    And user credentials are hardcoded at compile time

  Scenario: Login routing based on role
    When a user logs in successfully
    Then the app must render the UI conditioned by their role
    And if the role is "Gerente", grant access to full system features
    And if the role is "Registradora", hide administrative settings and render the POS UI