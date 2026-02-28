-- ============================================================
-- MenuProfit Calculation Validation Script
-- Validates all SQL functions match SRS formulas
-- Run after migrations 001-004
-- ============================================================

-- ============================================================
-- TEST 1: calc_effective_ingredient_cost
-- ============================================================
DO $$
DECLARE
  v_result NUMERIC;
BEGIN
  -- Case: Normal yield (price=40, yield=80) => 50.0000
  v_result := public.calc_effective_ingredient_cost(40, 80);
  ASSERT v_result = 50.0000, 
    format('TP-6.1 FAILED: expected 50.0000, got %s', v_result);
  RAISE NOTICE 'TP-6.1 PASSED: effective_cost(40, 80) = %', v_result;

  -- Case: 100% yield (price=40, yield=100) => 40.0000
  v_result := public.calc_effective_ingredient_cost(40, 100);
  ASSERT v_result = 40.0000,
    format('TP-6.2 FAILED: expected 40.0000, got %s', v_result);
  RAISE NOTICE 'TP-6.2 PASSED: effective_cost(40, 100) = %', v_result;

  -- Case: 0% yield fallback (price=40, yield=0) => 40.0000
  v_result := public.calc_effective_ingredient_cost(40, 0);
  ASSERT v_result = 40.0000,
    format('TP-6.3 FAILED: expected 40.0000, got %s', v_result);
  RAISE NOTICE 'TP-6.3 PASSED: effective_cost(40, 0) = %', v_result;

  -- Case: NULL yield fallback (price=40, yield=NULL) => 40.0000
  v_result := public.calc_effective_ingredient_cost(40, NULL);
  ASSERT v_result = 40.0000,
    format('TP-6.4 FAILED: expected 40.0000, got %s', v_result);
  RAISE NOTICE 'TP-6.4 PASSED: effective_cost(40, NULL) = %', v_result;
END $$;

-- ============================================================
-- TEST 2: calc_true_cost
-- ============================================================
DO $$
DECLARE
  v_result NUMERIC;
BEGIN
  -- True cost: food=12.53, overhead=25 => 37.5300
  v_result := public.calc_true_cost(12.53, 25);
  ASSERT v_result = 37.5300,
    format('TP-6.9 FAILED: expected 37.5300, got %s', v_result);
  RAISE NOTICE 'TP-6.9 PASSED: true_cost(12.53, 25) = %', v_result;

  -- True cost with NULL overhead => food cost only
  v_result := public.calc_true_cost(12.53, NULL);
  ASSERT v_result = 12.5300,
    format('TP-6.9b FAILED: expected 12.5300, got %s', v_result);
  RAISE NOTICE 'TP-6.9b PASSED: true_cost(12.53, NULL) = %', v_result;
END $$;

-- ============================================================
-- TEST 3: calc_margin_percent
-- ============================================================
DO $$
DECLARE
  v_result NUMERIC;
BEGIN
  -- Margin: SP=80, TC=37.53 => 53.09%
  v_result := public.calc_margin_percent(80, 37.53);
  ASSERT v_result = 53.09,
    format('TP-6.10 FAILED: expected 53.09, got %s', v_result);
  RAISE NOTICE 'TP-6.10 PASSED: margin_percent(80, 37.53) = %', v_result;

  -- Margin: SP=0 => NULL
  v_result := public.calc_margin_percent(0, 37.53);
  ASSERT v_result IS NULL,
    format('TP-6.11 FAILED: expected NULL, got %s', v_result);
  RAISE NOTICE 'TP-6.11 PASSED: margin_percent(0, 37.53) = NULL';

  -- Margin: SP=NULL => NULL
  v_result := public.calc_margin_percent(NULL, 37.53);
  ASSERT v_result IS NULL,
    format('TP-6.11b FAILED: expected NULL, got %s', v_result);
  RAISE NOTICE 'TP-6.11b PASSED: margin_percent(NULL, 37.53) = NULL';
END $$;

-- ============================================================
-- TEST 4: calc_contribution_margin
-- ============================================================
DO $$
DECLARE
  v_result NUMERIC;
BEGIN
  -- CM: SP=80, TC=37.53 => 42.47
  v_result := public.calc_contribution_margin(80, 37.53);
  ASSERT v_result = 42.47,
    format('TP-6.12 FAILED: expected 42.47, got %s', v_result);
  RAISE NOTICE 'TP-6.12 PASSED: contribution_margin(80, 37.53) = %', v_result;
END $$;

-- ============================================================
-- TEST 5: Verify schema completeness
-- ============================================================
DO $$
DECLARE
  v_count INTEGER;
  v_tables TEXT[] := ARRAY[
    'profiles', 'tenants', 'tenant_memberships', 'tenant_subscriptions',
    'suppliers', 'ingredients', 'ingredient_price_history', 'overhead_monthly',
    'recipe_categories', 'recipes', 'recipe_items', 'import_jobs',
    'sales_data', 'competitors', 'competitor_prices', 'action_items',
    'audit_logs'
  ];
  v_table TEXT;
BEGIN
  FOREACH v_table IN ARRAY v_tables LOOP
    SELECT COUNT(*) INTO v_count
    FROM pg_tables
    WHERE schemaname = 'public' AND tablename = v_table;
    
    ASSERT v_count = 1,
      format('TP-1.1 FAILED: table "%s" not found', v_table);
  END LOOP;
  RAISE NOTICE 'TP-1.1 PASSED: All 17 tables exist';
END $$;

-- ============================================================
-- TEST 6: Verify RLS enabled on all tables
-- ============================================================
DO $$
DECLARE
  v_row RECORD;
  v_failures TEXT := '';
BEGIN
  FOR v_row IN
    SELECT tablename, rowsecurity
    FROM pg_tables
    WHERE schemaname = 'public'
  LOOP
    IF NOT v_row.rowsecurity THEN
      v_failures := v_failures || v_row.tablename || ', ';
    END IF;
  END LOOP;

  IF v_failures != '' THEN
    RAISE EXCEPTION 'TP-1.2 FAILED: RLS not enabled on: %', v_failures;
  END IF;
  
  RAISE NOTICE 'TP-1.2 PASSED: RLS enabled on all public tables';
END $$;

-- ============================================================
-- TEST 7: Verify sales_data has NO price/revenue columns
-- ============================================================
DO $$
DECLARE
  v_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'sales_data'
    AND column_name IN ('price', 'revenue', 'total', 'amount', 'selling_price', 'sales_total', 'profit');

  ASSERT v_count = 0,
    format('TP-9.1 FAILED: sales_data has forbidden revenue columns (found %s)', v_count);
  RAISE NOTICE 'TP-9.1 PASSED: sales_data has NO revenue/price columns';
END $$;

-- ============================================================
-- TEST 8: Verify audit_logs immutability triggers exist
-- ============================================================
DO $$
DECLARE
  v_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM information_schema.triggers
  WHERE trigger_schema = 'public'
    AND event_object_table = 'audit_logs'
    AND trigger_name LIKE 'enforce_audit_log_immutable%';

  ASSERT v_count = 2,
    format('TP-4.4/4.5 FAILED: expected 2 immutability triggers, found %s', v_count);
  RAISE NOTICE 'TP-4.4/4.5 PASSED: audit_logs has 2 immutability triggers';
END $$;

-- ============================================================
-- TEST 9: Verify audit triggers exist on all business tables
-- ============================================================
DO $$
DECLARE
  v_count INTEGER;
  v_tables TEXT[] := ARRAY[
    'suppliers', 'ingredients', 'ingredient_price_history', 'overhead_monthly',
    'recipe_categories', 'recipes', 'recipe_items', 'import_jobs',
    'sales_data', 'competitors', 'competitor_prices', 'action_items',
    'tenant_memberships', 'tenant_subscriptions'
  ];
  v_table TEXT;
BEGIN
  FOREACH v_table IN ARRAY v_tables LOOP
    SELECT COUNT(*) INTO v_count
    FROM information_schema.triggers
    WHERE trigger_schema = 'public'
      AND event_object_table = v_table
      AND trigger_name LIKE 'audit_%';
    
    IF v_count = 0 THEN
      RAISE EXCEPTION 'TP-4.8 FAILED: no audit trigger on table "%"', v_table;
    END IF;
  END LOOP;
  RAISE NOTICE 'TP-4.8 PASSED: audit triggers exist on all 14 business tables';
END $$;

-- ============================================================
-- TEST 10: Verify functions exist
-- ============================================================
DO $$
DECLARE
  v_count INTEGER;
  v_funcs TEXT[] := ARRAY[
    'calc_effective_ingredient_cost',
    'calc_recipe_food_cost',
    'get_latest_overhead_per_plate',
    'get_overhead_per_plate_for_month',
    'calc_true_cost',
    'calc_recipe_true_cost',
    'calc_margin_percent',
    'calc_contribution_margin',
    'get_recipe_analysis',
    'get_all_recipes_analysis',
    'check_plan_limit',
    'is_tenant_member',
    'is_tenant_owner',
    'is_tenant_manager_or_above',
    'get_tenant_role',
    'audit_trigger_func',
    'prevent_audit_log_mutation'
  ];
  v_func TEXT;
BEGIN
  FOREACH v_func IN ARRAY v_funcs LOOP
    SELECT COUNT(*) INTO v_count
    FROM pg_proc
    WHERE proname = v_func
      AND pronamespace = 'public'::regnamespace;
    
    IF v_count = 0 THEN
      RAISE EXCEPTION 'FUNC CHECK FAILED: function "%" not found', v_func;
    END IF;
  END LOOP;
  RAISE NOTICE 'FUNC CHECK PASSED: all 17 functions exist';
END $$;

DO $$
BEGIN
  RAISE NOTICE '====================================';
  RAISE NOTICE 'ALL VALIDATION TESTS PASSED';
  RAISE NOTICE '====================================';
END $$;
