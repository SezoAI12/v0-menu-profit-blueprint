'use client'

import React, { createContext, useContext, useEffect, useState, useCallback } from 'react'
import { createClient } from '@/lib/supabase/client'
import type { User } from '@supabase/supabase-js'
import type { TenantRole, SubscriptionPlan, GraceMode } from '@/lib/types/database'

export interface TenantInfo {
  id: string
  name: string
  name_ar: string | null
  slug: string
  role: TenantRole
  plan: SubscriptionPlan
  graceMode: GraceMode
}

export interface AuthContextType {
  user: User | null
  profile: { full_name: string | null; full_name_ar: string | null; avatar_url: string | null; preferred_language: string } | null
  tenants: TenantInfo[]
  activeTenant: TenantInfo | null
  setActiveTenant: (tenantId: string) => void
  isLoading: boolean
  isAuthenticated: boolean
  signOut: () => Promise<void>
  refreshAuth: () => Promise<void>
}

const AuthContext = createContext<AuthContextType | null>(null)

const ACTIVE_TENANT_COOKIE = 'menuprofit_active_tenant'

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<User | null>(null)
  const [profile, setProfile] = useState<AuthContextType['profile']>(null)
  const [tenants, setTenants] = useState<TenantInfo[]>([])
  const [activeTenantId, setActiveTenantId] = useState<string | null>(null)
  const [isLoading, setIsLoading] = useState(true)

  const supabase = createClient()

  const loadUserData = useCallback(async () => {
    try {
      const { data: { user: authUser }, error: authError } = await supabase.auth.getUser()

      if (authError || !authUser) {
        setUser(null)
        setProfile(null)
        setTenants([])
        setIsLoading(false)
        return
      }

      setUser(authUser)

      // Load profile
      const { data: profileData } = await supabase
        .from('profiles')
        .select('full_name, full_name_ar, avatar_url, preferred_language')
        .eq('id', authUser.id)
        .single()

      setProfile(profileData)

      // Load tenant memberships
      const { data: memberships } = await supabase
        .from('tenant_memberships')
        .select(`
          role,
          is_active,
          tenant:tenants(id, name, name_ar, slug)
        `)
        .eq('user_id', authUser.id)
        .eq('is_active', true)

      if (memberships && memberships.length > 0) {
        const tenantInfos: TenantInfo[] = []

        for (const m of memberships) {
          const tenant = m.tenant as unknown as { id: string; name: string; name_ar: string | null; slug: string }
          if (!tenant) continue

          // Get subscription info
          const { data: subData } = await supabase.rpc('get_subscription_status', {
            p_tenant_id: tenant.id,
          })

          const sub = subData as { mode: GraceMode; plan: SubscriptionPlan } | null

          tenantInfos.push({
            id: tenant.id,
            name: tenant.name,
            name_ar: tenant.name_ar,
            slug: tenant.slug,
            role: m.role as TenantRole,
            plan: sub?.plan ?? 'free',
            graceMode: sub?.mode ?? 'active',
          })
        }

        setTenants(tenantInfos)

        // Restore active tenant from cookie or use first
        const storedId = document.cookie
          .split('; ')
          .find((c) => c.startsWith(`${ACTIVE_TENANT_COOKIE}=`))
          ?.split('=')[1]

        const targetId = storedId && tenantInfos.find((t) => t.id === storedId)
          ? storedId
          : tenantInfos[0].id

        setActiveTenantId(targetId)
      }
    } catch (err) {
      console.error('[MenuProfit] Auth load error:', err)
    } finally {
      setIsLoading(false)
    }
  }, [supabase])

  useEffect(() => {
    loadUserData()

    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
      if (!session) {
        setUser(null)
        setProfile(null)
        setTenants([])
        setActiveTenantId(null)
      }
    })

    return () => subscription.unsubscribe()
  }, [loadUserData, supabase.auth])

  const setActiveTenant = useCallback((tenantId: string) => {
    setActiveTenantId(tenantId)
    document.cookie = `${ACTIVE_TENANT_COOKIE}=${tenantId}; path=/; max-age=${60 * 60 * 24 * 365}`
  }, [])

  const signOut = useCallback(async () => {
    await supabase.auth.signOut()
    setUser(null)
    setProfile(null)
    setTenants([])
    setActiveTenantId(null)
    window.location.href = '/auth/login'
  }, [supabase.auth])

  const activeTenant = tenants.find((t) => t.id === activeTenantId) ?? null

  return (
    <AuthContext.Provider
      value={{
        user,
        profile,
        tenants,
        activeTenant,
        setActiveTenant,
        isLoading,
        isAuthenticated: !!user,
        signOut,
        refreshAuth: loadUserData,
      }}
    >
      {children}
    </AuthContext.Provider>
  )
}

export function useAuth() {
  const context = useContext(AuthContext)
  if (!context) {
    throw new Error('useAuth must be used within an AuthProvider')
  }
  return context
}
