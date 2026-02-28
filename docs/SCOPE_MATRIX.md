# MenuProfit -- Feature Lock Blueprint & ScopeMatrix v1.0

> Single source of truth. Every module, every boundary, every gate.
> Generated: 2026-02-28 | SRS: v2.0 (Feb 27, 2026)

---

## HARD EXCLUSIONS (globally forbidden)

| ID | Feature | Reason |
|----|---------|--------|
| X-1 | POS Integration | SRS exclusion |
| X-2 | Inventory Management | SRS exclusion |
| X-3 | Accounting / GL | SRS exclusion |
| X-4 | Payroll | SRS exclusion |
| X-5 | Customer Ordering / Reservations | SRS exclusion |
| X-6 | Revenue / Sales Totals / Profit Totals Dashboards | SRS exclusion |
| X-7 | Sales data beyond volume (quantities only) | SRS exclusion |

---

## SUBSCRIPTION PLAN LIMITS (server-side enforced)

| Resource / Gate | Free | Pro | Elite |
|-----------------|------|-----|-------|
| Restaurants (tenants) | 1 | 3 | 10 |
| Recipes per tenant | 25 | 150 | Unlimited |
| Ingredients per tenant | 50 | 300 | Unlimited |
| Suppliers per tenant | 10 | 50 | Unlimited |
| Users per tenant | 1 (Owner only) | 5 | 20 |
| Sales Import | No | Yes | Yes |
| AI Suggestions | No | Basic (5/day) | Full (unlimited) |
| Competition Tracking | No | 3 competitors | Unlimited |
| Reports / Export | Basic PDF | Full PDF + CSV | Full + scheduled |
| Bulk Import (CSV/Excel) | No | Yes | Yes |
| Overhead Management | Basic (single month) | Full history | Full + forecasting |
| Risk Radar | No | Basic alerts | Full alerts + AI |
| API Access | No | No | Yes |
| Audit Log View | No | 30 days | Full history |

---

## MODULE SCOPE MATRIX

### FR-1: Multi-Tenancy & Tenant Isolation

| Attribute | Detail |
|-----------|--------|
| **In-scope** | Tenant (restaurant) CRUD; tenant_id on every row; RLS policies; tenant switching for users with multiple memberships; tenant-scoped queries only |
| **Out-of-scope** | Cross-tenant reporting; tenant merging; white-labeling |
| **Data entities** | `tenants`, `tenant_memberships`, `users` (via auth.users) |
| **UI pages** | Tenant selector (header dropdown), Create Tenant form, Tenant Settings page |
| **Plan gating** | Free=1 tenant, Pro=3, Elite=10 |

### FR-2: User Management & Roles

| Attribute | Detail |
|-----------|--------|
| **In-scope** | Auth (email+password via Supabase Auth); roles Owner/Manager/Staff per tenant; invite flow; role-based access control; profile management |
| **Out-of-scope** | SSO/OAuth; LDAP; external identity providers (unless explicitly requested later) |
| **Data entities** | `auth.users`, `profiles`, `tenant_memberships` (role column) |
| **UI pages** | Login, Sign-up, Sign-up Success, Invite Accept, Team Management (Owner only), Profile Settings |
| **Plan gating** | Free=1 user, Pro=5, Elite=20 per tenant |

### FR-3: Billing & Subscription Management

| Attribute | Detail |
|-----------|--------|
| **In-scope** | Plan assignment per tenant; server-side limit enforcement on every mutating API; plan display; upgrade prompts; usage counters |
| **Out-of-scope** | Stripe/payment processing (managed externally); invoice generation; refunds |
| **Data entities** | `tenant_subscriptions` (plan, period_start, period_end, status) |
| **UI pages** | Subscription Status page, Upgrade Prompt modal, Usage Dashboard |
| **Plan gating** | All plans have this module; limits differ per plan |

### FR-4: Dashboard (Home)

| Attribute | Detail |
|-----------|--------|
| **In-scope** | KPI cards: total recipes, total ingredients, average margin%, highest/lowest margin items, cost alerts count, overhead-per-plate current; recent activity feed; quick actions |
| **Out-of-scope** | Revenue totals; profit totals; sales charts; financial dashboards |
| **Data entities** | Aggregated views from recipes, ingredients, overhead_monthly, audit_logs |
| **UI pages** | `/dashboard` -- single page with KPI cards + activity feed |
| **Plan gating** | Free=basic KPIs, Pro=full KPIs, Elite=full + AI insights |

### FR-5: Overhead Management

| Attribute | Detail |
|-----------|--------|
| **In-scope** | Monthly overhead entry: rent, salaries, utilities, marketing, other; baseline plates/month; computed overhead_per_plate = total_overhead / baseline_plates; historical months; fallback to latest month for calculations |
| **Out-of-scope** | Forecasting (Elite future); payroll integration; accounting GL codes |
| **Data entities** | `overhead_monthly` (tenant_id, month, year, rent, salaries, utilities, marketing, other, baseline_plates, overhead_per_plate, created_by, updated_at) |
| **UI pages** | `/overhead` -- list of months + add/edit form |
| **Plan gating** | Free=current month only, Pro=full history, Elite=full + trends |

### FR-6: Suppliers

| Attribute | Detail |
|-----------|--------|
| **In-scope** | Supplier CRUD: name, contact_name, phone, email, address, notes, is_active; link to ingredients; supplier directory |
| **Out-of-scope** | Purchase orders; supplier portal; automated ordering; payment tracking |
| **Data entities** | `suppliers` (tenant_id, name, contact_name, phone, email, address, notes, is_active) |
| **UI pages** | `/suppliers` -- list + add/edit drawer/dialog |
| **Plan gating** | Free=10, Pro=50, Elite=unlimited |

### FR-7: Ingredients

| Attribute | Detail |
|-----------|--------|
| **In-scope** | Ingredient CRUD: name, category, unit_type, purchase_unit, recipe_unit, unit_conversion_factor, current_price, yield_percent, waste_percent, alert_threshold, supplier_id link; effective_cost = price / (yield% / 100); price history append-only (never overwrite); low-stock/price alerts |
| **Out-of-scope** | Inventory quantities; stock counts; purchase orders; barcode scanning |
| **Data entities** | `ingredients`, `ingredient_price_history` (append-only: ingredient_id, price, effective_date, recorded_by) |
| **UI pages** | `/ingredients` -- list with filters + add/edit form + price history drawer |
| **Plan gating** | Free=50, Pro=300, Elite=unlimited |

### FR-8: Bulk Import (CSV/Excel)

| Attribute | Detail |
|-----------|--------|
| **In-scope** | CSV/Excel upload for ingredients and suppliers; validation preview; error reporting per row; import job logging; duplicate detection |
| **Out-of-scope** | API-based import; automated scheduled imports; import from POS |
| **Data entities** | `import_jobs` (tenant_id, type, file_name, status, total_rows, success_rows, error_rows, error_details_json, created_by, completed_at) |
| **UI pages** | `/import` -- upload + preview + results |
| **Plan gating** | Free=no, Pro=yes, Elite=yes |

### FR-9: Recipes & Recipe Builder

| Attribute | Detail |
|-----------|--------|
| **In-scope** | Recipe CRUD: name, name_ar, category, selling_price, target_margin, is_protected, status (draft/active/archived); recipe items: ingredient link, quantity, unit, unit_conversion; computed fields: food_cost (sum of item costs), true_cost (food_cost + overhead_per_plate), actual_margin% = (selling_price - true_cost) / selling_price, contribution_margin = selling_price - true_cost; recipe duplication; category management |
| **Out-of-scope** | Recipe versioning (defer to future); recipe photos (defer); nutritional info; allergen tracking; prep instructions |
| **Data entities** | `recipe_categories`, `recipes`, `recipe_items` |
| **UI pages** | `/recipes` -- list + `/recipes/[id]` builder page |
| **Plan gating** | Free=25 recipes, Pro=150, Elite=unlimited |

### FR-10: Sales Import (Volume Only)

| Attribute | Detail |
|-----------|--------|
| **In-scope** | Import sales data as quantities only per recipe per period; CSV upload; manual entry; used for popularity ranking and contribution analysis (volume * margin) |
| **Out-of-scope** | Revenue amounts; price per transaction; POS sync; real-time sales; financial reporting |
| **Data entities** | `sales_periods`, `sales_data` (tenant_id, recipe_id, period_id, quantity_sold) |
| **UI pages** | `/sales` -- period list + import/entry form |
| **Plan gating** | Free=no, Pro=yes, Elite=yes |

### FR-11: Competition Tracking

| Attribute | Detail |
|-----------|--------|
| **In-scope** | Competitor CRUD: name, location, notes; competitor menu items: item_name, category, price; price comparison with own recipes; market positioning insights |
| **Out-of-scope** | Automated scraping; real-time monitoring; competitor analytics AI |
| **Data entities** | `competitors`, `competitor_menu_items` |
| **UI pages** | `/competition` -- competitor list + menu item comparison |
| **Plan gating** | Free=no, Pro=3 competitors, Elite=unlimited |

### FR-12: AI Suggestions

| Attribute | Detail |
|-----------|--------|
| **In-scope** | AI-powered pricing suggestions based on cost/margin data; ingredient substitution suggestions; menu optimization tips; all based on tenant's own data only |
| **Out-of-scope** | Market data integration; demand forecasting; automated price changes |
| **Data entities** | `ai_suggestion_log` (tenant_id, type, input_data, suggestion, accepted, created_at) |
| **UI pages** | `/ai` -- suggestions dashboard + per-recipe suggestions in recipe builder |
| **Plan gating** | Free=no, Pro=5/day, Elite=unlimited |

### FR-13: Risk Radar

| Attribute | Detail |
|-----------|--------|
| **In-scope** | Alerts: ingredient price spike (>threshold), margin below target, overhead increase, missing price data; alert list with status (new/acknowledged/resolved); configurable thresholds |
| **Out-of-scope** | Predictive analytics; supply chain risk; weather-based alerts |
| **Data entities** | `risk_alerts` (tenant_id, type, severity, entity_type, entity_id, message, status, created_at, resolved_at, resolved_by) |
| **UI pages** | `/alerts` -- alert list + configuration |
| **Plan gating** | Free=no, Pro=basic, Elite=full + AI-enhanced |

### FR-14: Actions & Recommendations

| Attribute | Detail |
|-----------|--------|
| **In-scope** | Actionable items derived from alerts and analysis; action queue with status tracking; priority ranking; linked to source alert/recipe/ingredient |
| **Out-of-scope** | Automated execution of actions; workflow automation |
| **Data entities** | `action_items` (tenant_id, source_type, source_id, title, description, priority, status, assigned_to, due_date) |
| **UI pages** | `/actions` -- action queue + detail view |
| **Plan gating** | Free=no, Pro=basic, Elite=full |

### FR-15: Reports & Export

| Attribute | Detail |
|-----------|--------|
| **In-scope** | Menu cost analysis report; margin analysis report; ingredient cost report; overhead trend report; export to PDF and CSV; report history |
| **Out-of-scope** | Revenue reports; profit/loss; financial statements; scheduled email reports (Elite future) |
| **Data entities** | `report_jobs` (tenant_id, type, parameters_json, status, file_url, created_by, created_at) |
| **UI pages** | `/reports` -- report selector + generated report view + download |
| **Plan gating** | Free=basic PDF, Pro=full PDF+CSV, Elite=full+scheduled |

### FR-16: Settings

| Attribute | Detail |
|-----------|--------|
| **In-scope** | Tenant settings: name, currency, language preference, timezone; user profile settings; notification preferences; data management (export all data) |
| **Out-of-scope** | Custom branding; domain settings; API key management (Elite future) |
| **Data entities** | `tenant_settings`, `user_preferences` |
| **UI pages** | `/settings` -- tabbed settings page |
| **Plan gating** | All plans |

---

## COST FORMULA REFERENCE (immutable)

```
Effective Ingredient Cost = Purchase Price / (Yield% / 100)

Food Cost (per recipe) = SUM(ingredient_effective_cost * quantity_in_recipe_units)
  where quantity_in_recipe_units accounts for unit_conversion_factor

Overhead Per Plate = Total Monthly Overhead / Baseline Plates Per Month
  Total Monthly Overhead = rent + salaries + utilities + marketing + other

True Cost = Food Cost + Overhead Per Plate

Margin % = (Selling Price - True Cost) / Selling Price * 100

Contribution Margin = Selling Price - True Cost
```

---

## ROLE PERMISSIONS MATRIX

| Action | Owner | Manager | Staff |
|--------|-------|---------|-------|
| Manage Team / Invite Users | Yes | No | No |
| Manage Subscription | Yes | No | No |
| Manage Tenant Settings | Yes | No | No |
| CRUD Overhead | Yes | Yes | No |
| CRUD Suppliers | Yes | Yes | No |
| CRUD Ingredients | Yes | Yes | View only |
| CRUD Recipes | Yes | Yes | View only |
| Import Data | Yes | Yes | No |
| View Reports | Yes | Yes | Yes |
| Export Reports | Yes | Yes | No |
| CRUD Competition | Yes | Yes | No |
| View AI Suggestions | Yes | Yes | Yes |
| Manage Alerts | Yes | Yes | Acknowledge only |
| View Dashboard | Yes | Yes | Yes |
| View Audit Log | Yes | No | No |

---

## AUDIT LOG REQUIREMENTS

- Table: `audit_logs`
- Immutable (INSERT only, no UPDATE/DELETE)
- Fields: id, tenant_id, table_name, record_id, action (create/update/delete), before_data (JSONB), after_data (JSONB), user_id, ip_address, created_at
- Triggered on ALL CRUD operations across ALL tenant-scoped tables
- Retained per plan: Free=none visible, Pro=30 days, Elite=full history

---

## UI/UX REQUIREMENTS (cross-cutting)

- Arabic RTL-first with instant AR/EN toggle (no reload)
- Every screen: loading state, empty state, error state
- All errors logged (never silently fail)
- Responsive: mobile-first, works on tablet and desktop
- Accessibility: ARIA labels, keyboard navigation, screen reader support

---

## DATA FLOW INVARIANTS

1. `tenant_id` is REQUIRED on every table except `auth.users` and `profiles`
2. No query may ever omit tenant_id filter
3. RLS policies enforce tenant isolation at database level
4. All mutations go through server actions / API routes (no direct client DB access)
5. Subscription limits checked server-side before every INSERT
6. Price history is append-only -- UPDATE and DELETE are forbidden on `ingredient_price_history`
