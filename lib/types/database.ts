/**
 * MenuProfit Database Types
 * Mirrors the Supabase schema for type-safe TypeScript usage.
 */

// ============================================================
// ENUMS
// ============================================================
export type TenantRole = 'owner' | 'manager' | 'staff'
export type SubscriptionPlan = 'free' | 'pro' | 'elite'
export type SubscriptionStatus = 'active' | 'past_due' | 'canceled' | 'trialing'
export type IngredientUnit = 'kg' | 'g' | 'lb' | 'oz' | 'l' | 'ml' | 'piece' | 'bunch' | 'can' | 'box' | 'bag' | 'other'
export type RecipeStatus = 'draft' | 'active' | 'archived'
export type ImportJobStatus = 'pending' | 'processing' | 'completed' | 'failed'
export type ActionStatus = 'pending' | 'in_progress' | 'done' | 'dismissed'
export type ActionPriority = 'low' | 'medium' | 'high' | 'critical'

// ============================================================
// CORE ENTITIES
// ============================================================
export interface Profile {
  id: string // matches auth.users.id
  full_name: string | null
  full_name_ar: string | null
  avatar_url: string | null
  preferred_language: string
  created_at: string
  updated_at: string
}

export interface Tenant {
  id: string
  name: string
  name_ar: string | null
  slug: string
  logo_url: string | null
  currency: string
  timezone: string
  is_active: boolean
  created_by: string
  created_at: string
  updated_at: string
}

export interface TenantMembership {
  id: string
  tenant_id: string
  user_id: string
  role: TenantRole
  is_active: boolean
  invited_by: string | null
  created_at: string
  updated_at: string
}

export interface TenantSubscription {
  id: string
  tenant_id: string
  plan: SubscriptionPlan
  status: SubscriptionStatus
  current_period_start: string | null
  current_period_end: string | null
  stripe_subscription_id: string | null
  stripe_customer_id: string | null
  created_at: string
  updated_at: string
}

// ============================================================
// BUSINESS ENTITIES
// ============================================================
export interface Supplier {
  id: string
  tenant_id: string
  name: string
  name_ar: string | null
  contact_name: string | null
  phone: string | null
  email: string | null
  notes: string | null
  is_active: boolean
  created_by: string
  created_at: string
  updated_at: string
}

export interface Ingredient {
  id: string
  tenant_id: string
  name: string
  name_ar: string | null
  unit: IngredientUnit
  current_price: number
  yield_percent: number
  waste_percent: number
  alert_threshold: number | null
  alert_threshold_price: number | null
  supplier_id: string | null
  is_active: boolean
  created_by: string
  created_at: string
  updated_at: string
  // Computed (not stored)
  effective_cost?: number
}

export interface IngredientPriceHistory {
  id: string
  tenant_id: string
  ingredient_id: string
  price: number
  effective_date: string
  notes: string | null
  created_by: string
  created_at: string
}

export interface OverheadMonthly {
  id: string
  tenant_id: string
  year: number
  month: number
  rent: number
  salaries: number
  utilities: number
  marketing: number
  other_costs: number
  total_overhead: number
  baseline_plates: number
  overhead_per_plate: number
  notes: string | null
  created_by: string
  created_at: string
  updated_at: string
}

export interface RecipeCategory {
  id: string
  tenant_id: string
  name: string
  name_ar: string | null
  sort_order: number
  created_by: string
  created_at: string
}

export interface Recipe {
  id: string
  tenant_id: string
  name: string
  name_ar: string | null
  category_id: string | null
  selling_price: number
  target_margin: number | null
  status: RecipeStatus
  is_protected: boolean
  description: string | null
  description_ar: string | null
  image_url: string | null
  version: number
  created_by: string
  created_at: string
  updated_at: string
  // Computed (not stored)
  food_cost?: number
  true_cost?: number
  margin_percent?: number
  contribution_margin?: number
}

export interface RecipeItem {
  id: string
  tenant_id: string
  recipe_id: string
  ingredient_id: string
  quantity: number
  unit: IngredientUnit
  unit_conversion_factor: number
  notes: string | null
  created_at: string
  updated_at: string
}

export interface ImportJob {
  id: string
  tenant_id: string
  file_name: string
  file_url: string | null
  entity_type: string
  status: ImportJobStatus
  total_rows: number
  success_count: number
  error_count: number
  error_details: Record<string, unknown> | null
  created_by: string
  created_at: string
  updated_at: string
}

export interface SalesData {
  id: string
  tenant_id: string
  recipe_id: string
  sale_date: string
  quantity_sold: number
  // STRICTLY NO price/revenue columns - volume only per SRS
  import_job_id: string | null
  created_by: string
  created_at: string
}

export interface Competitor {
  id: string
  tenant_id: string
  name: string
  name_ar: string | null
  location: string | null
  notes: string | null
  is_active: boolean
  created_by: string
  created_at: string
  updated_at: string
}

export interface CompetitorPrice {
  id: string
  tenant_id: string
  competitor_id: string
  recipe_id: string | null
  dish_name: string
  price: number
  observed_date: string
  notes: string | null
  created_by: string
  created_at: string
}

export interface ActionItem {
  id: string
  tenant_id: string
  title: string
  title_ar: string | null
  description: string | null
  description_ar: string | null
  priority: ActionPriority
  status: ActionStatus
  source: string | null
  related_recipe_id: string | null
  related_ingredient_id: string | null
  assigned_to: string | null
  due_date: string | null
  completed_at: string | null
  created_by: string
  created_at: string
  updated_at: string
}

export interface AuditLog {
  id: string
  tenant_id: string
  table_name: string
  record_id: string
  action: 'create' | 'update' | 'delete'
  before_data: Record<string, unknown> | null
  after_data: Record<string, unknown> | null
  user_id: string | null
  created_at: string
}

// ============================================================
// CALCULATED TYPES
// ============================================================
export interface RecipeAnalysis {
  recipe_id: string
  food_cost: number
  overhead_per_plate: number
  true_cost: number
  selling_price: number
  margin_percent: number | null
  contribution_margin: number
  target_margin: number | null
  margin_gap: number | null
}

export interface PlanLimitCheck {
  allowed: boolean
  plan: SubscriptionPlan
  resource: string
  current_count: number
  limit: number
  remaining: number
  error?: string
}

// ============================================================
// PLAN LIMITS REFERENCE TABLE
// ============================================================
export const PLAN_LIMITS = {
  free: {
    recipes: 20,
    ingredients: 30,
    suppliers: 10,
    users: 1,
    tenants: 1,
    ai_requests_per_month: 10,
    bulk_import: false,
    ai_suggestions: false,
    competition_tracking: false,
    advanced_reports: false,
    risk_radar: false,
  },
  pro: {
    recipes: 150,
    ingredients: 300,
    suppliers: 50,
    users: 5,
    tenants: 3,
    ai_requests_per_month: 100,
    bulk_import: true,
    ai_suggestions: true,
    competition_tracking: true,
    advanced_reports: false,
    risk_radar: true,
  },
  elite: {
    recipes: 999999,
    ingredients: 999999,
    suppliers: 999999,
    users: 20,
    tenants: 10,
    ai_requests_per_month: 999999,
    bulk_import: true,
    ai_suggestions: true,
    competition_tracking: true,
    advanced_reports: true,
    risk_radar: true,
  },
} as const

// Grace period constants
export const GRACE_PERIOD_DAYS = 7
export type GraceMode = 'active' | 'grace' | 'locked'
