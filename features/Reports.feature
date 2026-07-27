Feature: Financial Reports
  As a business owner or cashier
  I want to view sales summaries based on time periods
  So that I can track revenue accurately

  Background:
    Given the day is divided into three fixed shifts for reporting purposes
    And "Morning" covers 00:00 to 11:59
    And "Afternoon" covers 12:00 to 17:59
    And "Night" covers 18:00 to 23:59
    And there is no strict cash-register open/close event — shifts are only a time grouping for accounting

  Scenario: Gerente reporting capabilities
    Given the user is logged in as "Gerente"
    When the user accesses the Reports module
    Then the user can query sales by Morning/Afternoon/Night for any specific day
    And the user can generate Weekly, Monthly, and Annual reports
    And the reports must show total amounts and sort items by most/least sold

  Scenario: Registradora reporting capabilities
    Given the user is logged in as "Registradora"
    When the user accesses the Reports module
    Then the user can only view the Current Week report
    And the Current Day report
    And the Morning/Afternoon/Night breakdown for the current day