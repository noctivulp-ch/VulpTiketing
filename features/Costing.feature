Feature: Recipe costing
  As the Gerente
  I want to know what each item really costs and what price sustains my margin
  So that I decide prices with numbers, without the app deciding for me

  Scenario: The costing window is for the Gerente only
    Given the user is logged in as "Gerente"
    Then a sixth window "Costeo" is available in the dashboard
    And a "Registradora" does not see it, and her gestures and shortcuts do not change ([0040])

  Scenario: Every catalog item is costed, variants included
    Given products with and without variants
    When the Gerente opens "Costeo"
    Then each product without variants, and each variant, is one costed item
    And items with no recipe, no volume, or an estimated volume show their notices

  Scenario: Costs come from inputs, labour, and shared fixed costs
    Given "Insumos" with purchase price, content per purchase and waste
    And a recipe per lot for an item
    And monthly "Costos fijos" and the business parameters
    Then the item's cost per unit is inputs (with waste) + labour + other direct costs + its share of fixed costs
    And fixed costs are shared per unit or per production minute, never by revenue ([0040])

  Scenario: Volume is real sales
    Given sales in the last 30 days
    Then each item's monthly units are its real sales, per variant
    And a sale without variant of a product that now has variants counts for the default variant
    And only without sales the hand estimate is used, and the item says so

  Scenario: The module informs and never touches the menu on its own
    Given a costed item whose current price differs from the suggested one
    Then the screen shows current price, suggested price and the real margin at the current price
    And no product price changes by opening, editing recipes or changing parameters

  Scenario: Applying a price is explicit and per item
    When the Gerente taps "Aplicar" on one item and confirms
    Then only that item's price changes: the base price, or the variant price (and the base price if it is the default variant)
    And the button is disabled when no price can be computed or the current price already equals the suggested one

  Scenario: Input purchases are ledger entries and set the input cost
    Given an "Insumo" registered once with its unit, waste and a starting price
    When the Gerente notes a purchase (how many packages, content each, total paid)
    Then the entry is written to the current ledger file, next to the sales ([0041])
    And the input cost is the weighted average of its purchases in the last 90 days, else the last purchase, else the starting price — and the screen says which
    And voiding a purchase removes it from the average without deleting it from the ledger
    And the Insumos section shows what was bought this month and this quarter, which is the simplified regime's tax base

  Scenario: Taxes follow the regime, and commissions follow the payment mix
    Given the business regime is set in the costing settings
    When it is "simplificado"
    Then the tax per unit is the input cost × (VAT factor + income factor), and no VAT is applied on sale prices ([0042])
    And the settings show the current quarter's purchases × factors, which is what gets declared
    When it is "general"
    Then each product's VAT rate (or the default one) is inside its price as rate/(1+rate), and enters the suggested price and the real margin
    And the effective payment commission is the cash and SINPE commissions weighted by the last 30 days' real payment mix
