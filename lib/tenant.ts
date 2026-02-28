/**
 * MenuProfit Tenant Context & Guards
 *
 * Provides server-side utilities for:
 * - Resolving the current tenant from session/headers
 * - Verifying tenant membership and roles
 * - Enforcing plan limits before mutations
 */

import { createClient } from '@/lib/supabase/server'
import type { TenantRole, SubscriptionPlan, PlanLimitCheck } from '@/lib/types/database'

export interface TenantContext {
  tenantId: string
  userId: string
  role: TenantRole
  plan: SubscriptionPlan
}

/**
 * Resolves the current tenant context from auth session + tenant header/cookie.
 * Throws if user is not authenticated or not a member of the requested tenant.
 */
export async function getTenantContext(tenantId: string): Promise<TenantContext> {
  const supabase = await createClient()

  // 1. Verify authenticated user
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser()

  if (authError || !user) {
    throw new Error('UNAUTHORIZED: User not authenticated')
  }

  // 2. Verify tenant membership
  const { data: membership, error: memberError } = await supabase
    .from('tenant_memberships')
    .select('role, is_active')
    .eq('tenant_id', tenantId)
    .eq('user_id', user.id)
    .single()

  if (memberError || !membership) {
    throw new Error('FORBIDDEN: User is not a member of this tenant')
  }

  if (!membership.is_active) {
    throw new Error('FORBIDDEN: Tenant membership is inactive')
  }

  // 3. Get subscription plan
  const { data: subscription } = await supabase
    .from('tenant_subscriptions')
    .select('plan, status')
    .eq('tenant_id', tenantId)
    .eq('status', 'active')
    .single()

  const plan: SubscriptionPlan = subscription?.plan ?? 'free'

  return {
    tenantId,
    userId: user.id,
    role: membership.role as TenantRole,
    plan,
  }
}

/**
 * Asserts that the current user has at least the required role.
 * Role hierarchy: owner > manager > staff
 */
export function assertRole(ctx: TenantContext, requiredRole: TenantRole): void {
  const hierarchy: Record<TenantRole, number> = {
    staff: 0,
    manager: 1,
    owner: 2,
  }

  if (hierarchy[ctx.role] < hierarchy[requiredRole]) {
    throw new Error(
      `FORBIDDEN: Requires role '${requiredRole}', but user has '${ctx.role}'`
    )
  }
}

/**
 * Server-side plan limit check. Calls the Supabase RPC function.
 * Returns the check result; throws on unexpected errors.
 */
export async function checkPlanLimit(
  tenantId: string,
  resourceType: string
): Promise<PlanLimitCheck> {
  const supabase = await createClient()

  const { data, error } = await supabase.rpc('check_plan_limit', {
    p_tenant_id: tenantId,
    p_resource_type: resourceType,
  })

  if (error) {
    console.error('[MenuProfit] Plan limit check failed:', error)
    throw new Error(`Plan limit check failed: ${error.message}`)
  }

  return data as PlanLimitCheck
}

/**
 * Asserts that the tenant can create a new resource (under plan limit).
 * Throws with a descriptive error if limit reached.
 */
export async function assertPlanLimit(
  tenantId: string,
  resourceType: string
): Promise<void> {
  const check = await checkPlanLimit(tenantId, resourceType)

  if (!check.allowed) {
    throw new Error(
      `PLAN_LIMIT_REACHED: ${resourceType} limit (${check.limit}) reached on ${check.plan} plan. ` +
        `Current: ${check.current_count}. Upgrade to add more.`
    )
  }
}

/**
 * Feature gating check - verifies a feature is available on the current plan.
 */
export function assertFeatureAccess(
  plan: SubscriptionPlan,
  feature: string
): void {
  const featureMinPlan: Record<string, SubscriptionPlan> = {
    bulk_import: 'pro',
    ai_suggestions: 'pro',
    competition_tracking: 'pro',
    risk_radar: 'pro',
    advanced_reports: 'elite',
    custom_branding: 'elite',
    api_access: 'elite',
    multi_location: 'elite',
  }

  const minPlan = featureMinPlan[feature]
  if (!minPlan) return // Feature not gated

  const planLevel: Record<SubscriptionPlan, number> = {
    free: 0,
    pro: 1,
    elite: 2,
  }

  if (planLevel[plan] < planLevel[minPlan]) {
    throw new Error(
      `FEATURE_LOCKED: '${feature}' requires ${minPlan} plan or higher. Current: ${plan}`
    )
  }
}
