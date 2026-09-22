Feature: Inventory CRUD Operations
  As a soda worker
  I want to manage the products available for sale
  So that the catalog is always up to date

  Background:
    Given a "Producto" has a name, an optional image, an optional category, and a base price
    And "Producto" listings can be ordered "Alfabético", "Precio", or "Categoría" (grouped), configurable in Configuración

  Scenario: Searching products ranks name matches before category matches
    Given the user types a search term in a product search bar
    When the term matches one or more "Producto" names, tolerating typos
    And the term also matches a "Categoria" name, tolerating typos
    Then products with a direct name match are shown first
    And products belonging to the matched "Categoria" are shown after, excluding any already shown above

  Scenario: Gerente full access
    Given the user is logged in as "Gerente"
    When the user navigates to the Inventory Management module
    Then the user can Create, Read, Update, and Discontinue any "Producto"

  Scenario: Registradora restricted access
    Given the user is logged in as "Registradora"
    When the user navigates to the Inventory Management module
    Then the user can only Read and Update existing "Productos"
    And the Create and Discontinue options must be disabled or hidden

  Scenario: A Producto can be sold in variants at different prices
    Given the user is logged in as "Gerente" or "Registradora"
    When the user edits a "Producto" and adds one or more "Variantes", each with a name and a price
    Then its variants are stored inside its own record, not as separate "Productos" ([0039])
    And exactly one variant is the default; the "Producto" base price is that variant's price, and the base-price field becomes the default selector
    And no two variants of the same "Producto" may share a name
    And the sale screens show the default variant's price
    # Sizes, cuts, with or without sides, flavours: one mechanism. Before this
    # the menu had "Pollo frito (cadera y muslo)" and "Pollo frito (pechuga y
    # ala)" as two Productos, and the ranking split one dish in two rows.

  Scenario: Discontinuing a Producto is a soft-delete
    Given the user is logged in as "Gerente"
    When the user discontinues a "Producto"
    Then the system must mark it with a "deleted_at" timestamp instead of removing the row
    And the "Producto" must no longer appear in the catalog or in new sales

  Scenario: Purging a Producto is a real physical delete, but only when safe
    Given the user is logged in as "Gerente"
    And the "Producto" is already discontinued
    And no "LineaVenta" references this "Producto"
    And all known devices are confirmed synchronized
    When the user purges the "Producto"
    Then the system permanently removes the row from the database

  Scenario: Purging is blocked when it is not safe
    Given the user is logged in as "Gerente"
    When the "Producto" has at least one "LineaVenta" referencing it, or is not discontinued, or not all known devices are confirmed synchronized
    Then the purge action must be disabled, with a message explaining why