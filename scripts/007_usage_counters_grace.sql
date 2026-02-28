-- ============================================================
-- MenuProfit 007: Usage counters + Grace period support
-- ============================================================

-- Usage counters for rate-limited features (AI requests/month)
CREATE TABLE IF NOT EXISTS public.usage_counters (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  resource_type TEXT NOT NULL, -- e.g. 'ai_requests'
  period_start DATE NOT NULL,  -- first day of the month
  period_end DATE NOT NULL,    -- last day of the month
  count INTEGER NOT NULL DEFAULT 0,
  max_allowed INTEGER NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(tenant_id, resource_type, period_start)
);

CREATE INDEX idx_usage_counters_tenant ON public.usage_counters(tenant_id);
CREATE INDEX idx_usage_counters_lookup ON public.usage_counters(tenant_id, resource_type, period_start);

ALTER TABLE public.usage_counters ENABLE ROW LEVEL SECURITY;

CREATE POLICY "usage_counters_select" ON public.usage_counters
  FOR SELECT USING (public.is_tenant_member(tenant_id));

CREATE POLICY "usage_counters_insert" ON public.usage_counters
  FOR INSERT WITH CHECK (public.is_tenant_manager_or_above(tenant_id));

CREATE POLICY "usage_counters_update" ON public.usage_counters
  FOR UPDATE USING (public.is_tenant_manager_or_above(tenant_id));

-- Add grace_period columns to tenant_subscriptions
ALTER TABLE public.tenant_subscriptions
  ADD COLUMN IF NOT EXISTS grace_starts_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS grace_ends_at TIMESTAMPTZ;

-- Function: increment usage counter and check limit
CREATE OR REPLACE FUNCTION public.increment_usage_counter(
  p_tenant_id UUID,
  p_resource_type TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_plan TEXT;
  v_max_allowed INT;
  v_current_count INT;
  v_period_start DATE;
  v_period_end DATE;
BEGIN
  -- Get current plan
  SELECT plan INTO v_plan
  FROM public.tenant_subscriptions
  WHERE tenant_id = p_tenant_id
    AND status IN ('active', 'trialing')
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_plan IS NULL THEN v_plan := 'free'; END IF;

  -- Determine limit
  CASE p_resource_type
    WHEN 'ai_requests' THEN
      v_max_allowed := CASE v_plan WHEN 'free' THEN 10 WHEN 'pro' THEN 100 ELSE 999999 END;
    ELSE
      v_max_allowed := 999999;
  END CASE;

  -- Current month period
  v_period_start := date_trunc('month', CURRENT_DATE)::DATE;
  v_period_end := (date_trunc('month', CURRENT_DATE) + interval '1 month' - interval '1 day')::DATE;

  -- Upsert counter
  INSERT INTO public.usage_counters (tenant_id, resource_type, period_start, period_end, count, max_allowed)
  VALUES (p_tenant_id, p_resource_type, v_period_start, v_period_end, 0, v_max_allowed)
  ON CONFLICT (tenant_id, resource_type, period_start)
  DO UPDATE SET max_allowed = v_max_allowed, updated_at = now();

  -- Get current count
  SELECT count INTO v_current_count
  FROM public.usage_counters
  WHERE tenant_id = p_tenant_id
    AND resource_type = p_resource_type
    AND period_start = v_period_start;

  -- Check if allowed
  IF v_current_count >= v_max_allowed THEN
    RETURN jsonb_build_object(
      'allowed', false,
      'plan', v_plan,
      'resource', p_resource_type,
      'current_count', v_current_count,
      'limit', v_max_allowed,
      'remaining', 0,
      'error', 'Monthly limit reached for ' || p_resource_type
    );
  END IF;

  -- Increment
  UPDATE public.usage_counters
  SET count = count + 1, updated_at = now()
  WHERE tenant_id = p_tenant_id
    AND resource_type = p_resource_type
    AND period_start = v_period_start;

  RETURN jsonb_build_object(
    'allowed', true,
    'plan', v_plan,
    'resource', p_resource_type,
    'current_count', v_current_count + 1,
    'limit', v_max_allowed,
    'remaining', v_max_allowed - (v_current_count + 1)
  );
END;
$$;

-- Function: check subscription grace period
CREATE OR REPLACE FUNCTION public.get_subscription_status(p_tenant_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sub RECORD;
  v_mode TEXT;
BEGIN
  SELECT * INTO v_sub
  FROM public.tenant_subscriptions
  WHERE tenant_id = p_tenant_id
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_sub IS NULL THEN
    RETURN jsonb_build_object('mode', 'active', 'plan', 'free', 'status', 'active');
  END IF;

  -- Check grace period (7 days after cancellation or past_due)
  IF v_sub.status = 'canceled' OR v_sub.status = 'past_due' THEN
    IF v_sub.grace_ends_at IS NOT NULL AND now() <= v_sub.grace_ends_at THEN
      v_mode := 'grace'; -- Read-only, no edits
    ELSIF v_sub.grace_ends_at IS NOT NULL AND now() > v_sub.grace_ends_at THEN
      v_mode := 'locked'; -- Fully locked
    ELSE
      v_mode := 'grace'; -- Default to grace if no grace_ends_at set
    END IF;
  ELSE
    v_mode := 'active';
  END IF;

  RETURN jsonb_build_object(
    'mode', v_mode,
    'plan', v_sub.plan,
    'status', v_sub.status,
    'grace_starts_at', v_sub.grace_starts_at,
    'grace_ends_at', v_sub.grace_ends_at,
    'current_period_end', v_sub.current_period_end
  );
END;
$$;

-- Attach audit trigger
CREATE TRIGGER audit_usage_counters
  AFTER INSERT OR UPDATE OR DELETE ON public.usage_counters
  FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();
