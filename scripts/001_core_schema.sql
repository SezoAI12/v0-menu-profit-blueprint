-- ============================================================
-- MenuProfit Core Schema - Migration 001
-- Multi-tenant SaaS: profiles, tenants, memberships, subscriptions
-- ORDERING: All tables first, then all RLS policies
-- ============================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- ENUM TYPES
-- ============================================================
DO $$ BEGIN
  CREATE TYPE public.tenant_role AS ENUM ('owner', 'manager', 'staff');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE public.subscription_plan AS ENUM ('free', 'pro', 'elite');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE public.subscription_status AS ENUM ('active', 'past_due', 'canceled', 'trialing');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ============================================================
-- TABLES (created first, no RLS policies yet)
-- ============================================================

-- 1. PROFILES (linked to auth.users)
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT,
  avatar_url TEXT,
  locale TEXT NOT NULL DEFAULT 'ar' CHECK (locale IN ('ar', 'en')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. TENANTS (restaurants)
CREATE TABLE IF NOT EXISTS public.tenants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  name_ar TEXT,
  currency TEXT NOT NULL DEFAULT 'SAR',
  timezone TEXT NOT NULL DEFAULT 'Asia/Riyadh',
  locale TEXT NOT NULL DEFAULT 'ar' CHECK (locale IN ('ar', 'en')),
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_by UUID NOT NULL REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3. TENANT MEMBERSHIPS (user <-> tenant, with role)
CREATE TABLE IF NOT EXISTS public.tenant_memberships (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role public.tenant_role NOT NULL DEFAULT 'staff',
  is_active BOOLEAN NOT NULL DEFAULT true,
  invited_by UUID REFERENCES auth.users(id),
  invited_at TIMESTAMPTZ,
  joined_at TIMESTAMPTZ DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, user_id)
);

-- 4. TENANT SUBSCRIPTIONS
CREATE TABLE IF NOT EXISTS public.tenant_subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE UNIQUE,
  plan public.subscription_plan NOT NULL DEFAULT 'free',
  status public.subscription_status NOT NULL DEFAULT 'active',
  max_recipes INTEGER NOT NULL DEFAULT 15,
  max_ingredients INTEGER NOT NULL DEFAULT 50,
  max_users INTEGER NOT NULL DEFAULT 1,
  features JSONB NOT NULL DEFAULT '{"ai_suggestions": false, "competition_tracking": false, "risk_radar": false, "bulk_import": false, "advanced_reports": false}'::jsonb,
  period_start TIMESTAMPTZ,
  period_end TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- ENABLE RLS ON ALL TABLES
-- ============================================================
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tenant_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tenant_subscriptions ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- RLS POLICIES - PROFILES
-- ============================================================
CREATE POLICY "profiles_select_own" ON public.profiles
  FOR SELECT USING (auth.uid() = id);
CREATE POLICY "profiles_insert_own" ON public.profiles
  FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "profiles_update_own" ON public.profiles
  FOR UPDATE USING (auth.uid() = id);

-- ============================================================
-- RLS POLICIES - TENANT MEMBERSHIPS (before tenants, since tenants policies reference memberships)
-- ============================================================

-- Users can see their own memberships
CREATE POLICY "memberships_select_own" ON public.tenant_memberships
  FOR SELECT USING (user_id = auth.uid());

-- Owners can see all memberships for their tenants
CREATE POLICY "memberships_select_owner" ON public.tenant_memberships
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.tenant_memberships tm2
      WHERE tm2.tenant_id = tenant_memberships.tenant_id
        AND tm2.user_id = auth.uid()
        AND tm2.role = 'owner'
        AND tm2.is_active = true
    )
  );

-- Owners can insert memberships (invite), or self-insert when creating a new tenant
CREATE POLICY "memberships_insert_owner" ON public.tenant_memberships
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.tenant_memberships tm2
      WHERE tm2.tenant_id = tenant_memberships.tenant_id
        AND tm2.user_id = auth.uid()
        AND tm2.role = 'owner'
        AND tm2.is_active = true
    )
    OR
    (user_id = auth.uid() AND role = 'owner')
  );

-- Only owners can update memberships
CREATE POLICY "memberships_update_owner" ON public.tenant_memberships
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.tenant_memberships tm2
      WHERE tm2.tenant_id = tenant_memberships.tenant_id
        AND tm2.user_id = auth.uid()
        AND tm2.role = 'owner'
        AND tm2.is_active = true
    )
  );

-- Only owners can delete memberships
CREATE POLICY "memberships_delete_owner" ON public.tenant_memberships
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.tenant_memberships tm2
      WHERE tm2.tenant_id = tenant_memberships.tenant_id
        AND tm2.user_id = auth.uid()
        AND tm2.role = 'owner'
        AND tm2.is_active = true
    )
  );

-- ============================================================
-- RLS POLICIES - TENANTS (now memberships table exists)
-- ============================================================
CREATE POLICY "tenants_select_member" ON public.tenants
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.tenant_memberships tm
      WHERE tm.tenant_id = tenants.id
        AND tm.user_id = auth.uid()
        AND tm.is_active = true
    )
  );

CREATE POLICY "tenants_insert" ON public.tenants
  FOR INSERT WITH CHECK (auth.uid() = created_by);

CREATE POLICY "tenants_update_owner" ON public.tenants
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.tenant_memberships tm
      WHERE tm.tenant_id = tenants.id
        AND tm.user_id = auth.uid()
        AND tm.role = 'owner'
        AND tm.is_active = true
    )
  );

-- ============================================================
-- RLS POLICIES - TENANT SUBSCRIPTIONS
-- ============================================================
CREATE POLICY "subscriptions_select_member" ON public.tenant_subscriptions
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.tenant_memberships tm
      WHERE tm.tenant_id = tenant_subscriptions.tenant_id
        AND tm.user_id = auth.uid()
        AND tm.is_active = true
    )
  );

CREATE POLICY "subscriptions_update_owner" ON public.tenant_subscriptions
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.tenant_memberships tm
      WHERE tm.tenant_id = tenant_subscriptions.tenant_id
        AND tm.user_id = auth.uid()
        AND tm.role = 'owner'
        AND tm.is_active = true
    )
  );

-- ============================================================
-- HELPER FUNCTIONS (SECURITY DEFINER - bypass RLS for checks)
-- ============================================================
CREATE OR REPLACE FUNCTION public.is_tenant_member(p_tenant_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.tenant_memberships
    WHERE tenant_id = p_tenant_id
      AND user_id = auth.uid()
      AND is_active = true
  );
$$;

CREATE OR REPLACE FUNCTION public.get_tenant_role(p_tenant_id UUID)
RETURNS public.tenant_role
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT role FROM public.tenant_memberships
  WHERE tenant_id = p_tenant_id
    AND user_id = auth.uid()
    AND is_active = true
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.is_tenant_owner(p_tenant_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.tenant_memberships
    WHERE tenant_id = p_tenant_id
      AND user_id = auth.uid()
      AND role = 'owner'
      AND is_active = true
  );
$$;

CREATE OR REPLACE FUNCTION public.is_tenant_manager_or_above(p_tenant_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.tenant_memberships
    WHERE tenant_id = p_tenant_id
      AND user_id = auth.uid()
      AND role IN ('owner', 'manager')
      AND is_active = true
  );
$$;

-- ============================================================
-- TRIGGER: Auto-create profile on signup
-- ============================================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data ->> 'full_name', '')
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- ============================================================
-- TRIGGER: Auto-create free subscription when tenant is created
-- ============================================================
CREATE OR REPLACE FUNCTION public.handle_new_tenant()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.tenant_subscriptions (tenant_id, plan, status, max_recipes, max_ingredients, max_users)
  VALUES (NEW.id, 'free', 'active', 15, 50, 1)
  ON CONFLICT (tenant_id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_tenant_created ON public.tenants;
CREATE TRIGGER on_tenant_created
  AFTER INSERT ON public.tenants
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_tenant();

-- ============================================================
-- TRIGGER: updated_at auto-refresh
-- ============================================================
CREATE OR REPLACE FUNCTION public.update_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER profiles_updated_at BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
CREATE TRIGGER tenants_updated_at BEFORE UPDATE ON public.tenants
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
CREATE TRIGGER memberships_updated_at BEFORE UPDATE ON public.tenant_memberships
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
CREATE TRIGGER subscriptions_updated_at BEFORE UPDATE ON public.tenant_subscriptions
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
