Feature: Menu CRUD Operations
  As a restaurant worker
  I want to manage the items available for sale
  So that the catalog is always up to date

  Scenario: Gerente full access
    Given the user is logged in as "Gerente"
    When the user navigates to the Menu Management module
    Then the user can Create, Read, Update, and Delete any "Plato"

  Scenario: Registradora restricted access
    Given the user is logged in as "Registradora"
    When the user navigates to the Menu Management module
    Then the user can only Read and Update existing "Platos"
    And the Create and Delete options must be disabled or hidden