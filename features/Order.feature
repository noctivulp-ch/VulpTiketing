Feature: Fast Sale Registration
  As a user recording sales
  I want a fast interface to register what was sold
  So that accounting stays accurate without slowing down busy hours

  Scenario: Registering a sale with one or more products
    Given the user is logged in (Any role)
    When the user creates a new "Venta"
    And adds one or more "Productos" from the inventory to the venta, each with a quantity
    Then the system must load each product's base price automatically
    And allow the user to override the price manually per product if needed
    And allow the user to add an optional descriptive note per product line (e.g. to justify a manual price override)
    And allow the user to add an optional text note (Detalle) to the venta as a whole
    And save the venta locally with its date and time, with "estado" set to "activa"

  Scenario: Adding a free-form line without a catalog Producto
    Given the user is logged in (Any role)
    And the user is building a "Venta"
    When the user adds a line with a hand-typed name and price instead of selecting a "Producto"
    Then the system must save that line as a "línea libre", not linked to any catalog "Producto"
    And this line must never block a future purge of any "Producto" ([0016])

  Scenario: A saved Venta cannot be edited or deleted
    Given a "Venta" has already been saved
    When the user wants to correct it
    Then the system must not allow editing its lines or prices
    And the system must not allow deleting it
    And the only available action is to revert it

  Scenario: Reverting a Venta
    Given a "Venta" is in "activa" state
    When the user reverts it (e.g., a return or a mistaken sale)
    Then the system must require a motivo (reason) before completing the reversal
    And store the motivo as structured data (type of reason, free-text detail, who, when)
    And change the venta's "estado" to "revertida"
    And keep the venta visible for accounting traceability
    And exclude it from sales totals in reports