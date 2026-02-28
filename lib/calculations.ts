/**
 * MenuProfit Core Calculation Functions (TypeScript)
 *
 * These mirror the SQL functions in 004_calculation_functions.sql
 * for client-side previews and validation. The SQL functions are
 * the source of truth for all persisted data.
 *
 * Formulas per SRS v2.0:
 *   Effective Cost = purchase_price / (yield_percent / 100)
 *   Food Cost = SUM(effective_cost * quantity_in_base_units)
 *   True Cost = Food Cost + Overhead Per Plate
 *   Margin % = (Selling Price - True Cost) / Selling Price * 100
 *   Contribution Margin = Selling Price - True Cost
 */

// ============================================================
// 1. EFFECTIVE INGREDIENT COST
// ============================================================
/**
 * Calculate the effective cost of an ingredient after yield/waste adjustment.
 *
 * @param purchasePrice - The purchase price per unit
 * @param yieldPercent - The yield percentage (e.g., 80 means 80%)
 * @returns The effective cost per usable unit
 *
 * Example: Chicken breast at 40 SAR/kg with 80% yield
 *   = 40 / (80/100) = 40 / 0.8 = 50 SAR/kg effective cost
 */
export function calcEffectiveIngredientCost(
  purchasePrice: number,
  yieldPercent: number | null | undefined
): number {
  if (!yieldPercent || yieldPercent <= 0) {
    return purchasePrice
  }
  return round(purchasePrice / (yieldPercent / 100), 4)
}

// ============================================================
// 2. RECIPE FOOD COST
// ============================================================
export interface RecipeItemForCalc {
  ingredientPrice: number
  ingredientYieldPercent: number
  quantity: number
  unitConversionFactor: number
}

/**
 * Calculate the total food cost for a recipe.
 *
 * @param items - Array of recipe items with ingredient data
 * @returns Total food cost for the recipe
 *
 * Each item cost = effective_cost * (quantity / unit_conversion_factor)
 * Food cost = SUM of all item costs
 */
export function calcRecipeFoodCost(items: RecipeItemForCalc[]): number {
  if (!items || items.length === 0) return 0

  const total = items.reduce((sum, item) => {
    const effectiveCost = calcEffectiveIngredientCost(
      item.ingredientPrice,
      item.ingredientYieldPercent
    )
    const quantityInBaseUnits = item.quantity / item.unitConversionFactor
    return sum + effectiveCost * quantityInBaseUnits
  }, 0)

  return round(total, 4)
}

// ============================================================
// 3. TRUE COST
// ============================================================
/**
 * Calculate the true cost of a dish.
 * True Cost = Food Cost + Overhead Per Plate
 *
 * @param foodCost - Total food cost of the recipe
 * @param overheadPerPlate - Overhead cost allocated per plate
 * @returns The true cost per dish
 */
export function calcTrueCost(
  foodCost: number,
  overheadPerPlate: number | null | undefined
): number {
  return round(foodCost + (overheadPerPlate ?? 0), 4)
}

// ============================================================
// 4. MARGIN PERCENT
// ============================================================
/**
 * Calculate the profit margin percentage.
 * Margin % = (Selling Price - True Cost) / Selling Price * 100
 *
 * @param sellingPrice - The menu selling price
 * @param trueCost - The true cost (food + overhead)
 * @returns Margin percentage, or null if selling price is zero
 */
export function calcMarginPercent(
  sellingPrice: number,
  trueCost: number
): number | null {
  if (!sellingPrice || sellingPrice === 0) return null
  return round(((sellingPrice - trueCost) / sellingPrice) * 100, 2)
}

// ============================================================
// 5. CONTRIBUTION MARGIN
// ============================================================
/**
 * Calculate the contribution margin per dish.
 * Contribution Margin = Selling Price - True Cost
 *
 * @param sellingPrice - The menu selling price
 * @param trueCost - The true cost (food + overhead)
 * @returns Contribution margin per dish
 */
export function calcContributionMargin(
  sellingPrice: number,
  trueCost: number
): number {
  return round(sellingPrice - trueCost, 2)
}

// ============================================================
// 6. OVERHEAD PER PLATE
// ============================================================
/**
 * Calculate overhead per plate from monthly overhead data.
 * Overhead Per Plate = Total Overhead / Baseline Plates
 *
 * @param totalOverhead - Total monthly overhead costs
 * @param baselinePlates - Number of plates served in the month
 * @returns Overhead cost per plate
 */
export function calcOverheadPerPlate(
  totalOverhead: number,
  baselinePlates: number
): number {
  if (!baselinePlates || baselinePlates <= 0) return 0
  return round(totalOverhead / baselinePlates, 4)
}

/**
 * Calculate total overhead from individual components.
 *
 * @param rent - Monthly rent
 * @param salaries - Monthly salaries
 * @param utilities - Monthly utilities
 * @param marketing - Monthly marketing costs
 * @param otherCosts - Other monthly costs
 * @returns Total monthly overhead
 */
export function calcTotalOverhead(
  rent: number,
  salaries: number,
  utilities: number,
  marketing: number,
  otherCosts: number
): number {
  return round(rent + salaries + utilities + marketing + otherCosts, 2)
}

// ============================================================
// 7. FULL RECIPE ANALYSIS
// ============================================================
export interface RecipeAnalysisInput {
  sellingPrice: number
  targetMargin: number | null
  items: RecipeItemForCalc[]
  overheadPerPlate: number
}

export interface RecipeAnalysisResult {
  foodCost: number
  overheadPerPlate: number
  trueCost: number
  sellingPrice: number
  marginPercent: number | null
  contributionMargin: number
  targetMargin: number | null
  marginGap: number | null
}

/**
 * Perform a full recipe analysis, returning all cost/margin metrics.
 */
export function analyzeRecipe(input: RecipeAnalysisInput): RecipeAnalysisResult {
  const foodCost = calcRecipeFoodCost(input.items)
  const trueCost = calcTrueCost(foodCost, input.overheadPerPlate)
  const marginPercent = calcMarginPercent(input.sellingPrice, trueCost)
  const contributionMargin = calcContributionMargin(input.sellingPrice, trueCost)
  const marginGap =
    input.targetMargin !== null && marginPercent !== null
      ? round(marginPercent - input.targetMargin, 2)
      : null

  return {
    foodCost,
    overheadPerPlate: input.overheadPerPlate,
    trueCost,
    sellingPrice: input.sellingPrice,
    marginPercent,
    contributionMargin,
    targetMargin: input.targetMargin,
    marginGap,
  }
}

// ============================================================
// 8. SUGGESTED SELLING PRICE (reverse calculation)
// ============================================================
/**
 * Calculate the suggested selling price to achieve a target margin.
 * Rearranging: Margin% = (SP - TC) / SP * 100
 *   SP * Margin% / 100 = SP - TC
 *   SP - SP * Margin% / 100 = TC
 *   SP * (1 - Margin% / 100) = TC
 *   SP = TC / (1 - Margin% / 100)
 *
 * @param trueCost - The true cost
 * @param targetMarginPercent - Desired margin percentage
 * @returns Suggested selling price
 */
export function calcSuggestedSellingPrice(
  trueCost: number,
  targetMarginPercent: number
): number | null {
  if (targetMarginPercent >= 100 || targetMarginPercent < 0) return null
  return round(trueCost / (1 - targetMarginPercent / 100), 2)
}

// ============================================================
// UTILITY
// ============================================================
function round(value: number, decimals: number): number {
  const factor = Math.pow(10, decimals)
  return Math.round(value * factor) / factor
}
