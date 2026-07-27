Feature: Fast Order Processing
  As a user taking customer orders
  I want a fast POS interface
  So that I can register sales quickly during busy hours

  Scenario: Registering a custom order
    Given the user is logged in (Any role)
    When the user creates a new "Pedido"
    And selects a "Plato" from the menu
    Then the system must load the base price automatically
    And allow the user to override the price manually if needed
    And allow the user to add an optional text note (Detalle)
    And save the transaction locally