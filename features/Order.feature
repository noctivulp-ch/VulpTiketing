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

  Scenario: Selling a Producto that has variants
    Given a "Producto" with "Variantes" is added to a "Venta"
    Then the system must ask which variant, highlighting the default one
    And in Venta Rápida the default variant comes preselected, so it sells in one tap
    And the line takes the variant's price as its applied price, still editable
    And the line records the variant's NAME as sold that day, so renaming the variant later never changes past sales ([0039])
    And a "Producto" without variants is added in one tap, exactly as before

  Scenario: Adding a free-form line without a catalog Producto
    Given the user is logged in (Any role)
    And the user is building a "Venta"
    When the user adds a line with a hand-typed name and price instead of selecting a "Producto"
    Then the system must save that line as a "línea libre", not linked to any catalog "Producto"
    And this line must never block a future purge of any "Producto" ([0016])

  Scenario: Choosing how the sale was paid
    Given the user is building a "Venta"
    Then the system must default the payment method to "efectivo" (cash)
    And offer a single "SINPE" checkbox to mark it as a bank transfer instead
    # A checkbox and not a two-option picker: cash is what happens in nine out
    # of ten sales, so asking every time would add a tap per sale for nothing.
    And this checkbox must be available both in Venta Rápida and in the Panel de Venta

  Scenario: Adding the transfer reference after the sale
    Given a "Venta" was saved with payment method "sinpe"
    When the user opens it later from the sales detail in Reportes
    Then the system must allow entering the transfer identifier
    And allow leaving it empty or clearing it afterwards
    # At the counter there is a queue: nobody types a twelve-digit reference
    # with the customer waiting. What cannot be lost is THAT it was a transfer.
    And this must be the only field of a saved venta that can be written after the fact,
        apart from the reversal — it must not change amounts, lines or estado ([0032])

  Scenario: A saved Venta cannot be edited or deleted
    Given a "Venta" has already been saved
    When the user wants to correct it
    Then the system must not allow editing its lines or prices
    And the system must not allow deleting it
    And the only available actions are to revert it, or to annotate its transfer reference

  Scenario: Reverting a Venta
    Given a "Venta" is in "activa" state
    When the user reverts it (e.g., a return or a mistaken sale)
    Then the system must require a motivo (reason) before completing the reversal
    And store the motivo as structured data (type of reason, free-text detail, who, when)
    And change the venta's "estado" to "revertida"
    And keep the venta visible for accounting traceability
    And exclude it from sales totals in reports