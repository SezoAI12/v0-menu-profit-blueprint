-- ============================================================
-- MenuProfit Calculation Functions - Migration 004
-- Server-side cost, margin, and overhead calculations
-- ============================================================

-- ============================================================
-- 1. EFFECTIVE INGREDIENT COST
--    = purchase_price / (yield_percent / 100)
--    This accounts for waste/yield loss
-- ============================================================
CREATE OR REPLACE FUNCTION public.calc_effective_ingredient_cost(
  p_price NUMERIC,
  p_yield_percent NUMERIC
)
RETURNS NUMERIC
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_yield_percent IS NULL OR p_yield_percent <= 0 THEN p_price
    ELSE ROUND(p_price / (p_yield_percent / 100.0), 4)
  END;
$$;

-- Get effective cost for a specific ingredient by ID
CREATE OR REPLACE FUNCTION public.get_ingredient_effective_cost(
  p_ingredient_id UUID
)
RETURNS NUMERIC
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.calc_effective_ingredient_cost(current_price, yield_percent)
  FROM public.ingredients
  WHERE id = p_ingredient_id;
$$;

-- ============================================================
-- 2. RECIPE FOOD COST
--    = SUM of (effective_ingredient_cost * quantity_in_recipe_units)
--    quantity_in_recipe_units = quantity / unit_conversion_factor
--    (unit_conversion_factor converts purchase units to recipe units)
--
--    Example: chicken breast costs 40 SAR/kg, yield 80%
--      effective_cost = 40 / 0.8 = 50 SAR/kg
--      recipe uses 200g = 0.2 kg (200/1000)
--      item_cost = 50 * 0.2 = 10 SAR
-- ============================================================
CREATE OR REPLACE FUNCTION public.calc_recipe_food_cost(
  p_recipe_id UUID
)
RETURNS NUMERIC
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(SUM(
    public.calc_effective_ingredient_cost(i.current_price, i.yield_percent)
    * (ri.quantity / ri.unit_conversion_factor)
  ), 0)
  FROM public.recipe_items ri
  JOIN public.ingredients i ON i.id = ri.ingredient_id
  WHERE ri.recipe_id = p_recipe_id;
$$;

-- ============================================================
-- 3. LATEST OVERHEAD PER PLATE
--    Returns the most recent month's overhead_per_plate for a tenant.
--    Falls back to 0 if no overhead data exists.
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_latest_overhead_per_plate(
  p_tenant_id UUID
)
RETURNS NUMERIC
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (
      SELECT overhead_per_plate
      FROM public.overhead_monthly
      WHERE tenant_id = p_tenant_id
      ORDER BY year DESC, month DESC
      LIMIT 1
    ),
    0
  );
$$;

-- Get overhead per plate for a specific month
CREATE OR REPLACE FUNCTION public.get_overhead_per_plate_for_month(
  p_tenant_id UUID,
  p_year INTEGER,
  p_month INTEGER
)
RETURNS NUMERIC
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (
      SELECT overhead_per_plate
      FROM public.overhead_monthly
      WHERE tenant_id = p_tenant_id
        AND year = p_year
        AND month = p_month
      LIMIT 1
    ),
    -- Fallback to latest if specific month not found
    public.get_latest_overhead_per_plate(p_tenant_id)
  );
$$;

-- ============================================================
-- 4. TRUE COST
--    = Food Cost + Overhead Per Plate
-- ============================================================
CREATE OR REPLACE FUNCTION public.calc_true_cost(
  p_food_cost NUMERIC,
  p_overhead_per_plate NUMERIC
)
RETURNS NUMERIC
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT ROUND(p_food_cost + COALESCE(p_overhead_per_plate, 0), 4);
$$;

-- Full true cost for a recipe (fetches food cost + latest overhead)
CREATE OR REPLACE FUNCTION public.calc_recipe_true_cost(
  p_recipe_id UUID,
  p_tenant_id UUID
)
RETURNS NUMERIC
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.calc_true_cost(
    public.calc_recipe_food_cost(p_recipe_id),
    public.get_latest_overhead_per_plate(p_tenant_id)
  );
$$;

-- ============================================================
-- 5. MARGIN PERCENT
--    = (Selling Price - True Cost) / Selling Price * 100
--    Returns NULL if selling_price is 0
-- ============================================================
CREATE OR REPLACE FUNCTION public.calc_margin_percent(
  p_selling_price NUMERIC,
  p_true_cost NUMERIC
)
RETURNS NUMERIC
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_selling_price IS NULL OR p_selling_price = 0 THEN NULL
    ELSE ROUND(((p_selling_price - p_true_cost) / p_selling_price) * 100, 2)
  END;
$$;

-- ============================================================
-- 6. CONTRIBUTION MARGIN
--    = Selling Price - True Cost
-- ============================================================
CREATE OR REPLACE FUNCTION public.calc_contribution_margin(
  p_selling_price NUMERIC,
  p_true_cost NUMERIC
)
RETURNS NUMERIC
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT ROUND(p_selling_price - p_true_cost, 2);
$$;

-- ============================================================
-- 7. FULL RECIPE ANALYSIS (composite view)
--    Returns all calculated metrics for a recipe in one call
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_recipe_analysis(
  p_recipe_id UUID,
  p_tenant_id UUID
)
RETURNS TABLE (
  recipe_id UUID,
  food_cost NUMERIC,
  overhead_per_plate NUMERIC,
  true_cost NUMERIC,
  selling_price NUMERIC,
  margin_percent NUMERIC,
  contribution_margin NUMERIC,
  target_margin NUMERIC,
  margin_gap NUMERIC
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH recipe_data AS (
    SELECT
      r.id,
      r.selling_price AS sp,
      r.target_margin AS tm,
      public.calc_recipe_food_cost(r.id) AS fc,
      public.get_latest_overhead_per_plate(p_tenant_id) AS opp
    FROM public.recipes r
    WHERE r.id = p_recipe_id
      AND r.tenant_id = p_tenant_id
  )
  SELECT
    rd.id AS recipe_id,
    rd.fc AS food_cost,
    rd.opp AS overhead_per_plate,
    public.calc_true_cost(rd.fc, rd.opp) AS true_cost,
    rd.sp AS selling_price,
    public.calc_margin_percent(rd.sp, public.calc_true_cost(rd.fc, rd.opp)) AS margin_percent,
    public.calc_contribution_margin(rd.sp, public.calc_true_cost(rd.fc, rd.opp)) AS contribution_margin,
    rd.tm AS target_margin,
    CASE
      WHEN rd.tm IS NOT NULL THEN
        public.calc_margin_percent(rd.sp, public.calc_true_cost(rd.fc, rd.opp)) - rd.tm
      ELSE NULL
    END AS margin_gap
  FROM recipe_data rd;
$$;

-- ============================================================
-- 8. BATCH RECIPE ANALYSIS (all recipes for a tenant)
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_all_recipes_analysis(
  p_tenant_id UUID
)
RETURNS TABLE (
  recipe_id UUID,
  recipe_name TEXT,
  recipe_name_ar TEXT,
  category_name TEXT,
  status public.recipe_status,
  food_cost NUMERIC,
  overhead_per_plate NUMERIC,
  true_cost NUMERIC,
  selling_price NUMERIC,
  margin_percent NUMERIC,
  contribution_margin NUMERIC,
  target_margin NUMERIC,
  margin_gap NUMERIC
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH opp AS (
    SELECT public.get_latest_overhead_per_plate(p_tenant_id) AS val
  )
  SELECT
    r.id AS recipe_id,
    r.name AS recipe_name,
    r.name_ar AS recipe_name_ar,
    rc.name AS category_name,
    r.status,
    public.calc_recipe_food_cost(r.id) AS food_cost,
    opp.val AS overhead_per_plate,
    public.calc_true_cost(public.calc_recipe_food_cost(r.id), opp.val) AS true_cost,
    r.selling_price,
    public.calc_margin_percent(
      r.selling_price,
      public.calc_true_cost(public.calc_recipe_food_cost(r.id), opp.val)
    ) AS margin_percent,
    public.calc_contribution_margin(
      r.selling_price,
      public.calc_true_cost(public.calc_recipe_food_cost(r.id), opp.val)
    ) AS contribution_margin,
    r.target_margin,
    CASE
      WHEN r.target_margin IS NOT NULL THEN
        public.calc_margin_percent(
          r.selling_price,
          public.calc_true_cost(public.calc_recipe_food_cost(r.id), opp.val)
        ) - r.target_margin
      ELSE NULL
    END AS margin_gap
  FROM public.recipes r
  CROSS JOIN opp
  LEFT JOIN public.recipe_categories rc ON rc.id = r.category_id
  WHERE r.tenant_id = p_tenant_id;
$$;

-- ============================================================
-- 9. SUBSCRIPTION PLAN LIMIT CHECKER
--    Server-side enforcement of plan limits
-- ============================================================
CREATE OR REPLACE FUNCTION public.check_plan_limit(
  p_tenant_id UUID,
  p_resource_type TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_plan public.subscription_plan;
  v_current_count INTEGER;
  v_limit INTEGER;
  v_allowed BOOLEAN;
BEGIN
  -- Get current plan
  SELECT plan INTO v_plan
  FROM public.tenant_subscriptions
  WHERE tenant_id = p_tenant_id
    AND status = 'active';

  -- Default to free if no subscription found
  IF v_plan IS NULL THEN
    v_plan := 'free';
  END IF;

  -- Get current count and limit based on resource type
  CASE p_resource_type
    WHEN 'recipes' THEN
      SELECT COUNT(*) INTO v_current_count FROM public.recipes WHERE tenant_id = p_tenant_id;
      v_limit := CASE v_plan WHEN 'free' THEN 25 WHEN 'pro' THEN 150 ELSE 999999 END;

    WHEN 'ingredients' THEN
      SELECT COUNT(*) INTO v_current_count FROM public.ingredients WHERE tenant_id = p_tenant_id;
      v_limit := CASE v_plan WHEN 'free' THEN 50 WHEN 'pro' THEN 300 ELSE 999999 END;

    WHEN 'suppliers' THEN
      SELECT COUNT(*) INTO v_current_count FROM public.suppliers WHERE tenant_id = p_tenant_id;
      v_limit := CASE v_plan WHEN 'free' THEN 10 WHEN 'pro' THEN 50 ELSE 999999 END;

    WHEN 'users' THEN
      SELECT COUNT(*) INTO v_current_count FROM public.tenant_memberships WHERE tenant_id = p_tenant_id AND is_active = true;
      v_limit := CASE v_plan WHEN 'free' THEN 1 WHEN 'pro' THEN 5 ELSE 20 END;

    WHEN 'tenants' THEN
      SELECT COUNT(*) INTO v_current_count
      FROM public.tenant_memberships tm
      JOIN public.tenants t ON t.id = tm.tenant_id
      WHERE tm.user_id = auth.uid()
        AND tm.role = 'owner'
        AND tm.is_active = true
        AND t.is_active = true;
      v_limit := CASE v_plan WHEN 'free' THEN 1 WHEN 'pro' THEN 3 ELSE 10 END;

    ELSE
      RETURN jsonb_build_object('allowed', false, 'error', 'Unknown resource type');
  END CASE;

  v_allowed := v_current_count < v_limit;

  RETURN jsonb_build_object(
    'allowed', v_allowed,
    'plan', v_plan,
    'resource', p_resource_type,
    'current_count', v_current_count,
    'limit', v_limit,
    'remaining', GREATEST(v_limit - v_current_count, 0)
  );
END;
$$;

-- ============================================================
-- 10. AUTO-CREATE SUBSCRIPTION ON TENANT CREATION
-- ============================================================
CREATE OR REPLACE FUNCTION public.create_default_subscription()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.tenant_subscriptions (tenant_id, plan, status)
  VALUES (NEW.id, 'free', 'active')
  ON CONFLICT (tenant_id) DO NOTHING;
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_tenant_created_subscription
  AFTER INSERT ON public.tenants
  FOR EACH ROW
  EXECUTE FUNCTION public.create_default_subscription();
