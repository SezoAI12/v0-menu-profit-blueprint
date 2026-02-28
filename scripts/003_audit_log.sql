-- ============================================================
-- MenuProfit Audit Log - Migration 003
-- Immutable audit trail for all tenant-scoped CRUD operations
-- ============================================================

-- ============================================================
-- 1. AUDIT LOGS TABLE (immutable - INSERT only)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  table_name TEXT NOT NULL,
  record_id UUID NOT NULL,
  action TEXT NOT NULL CHECK (action IN ('create', 'update', 'delete')),
  before_data JSONB,
  after_data JSONB,
  user_id UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_audit_logs_tenant ON public.audit_logs(tenant_id, created_at DESC);
CREATE INDEX idx_audit_logs_table ON public.audit_logs(tenant_id, table_name, created_at DESC);
CREATE INDEX idx_audit_logs_record ON public.audit_logs(record_id);

ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

-- Only owners can view audit logs
CREATE POLICY "audit_logs_select_owner" ON public.audit_logs
  FOR SELECT USING (public.is_tenant_owner(tenant_id));

-- Insert allowed via trigger (SECURITY DEFINER)
CREATE POLICY "audit_logs_insert" ON public.audit_logs
  FOR INSERT WITH CHECK (true);

-- Prevent UPDATE and DELETE on audit_logs
CREATE OR REPLACE FUNCTION public.prevent_audit_log_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'audit_logs is immutable. UPDATE and DELETE are forbidden.';
  RETURN NULL;
END;
$$;

CREATE TRIGGER enforce_audit_log_immutable_update
  BEFORE UPDATE ON public.audit_logs
  FOR EACH ROW
  EXECUTE FUNCTION public.prevent_audit_log_mutation();

CREATE TRIGGER enforce_audit_log_immutable_delete
  BEFORE DELETE ON public.audit_logs
  FOR EACH ROW
  EXECUTE FUNCTION public.prevent_audit_log_mutation();

-- ============================================================
-- 2. GENERIC AUDIT TRIGGER FUNCTION
-- ============================================================
CREATE OR REPLACE FUNCTION public.audit_trigger_func()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id UUID;
  v_record_id UUID;
  v_action TEXT;
  v_before JSONB;
  v_after JSONB;
  v_user_id UUID;
BEGIN
  -- Get user from auth context (may be null for system operations)
  v_user_id := auth.uid();

  IF TG_OP = 'INSERT' THEN
    v_action := 'create';
    v_tenant_id := NEW.tenant_id;
    v_record_id := NEW.id;
    v_before := NULL;
    v_after := to_jsonb(NEW);
  ELSIF TG_OP = 'UPDATE' THEN
    v_action := 'update';
    v_tenant_id := NEW.tenant_id;
    v_record_id := NEW.id;
    v_before := to_jsonb(OLD);
    v_after := to_jsonb(NEW);
  ELSIF TG_OP = 'DELETE' THEN
    v_action := 'delete';
    v_tenant_id := OLD.tenant_id;
    v_record_id := OLD.id;
    v_before := to_jsonb(OLD);
    v_after := NULL;
  END IF;

  -- Insert audit record
  INSERT INTO public.audit_logs (
    tenant_id, table_name, record_id, action,
    before_data, after_data, user_id
  ) VALUES (
    v_tenant_id, TG_TABLE_NAME, v_record_id, v_action,
    v_before, v_after, v_user_id
  );

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  ELSE
    RETURN NEW;
  END IF;
END;
$$;

-- ============================================================
-- 3. ATTACH AUDIT TRIGGERS TO ALL TENANT-SCOPED TABLES
-- ============================================================

-- Suppliers
CREATE TRIGGER audit_suppliers
  AFTER INSERT OR UPDATE OR DELETE ON public.suppliers
  FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();

-- Ingredients
CREATE TRIGGER audit_ingredients
  AFTER INSERT OR UPDATE OR DELETE ON public.ingredients
  FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();

-- Overhead Monthly
CREATE TRIGGER audit_overhead_monthly
  AFTER INSERT OR UPDATE OR DELETE ON public.overhead_monthly
  FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();

-- Recipe Categories
CREATE TRIGGER audit_recipe_categories
  AFTER INSERT OR UPDATE OR DELETE ON public.recipe_categories
  FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();

-- Recipes
CREATE TRIGGER audit_recipes
  AFTER INSERT OR UPDATE OR DELETE ON public.recipes
  FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();

-- Recipe Items
CREATE TRIGGER audit_recipe_items
  AFTER INSERT OR UPDATE OR DELETE ON public.recipe_items
  FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();

-- Import Jobs
CREATE TRIGGER audit_import_jobs
  AFTER INSERT OR UPDATE ON public.import_jobs
  FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();

-- Tenant Memberships
CREATE TRIGGER audit_tenant_memberships
  AFTER INSERT OR UPDATE OR DELETE ON public.tenant_memberships
  FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();

-- Tenant Subscriptions
CREATE TRIGGER audit_tenant_subscriptions
  AFTER INSERT OR UPDATE ON public.tenant_subscriptions
  FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();

-- ============================================================
-- 4. UPDATED_AT AUTO-UPDATE TRIGGER
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

-- Attach updated_at trigger to all tables with updated_at column
CREATE TRIGGER set_updated_at_profiles
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

CREATE TRIGGER set_updated_at_tenants
  BEFORE UPDATE ON public.tenants
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

CREATE TRIGGER set_updated_at_memberships
  BEFORE UPDATE ON public.tenant_memberships
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

CREATE TRIGGER set_updated_at_subscriptions
  BEFORE UPDATE ON public.tenant_subscriptions
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

CREATE TRIGGER set_updated_at_suppliers
  BEFORE UPDATE ON public.suppliers
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

CREATE TRIGGER set_updated_at_ingredients
  BEFORE UPDATE ON public.ingredients
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

CREATE TRIGGER set_updated_at_overhead
  BEFORE UPDATE ON public.overhead_monthly
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

CREATE TRIGGER set_updated_at_recipes
  BEFORE UPDATE ON public.recipes
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

CREATE TRIGGER set_updated_at_recipe_items
  BEFORE UPDATE ON public.recipe_items
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
