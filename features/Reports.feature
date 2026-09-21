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
    And a "Producto" sold in variants ranks per variant, named "Producto · Variante" ([0039])

  Scenario: Registradora reporting capabilities
    Given the user is logged in as "Registradora"
    When the user accesses the Reports module
    Then the user can only view the Current Week report
    And the Current Day report
    And the Morning/Afternoon/Night breakdown for the current day

  Scenario: Seeing how much came in by bank transfer
    Given sales exist in the selected period, some paid by "sinpe"
    Then the report must show how much of the total came in by SINPE
    And show nothing about payment methods when every sale was cash
    # "SINPE ₡0" on an all-cash day is a line that says nothing and takes room
    # from the number people come to see.
    And exported files must carry the payment method and the transfer reference
        per line, which is what gets checked against the bank statement ([0032])
