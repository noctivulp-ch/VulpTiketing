Feature: Inventory CRUD Operations
  As a soda worker
  I want to manage the products available for sale
  So that the catalog is always up to date

  Background:
    Given a "Producto" has a name, an optional image, and a base price

  Scenario: Gerente full access
    Given the user is logged in as "Gerente"
    When the user navigates to the Inventory Management module
    Then the user can Create, Read, Update, and Discontinue any "Producto"

  Scenario: Registradora restricted access
    Given the user is logged in as "Registradora"
    When the user navigates to the Inventory Management module
    Then the user can only Read and Update existing "Productos"
    And the Create and Discontinue options must be disabled or hidden

  Scenario: Discontinuing a Producto is a soft-delete
    Given the user is logged in as "Gerente"
    When the user discontinues a "Producto"
    Then the system must mark it with a "deleted_at" timestamp instead of removing the row
    And the "Producto" must no longer appear in the catalog or in new sales