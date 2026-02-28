-- ============================================================
-- MenuProfit Business Entities - Migration 002
-- Suppliers, Ingredients, Price History, Overhead, Recipes
-- ============================================================

-- ============================================================
-- 1. SUPPLIERS
-- ============================================================
CREATE TABLE IF NOT EXISTS public.suppliers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  name_ar TEXT,
  contact_name TEXT,
  phone TEXT,
  email TEXT,
  address TEXT,
  notes TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_by UUID NOT NULL REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_suppliers_tenant ON public.suppliers(tenant_id);

ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "suppliers_select" ON public.suppliers
  FOR SELECT USING (public.is_tenant_member(tenant_id));

CREATE POLICY "suppliers_insert" ON public.suppliers
  FOR INSERT WITH CHECK (
    public.is_tenant_manager_or_above(tenant_id)
    AND auth.uid() = created_by
  );

CREATE POLICY "suppliers_update" ON public.suppliers
  FOR UPDATE USING (public.is_tenant_manager_or_above(tenant_id));

CREATE POLICY "suppliers_delete" ON public.suppliers
  FOR DELETE USING (public.is_tenant_manager_or_above(tenant_id));

-- ============================================================
-- 2. INGREDIENTS
-- ============================================================
CREATE TYPE public.unit_type AS ENUM (
  'kg', 'g', 'mg',
  'l', 'ml',
  'piece', 'dozen',
  'lb', 'oz',
  'cup', 'tbsp', 'tsp',
  'bunch', 'can', 'bag', 'box', 'pack'
);

CREATE TABLE IF NOT EXISTS public.ingredients (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  name_ar TEXT,
  category TEXT,
  purchase_unit public.unit_type NOT NULL DEFAULT 'kg',
  recipe_unit public.unit_type NOT NULL DEFAULT 'g',
  unit_conversion_factor NUMERIC(12,4) NOT NULL DEFAULT 1000
    CHECK (unit_conversion_factor > 0),
  current_price NUMERIC(12,4) NOT NULL DEFAULT 0
    CHECK (current_price >= 0),
  yield_percent NUMERIC(5,2) NOT NULL DEFAULT 100
    CHECK (yield_percent > 0 AND yield_percent <= 100),
  waste_percent NUMERIC(5,2) NOT NULL DEFAULT 0
    CHECK (waste_percent >= 0 AND waste_percent < 100),
  alert_threshold_price NUMERIC(12,4),
  alert_threshold_percent NUMERIC(5,2) DEFAULT 10
    CHECK (alert_threshold_percent IS NULL OR alert_threshold_percent > 0),
  supplier_id UUID REFERENCES public.suppliers(id) ON DELETE SET NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_by UUID NOT NULL REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- Ensure yield + waste consistency
  CONSTRAINT yield_waste_check CHECK (yield_percent + waste_percent <= 100)
);

CREATE INDEX idx_ingredients_tenant ON public.ingredients(tenant_id);
CREATE INDEX idx_ingredients_supplier ON public.ingredients(supplier_id);
CREATE INDEX idx_ingredients_category ON public.ingredients(tenant_id, category);

ALTER TABLE public.ingredients ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ingredients_select" ON public.ingredients
  FOR SELECT USING (public.is_tenant_member(tenant_id));

CREATE POLICY "ingredients_insert" ON public.ingredients
  FOR INSERT WITH CHECK (
    public.is_tenant_manager_or_above(tenant_id)
    AND auth.uid() = created_by
  );

CREATE POLICY "ingredients_update" ON public.ingredients
  FOR UPDATE USING (public.is_tenant_manager_or_above(tenant_id));

CREATE POLICY "ingredients_delete" ON public.ingredients
  FOR DELETE USING (public.is_tenant_manager_or_above(tenant_id));

-- ============================================================
-- 3. INGREDIENT PRICE HISTORY (append-only)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.ingredient_price_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  ingredient_id UUID NOT NULL REFERENCES public.ingredients(id) ON DELETE CASCADE,
  price NUMERIC(12,4) NOT NULL CHECK (price >= 0),
  effective_date DATE NOT NULL DEFAULT CURRENT_DATE,
  notes TEXT,
  recorded_by UUID NOT NULL REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
  -- NO updated_at: this table is append-only
);

CREATE INDEX idx_price_history_ingredient ON public.ingredient_price_history(ingredient_id, effective_date DESC);
CREATE INDEX idx_price_history_tenant ON public.ingredient_price_history(tenant_id);

ALTER TABLE public.ingredient_price_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "price_history_select" ON public.ingredient_price_history
  FOR SELECT USING (public.is_tenant_member(tenant_id));

CREATE POLICY "price_history_insert" ON public.ingredient_price_history
  FOR INSERT WITH CHECK (
    public.is_tenant_manager_or_above(tenant_id)
    AND auth.uid() = recorded_by
  );

-- NO UPDATE or DELETE policies: append-only table
-- Enforce append-only with trigger
CREATE OR REPLACE FUNCTION public.prevent_price_history_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'ingredient_price_history is append-only. UPDATE and DELETE are forbidden.';
  RETURN NULL;
END;
$$;

CREATE TRIGGER enforce_price_history_append_only_update
  BEFORE UPDATE ON public.ingredient_price_history
  FOR EACH ROW
  EXECUTE FUNCTION public.prevent_price_history_mutation();

CREATE TRIGGER enforce_price_history_append_only_delete
  BEFORE DELETE ON public.ingredient_price_history
  FOR EACH ROW
  EXECUTE FUNCTION public.prevent_price_history_mutation();

-- Auto-record price history when ingredient price changes
CREATE OR REPLACE FUNCTION public.record_ingredient_price_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Only record if price actually changed
  IF OLD.current_price IS DISTINCT FROM NEW.current_price THEN
    INSERT INTO public.ingredient_price_history (
      tenant_id, ingredient_id, price, effective_date, recorded_by
    ) VALUES (
      NEW.tenant_id, NEW.id, NEW.current_price, CURRENT_DATE, auth.uid()
    );
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_ingredient_price_change
  AFTER UPDATE ON public.ingredients
  FOR EACH ROW
  EXECUTE FUNCTION public.record_ingredient_price_change();

-- Also record initial price on ingredient creation
CREATE OR REPLACE FUNCTION public.record_ingredient_initial_price()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.current_price > 0 THEN
    INSERT INTO public.ingredient_price_history (
      tenant_id, ingredient_id, price, effective_date, recorded_by
    ) VALUES (
      NEW.tenant_id, NEW.id, NEW.current_price, CURRENT_DATE, NEW.created_by
    );
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_ingredient_created
  AFTER INSERT ON public.ingredients
  FOR EACH ROW
  EXECUTE FUNCTION public.record_ingredient_initial_price();

-- ============================================================
-- 4. OVERHEAD MONTHLY
-- ============================================================
CREATE TABLE IF NOT EXISTS public.overhead_monthly (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  month INTEGER NOT NULL CHECK (month >= 1 AND month <= 12),
  year INTEGER NOT NULL CHECK (year >= 2020 AND year <= 2100),
  rent NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (rent >= 0),
  salaries NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (salaries >= 0),
  utilities NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (utilities >= 0),
  marketing NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (marketing >= 0),
  other NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (other >= 0),
  baseline_plates INTEGER NOT NULL CHECK (baseline_plates > 0),
  -- Computed: (rent + salaries + utilities + marketing + other) / baseline_plates
  overhead_per_plate NUMERIC(12,4) GENERATED ALWAYS AS (
    (rent + salaries + utilities + marketing + other) / baseline_plates
  ) STORED,
  notes TEXT,
  created_by UUID NOT NULL REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, month, year)
);

CREATE INDEX idx_overhead_tenant_date ON public.overhead_monthly(tenant_id, year DESC, month DESC);

ALTER TABLE public.overhead_monthly ENABLE ROW LEVEL SECURITY;

CREATE POLICY "overhead_select" ON public.overhead_monthly
  FOR SELECT USING (public.is_tenant_member(tenant_id));

CREATE POLICY "overhead_insert" ON public.overhead_monthly
  FOR INSERT WITH CHECK (
    public.is_tenant_manager_or_above(tenant_id)
    AND auth.uid() = created_by
  );

CREATE POLICY "overhead_update" ON public.overhead_monthly
  FOR UPDATE USING (public.is_tenant_manager_or_above(tenant_id));

CREATE POLICY "overhead_delete" ON public.overhead_monthly
  FOR DELETE USING (public.is_tenant_owner(tenant_id));

-- ============================================================
-- 5. RECIPE CATEGORIES
-- ============================================================
CREATE TABLE IF NOT EXISTS public.recipe_categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  name_ar TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, name)
);

CREATE INDEX idx_recipe_categories_tenant ON public.recipe_categories(tenant_id);

ALTER TABLE public.recipe_categories ENABLE ROW LEVEL SECURITY;

CREATE POLICY "recipe_categories_select" ON public.recipe_categories
  FOR SELECT USING (public.is_tenant_member(tenant_id));

CREATE POLICY "recipe_categories_insert" ON public.recipe_categories
  FOR INSERT WITH CHECK (public.is_tenant_manager_or_above(tenant_id));

CREATE POLICY "recipe_categories_update" ON public.recipe_categories
  FOR UPDATE USING (public.is_tenant_manager_or_above(tenant_id));

CREATE POLICY "recipe_categories_delete" ON public.recipe_categories
  FOR DELETE USING (public.is_tenant_manager_or_above(tenant_id));

-- ============================================================
-- 6. RECIPES
-- ============================================================
CREATE TYPE public.recipe_status AS ENUM ('draft', 'active', 'archived');

CREATE TABLE IF NOT EXISTS public.recipes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  name_ar TEXT,
  category_id UUID REFERENCES public.recipe_categories(id) ON DELETE SET NULL,
  selling_price NUMERIC(12,2) NOT NULL CHECK (selling_price >= 0),
  target_margin NUMERIC(5,2) CHECK (target_margin IS NULL OR (target_margin >= 0 AND target_margin <= 100)),
  status public.recipe_status NOT NULL DEFAULT 'draft',
  is_protected BOOLEAN NOT NULL DEFAULT false,
  notes TEXT,
  created_by UUID NOT NULL REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_recipes_tenant ON public.recipes(tenant_id);
CREATE INDEX idx_recipes_category ON public.recipes(category_id);
CREATE INDEX idx_recipes_status ON public.recipes(tenant_id, status);

ALTER TABLE public.recipes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "recipes_select" ON public.recipes
  FOR SELECT USING (public.is_tenant_member(tenant_id));

CREATE POLICY "recipes_insert" ON public.recipes
  FOR INSERT WITH CHECK (
    public.is_tenant_manager_or_above(tenant_id)
    AND auth.uid() = created_by
  );

CREATE POLICY "recipes_update" ON public.recipes
  FOR UPDATE USING (public.is_tenant_manager_or_above(tenant_id));

CREATE POLICY "recipes_delete" ON public.recipes
  FOR DELETE USING (
    public.is_tenant_manager_or_above(tenant_id)
    AND is_protected = false
  );

-- ============================================================
-- 7. RECIPE ITEMS (recipe <-> ingredient link)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.recipe_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  recipe_id UUID NOT NULL REFERENCES public.recipes(id) ON DELETE CASCADE,
  ingredient_id UUID NOT NULL REFERENCES public.ingredients(id) ON DELETE RESTRICT,
  quantity NUMERIC(12,4) NOT NULL CHECK (quantity > 0),
  unit public.unit_type NOT NULL,
  unit_conversion_factor NUMERIC(12,4) NOT NULL DEFAULT 1
    CHECK (unit_conversion_factor > 0),
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (recipe_id, ingredient_id)
);

CREATE INDEX idx_recipe_items_recipe ON public.recipe_items(recipe_id);
CREATE INDEX idx_recipe_items_ingredient ON public.recipe_items(ingredient_id);
CREATE INDEX idx_recipe_items_tenant ON public.recipe_items(tenant_id);

ALTER TABLE public.recipe_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "recipe_items_select" ON public.recipe_items
  FOR SELECT USING (public.is_tenant_member(tenant_id));

CREATE POLICY "recipe_items_insert" ON public.recipe_items
  FOR INSERT WITH CHECK (public.is_tenant_manager_or_above(tenant_id));

CREATE POLICY "recipe_items_update" ON public.recipe_items
  FOR UPDATE USING (public.is_tenant_manager_or_above(tenant_id));

CREATE POLICY "recipe_items_delete" ON public.recipe_items
  FOR DELETE USING (public.is_tenant_manager_or_above(tenant_id));

-- ============================================================
-- 8. IMPORT JOBS
-- ============================================================
CREATE TYPE public.import_type AS ENUM ('ingredients', 'suppliers', 'recipes', 'sales');
CREATE TYPE public.import_status AS ENUM ('pending', 'validating', 'importing', 'completed', 'failed');

CREATE TABLE IF NOT EXISTS public.import_jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  type public.import_type NOT NULL,
  file_name TEXT NOT NULL,
  status public.import_status NOT NULL DEFAULT 'pending',
  total_rows INTEGER DEFAULT 0,
  success_rows INTEGER DEFAULT 0,
  error_rows INTEGER DEFAULT 0,
  error_details JSONB DEFAULT '[]'::jsonb,
  created_by UUID NOT NULL REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ
);

CREATE INDEX idx_import_jobs_tenant ON public.import_jobs(tenant_id);

ALTER TABLE public.import_jobs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "import_jobs_select" ON public.import_jobs
  FOR SELECT USING (public.is_tenant_member(tenant_id));

CREATE POLICY "import_jobs_insert" ON public.import_jobs
  FOR INSERT WITH CHECK (
    public.is_tenant_manager_or_above(tenant_id)
    AND auth.uid() = created_by
  );

CREATE POLICY "import_jobs_update" ON public.import_jobs
  FOR UPDATE USING (public.is_tenant_manager_or_above(tenant_id));

-- ============================================================
-- 9. SALES DATA (volume-only, NO revenue/totals)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.sales_data (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  recipe_id UUID NOT NULL REFERENCES public.recipes(id) ON DELETE CASCADE,
  sale_date DATE NOT NULL DEFAULT CURRENT_DATE,
  quantity_sold INTEGER NOT NULL CHECK (quantity_sold > 0),
  -- STRICTLY NO price/revenue columns - volume only per SRS
  import_job_id UUID REFERENCES public.import_jobs(id) ON DELETE SET NULL,
  created_by UUID NOT NULL REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_sales_data_tenant ON public.sales_data(tenant_id);
CREATE INDEX idx_sales_data_recipe ON public.sales_data(recipe_id, sale_date);
CREATE INDEX idx_sales_data_date ON public.sales_data(tenant_id, sale_date DESC);

ALTER TABLE public.sales_data ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sales_data_select" ON public.sales_data
  FOR SELECT USING (public.is_tenant_member(tenant_id));

CREATE POLICY "sales_data_insert" ON public.sales_data
  FOR INSERT WITH CHECK (
    public.is_tenant_manager_or_above(tenant_id)
    AND auth.uid() = created_by
  );

CREATE POLICY "sales_data_delete" ON public.sales_data
  FOR DELETE USING (public.is_tenant_manager_or_above(tenant_id));

-- ============================================================
-- 10. COMPETITION TRACKING (Pro+)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.competitors (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  name_ar TEXT,
  location TEXT,
  notes TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_by UUID NOT NULL REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_competitors_tenant ON public.competitors(tenant_id);

ALTER TABLE public.competitors ENABLE ROW LEVEL SECURITY;

CREATE POLICY "competitors_select" ON public.competitors
  FOR SELECT USING (public.is_tenant_member(tenant_id));

CREATE POLICY "competitors_insert" ON public.competitors
  FOR INSERT WITH CHECK (
    public.is_tenant_manager_or_above(tenant_id)
    AND auth.uid() = created_by
  );

CREATE POLICY "competitors_update" ON public.competitors
  FOR UPDATE USING (public.is_tenant_manager_or_above(tenant_id));

CREATE POLICY "competitors_delete" ON public.competitors
  FOR DELETE USING (public.is_tenant_manager_or_above(tenant_id));

CREATE TABLE IF NOT EXISTS public.competitor_prices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  competitor_id UUID NOT NULL REFERENCES public.competitors(id) ON DELETE CASCADE,
  recipe_id UUID REFERENCES public.recipes(id) ON DELETE SET NULL,
  dish_name TEXT NOT NULL,
  price NUMERIC(12,2) NOT NULL CHECK (price >= 0),
  observed_date DATE NOT NULL DEFAULT CURRENT_DATE,
  notes TEXT,
  created_by UUID NOT NULL REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_competitor_prices_tenant ON public.competitor_prices(tenant_id);
CREATE INDEX idx_competitor_prices_competitor ON public.competitor_prices(competitor_id);

ALTER TABLE public.competitor_prices ENABLE ROW LEVEL SECURITY;

CREATE POLICY "competitor_prices_select" ON public.competitor_prices
  FOR SELECT USING (public.is_tenant_member(tenant_id));

CREATE POLICY "competitor_prices_insert" ON public.competitor_prices
  FOR INSERT WITH CHECK (
    public.is_tenant_manager_or_above(tenant_id)
    AND auth.uid() = created_by
  );

-- ============================================================
-- 11. ACTION PLAN (tracking recommended actions)
-- ============================================================
CREATE TYPE public.action_status AS ENUM ('pending', 'in_progress', 'done', 'dismissed');
CREATE TYPE public.action_priority AS ENUM ('low', 'medium', 'high', 'critical');

CREATE TABLE IF NOT EXISTS public.action_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  title_ar TEXT,
  description TEXT,
  description_ar TEXT,
  priority public.action_priority NOT NULL DEFAULT 'medium',
  status public.action_status NOT NULL DEFAULT 'pending',
  source TEXT, -- e.g. 'ai_suggestion', 'risk_radar', 'manual'
  related_recipe_id UUID REFERENCES public.recipes(id) ON DELETE SET NULL,
  related_ingredient_id UUID REFERENCES public.ingredients(id) ON DELETE SET NULL,
  assigned_to UUID REFERENCES auth.users(id),
  due_date DATE,
  completed_at TIMESTAMPTZ,
  created_by UUID NOT NULL REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_action_items_tenant ON public.action_items(tenant_id);
CREATE INDEX idx_action_items_status ON public.action_items(tenant_id, status);

ALTER TABLE public.action_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "action_items_select" ON public.action_items
  FOR SELECT USING (public.is_tenant_member(tenant_id));

CREATE POLICY "action_items_insert" ON public.action_items
  FOR INSERT WITH CHECK (
    public.is_tenant_manager_or_above(tenant_id)
    AND auth.uid() = created_by
  );

CREATE POLICY "action_items_update" ON public.action_items
  FOR UPDATE USING (public.is_tenant_member(tenant_id));

CREATE POLICY "action_items_delete" ON public.action_items
  FOR DELETE USING (public.is_tenant_manager_or_above(tenant_id));

-- ============================================================
-- UPDATED_AT TRIGGERS for all business tables
-- ============================================================
CREATE TRIGGER suppliers_updated_at BEFORE UPDATE ON public.suppliers
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
CREATE TRIGGER ingredients_updated_at BEFORE UPDATE ON public.ingredients
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
CREATE TRIGGER overhead_updated_at BEFORE UPDATE ON public.overhead_monthly
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
CREATE TRIGGER recipes_updated_at BEFORE UPDATE ON public.recipes
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
CREATE TRIGGER recipe_items_updated_at BEFORE UPDATE ON public.recipe_items
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
CREATE TRIGGER competitors_updated_at BEFORE UPDATE ON public.competitors
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
CREATE TRIGGER action_items_updated_at BEFORE UPDATE ON public.action_items
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
