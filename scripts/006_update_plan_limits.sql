-- ============================================================
-- MenuProfit 006: Update plan limits to match SRS spec
-- Free: 30 ingredients, 20 recipes, 10 AI/month
-- ============================================================

CREATE OR REPLACE FUNCTION public.check_plan_limit(
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
  v_status TEXT;
  v_current_count INT;
  v_limit INT;
  v_period_end TIMESTAMPTZ;
BEGIN
  -- Get current plan
  SELECT plan, status, current_period_end
  INTO v_plan, v_status, v_period_end
  FROM public.tenant_subscriptions
  WHERE tenant_id = p_tenant_id
    AND status IN ('active', 'trialing', 'past_due')
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_plan IS NULL THEN
    v_plan := 'free';
    v_status := 'active';
  END IF;

  -- Determine limit based on plan (updated per SRS spec)
  CASE p_resource_type
    WHEN 'ingredients' THEN
      v_limit := CASE v_plan WHEN 'free' THEN 30 WHEN 'pro' THEN 300 ELSE 999999 END;
      SELECT COUNT(*) INTO v_current_count FROM public.ingredients WHERE tenant_id = p_tenant_id AND is_active = true;
    WHEN 'recipes' THEN
      v_limit := CASE v_plan WHEN 'free' THEN 20 WHEN 'pro' THEN 150 ELSE 999999 END;
      SELECT COUNT(*) INTO v_current_count FROM public.recipes WHERE tenant_id = p_tenant_id AND status != 'archived';
    WHEN 'suppliers' THEN
      v_limit := CASE v_plan WHEN 'free' THEN 10 WHEN 'pro' THEN 50 ELSE 999999 END;
      SELECT COUNT(*) INTO v_current_count FROM public.suppliers WHERE tenant_id = p_tenant_id AND is_active = true;
    WHEN 'users' THEN
      v_limit := CASE v_plan WHEN 'free' THEN 1 WHEN 'pro' THEN 5 ELSE 20 END;
      SELECT COUNT(*) INTO v_current_count FROM public.tenant_memberships WHERE tenant_id = p_tenant_id AND is_active = true;
    ELSE
      RETURN jsonb_build_object(
        'allowed', true,
        'plan', v_plan,
        'resource', p_resource_type,
        'current_count', 0,
        'limit', 999999,
        'remaining', 999999
      );
  END CASE;

  RETURN jsonb_build_object(
    'allowed', v_current_count < v_limit,
    'plan', v_plan,
    'resource', p_resource_type,
    'current_count', v_current_count,
    'limit', v_limit,
    'remaining', GREATEST(0, v_limit - v_current_count)
  );
END;
$$;
