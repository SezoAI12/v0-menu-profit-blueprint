# MenuProfit Test Plan - Data Layer

## TP-1: Schema Integrity Tests

| ID | Test | Expected | Status |
|----|------|----------|--------|
| TP-1.1 | All 18 tables exist in public schema | profiles, tenants, tenant_memberships, tenant_subscriptions, suppliers, ingredients, ingredient_price_history, overhead_monthly, recipe_categories, recipes, recipe_items, import_jobs, sales_data, competitors, competitor_prices, action_items, audit_logs | - |
| TP-1.2 | RLS enabled on ALL tables | `SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname='public'` all show `true` | - |
| TP-1.3 | All tables have tenant_id (except profiles) | Every business table has NOT NULL tenant_id FK to tenants | - |
| TP-1.4 | UUID primary keys on all tables | All `id` columns are UUID type | - |
| TP-1.5 | Enums exist | tenant_role, subscription_plan, subscription_status, ingredient_unit, recipe_status, import_job_status, action_status, action_priority | - |

## TP-2: Tenant Isolation Tests

| ID | Test | Expected | Status |
|----|------|----------|--------|
| TP-2.1 | User A in Tenant 1 cannot read Tenant 2 suppliers | SELECT returns 0 rows | - |
| TP-2.2 | User A in Tenant 1 cannot INSERT into Tenant 2 | INSERT violates RLS policy | - |
| TP-2.3 | User A in Tenant 1 cannot UPDATE Tenant 2 records | UPDATE affects 0 rows | - |
| TP-2.4 | User A in Tenant 1 cannot DELETE Tenant 2 records | DELETE affects 0 rows | - |
| TP-2.5 | Staff role cannot INSERT (only Owner/Manager can) | INSERT violates RLS policy for staff | - |
| TP-2.6 | Manager can INSERT/UPDATE but cannot access audit_logs | SELECT on audit_logs returns 0 rows | - |
| TP-2.7 | Owner can read audit_logs for their tenant only | SELECT returns only own tenant logs | - |
| TP-2.8 | User with multi-tenant membership sees correct data per tenant | Different data per tenant context | - |

## TP-3: Role Hierarchy Tests

| ID | Test | Expected | Status |
|----|------|----------|--------|
| TP-3.1 | Owner can perform all CRUD operations | All succeed | - |
| TP-3.2 | Manager can CRUD suppliers, ingredients, recipes, overhead | All succeed | - |
| TP-3.3 | Manager can manage team members (invite) | Per plan limits | - |
| TP-3.4 | Staff can only SELECT (read) | INSERT/UPDATE/DELETE fail | - |
| TP-3.5 | Staff cannot access audit_logs | SELECT returns 0 rows | - |
| TP-3.6 | Role check: assertRole('manager') fails for staff | Error thrown | - |
| TP-3.7 | Role check: assertRole('staff') succeeds for owner | No error | - |

## TP-4: Audit Log Tests

| ID | Test | Expected | Status |
|----|------|----------|--------|
| TP-4.1 | INSERT on suppliers creates audit_log with action='create' | Log entry exists with after_data | - |
| TP-4.2 | UPDATE on suppliers creates audit_log with action='update' | Log entry has both before_data and after_data | - |
| TP-4.3 | DELETE on suppliers creates audit_log with action='delete' | Log entry has before_data, null after_data | - |
| TP-4.4 | audit_logs cannot be UPDATED | Trigger raises exception | - |
| TP-4.5 | audit_logs cannot be DELETED | Trigger raises exception | - |
| TP-4.6 | Audit log captures correct tenant_id | Matches source record | - |
| TP-4.7 | Audit log captures correct user_id | Matches auth.uid() | - |
| TP-4.8 | Audit trigger fires on ALL 14 audited tables | Each table has audit records after CRUD | - |

## TP-5: Ingredient Price History Tests

| ID | Test | Expected | Status |
|----|------|----------|--------|
| TP-5.1 | INSERT new ingredient creates price history entry | History row with initial price | - |
| TP-5.2 | UPDATE ingredient price creates NEW history entry | Old history preserved, new row added | - |
| TP-5.3 | Price history is append-only (no UPDATE/DELETE) | Only INSERT policy exists | - |
| TP-5.4 | Multiple price updates create multiple history rows | All rows preserved in order | - |
| TP-5.5 | History effective_date defaults to current date | Correct date on auto-created rows | - |

## TP-6: Calculation Function Tests

| ID | Test | Expected | Status |
|----|------|----------|--------|
| TP-6.1 | Effective cost: price=40, yield=80 | 50.0000 (40/0.8) | - |
| TP-6.2 | Effective cost: price=40, yield=100 | 40.0000 (no adjustment) | - |
| TP-6.3 | Effective cost: price=40, yield=0 | 40.0000 (fallback, no division by zero) | - |
| TP-6.4 | Effective cost: price=40, yield=null | 40.0000 (fallback) | - |
| TP-6.5 | Food cost: 2 items, chicken(40SAR,80%,200g/1000) + rice(8SAR,95%,300g/1000) | 50*0.2 + 8.4211*0.3 = 12.5263 | - |
| TP-6.6 | Food cost: empty recipe (no items) | 0 | - |
| TP-6.7 | Overhead per plate: total=50000, plates=2000 | 25.0000 | - |
| TP-6.8 | Overhead per plate: plates=0 | 0 (fallback) | - |
| TP-6.9 | True cost: food=12.53, overhead=25 | 37.5300 | - |
| TP-6.10 | Margin%: SP=80, TC=37.53 | 53.09% ((80-37.53)/80*100) | - |
| TP-6.11 | Margin%: SP=0, TC=37.53 | NULL (division by zero guard) | - |
| TP-6.12 | Contribution margin: SP=80, TC=37.53 | 42.47 | - |
| TP-6.13 | Suggested SP: TC=37.53, target=60% | 93.83 (37.53/(1-0.6)) | - |
| TP-6.14 | Suggested SP: target=100% | NULL (impossible margin) | - |
| TP-6.15 | Full recipe analysis returns all fields correctly | Composite check | - |
| TP-6.16 | Batch analysis returns correct data for all tenant recipes | All recipes included with correct calcs | - |
| TP-6.17 | Latest overhead fallback works when no overhead data | Returns 0 | - |
| TP-6.18 | Latest overhead uses most recent month | Correct month selected | - |

## TP-7: Subscription Plan Limit Tests

| ID | Test | Expected | Status |
|----|------|----------|--------|
| TP-7.1 | Free plan: 26th recipe blocked | check_plan_limit returns allowed=false | - |
| TP-7.2 | Free plan: 51st ingredient blocked | check_plan_limit returns allowed=false | - |
| TP-7.3 | Free plan: 11th supplier blocked | check_plan_limit returns allowed=false | - |
| TP-7.4 | Free plan: 2nd user blocked | check_plan_limit returns allowed=false | - |
| TP-7.5 | Pro plan: 151st recipe blocked | check_plan_limit returns allowed=false | - |
| TP-7.6 | Pro plan: bulk_import feature allowed | assertFeatureAccess passes | - |
| TP-7.7 | Free plan: bulk_import feature blocked | assertFeatureAccess throws | - |
| TP-7.8 | Free plan: AI suggestions blocked | assertFeatureAccess throws | - |
| TP-7.9 | Elite plan: all features allowed | All checks pass | - |
| TP-7.10 | No subscription defaults to free plan | check_plan_limit uses free limits | - |
| TP-7.11 | Plan limit check returns correct remaining count | remaining = limit - current_count | - |

## TP-8: Overhead Calculation Tests

| ID | Test | Expected | Status |
|----|------|----------|--------|
| TP-8.1 | overhead_per_plate auto-calculated on INSERT | computed = total / baseline_plates | - |
| TP-8.2 | overhead_per_plate auto-calculated on UPDATE | recomputed on change | - |
| TP-8.3 | total_overhead auto-calculated from components | sum of rent+salaries+utilities+marketing+other | - |
| TP-8.4 | Unique constraint on tenant_id + year + month | Duplicate month rejected | - |
| TP-8.5 | baseline_plates must be > 0 | CHECK constraint enforced | - |

## TP-9: Sales Data Tests (Volume Only)

| ID | Test | Expected | Status |
|----|------|----------|--------|
| TP-9.1 | Sales data has NO revenue/price columns | Schema inspection confirms | - |
| TP-9.2 | quantity_sold must be > 0 | CHECK constraint enforced | - |
| TP-9.3 | Sales data respects tenant isolation | Cross-tenant reads blocked | - |
| TP-9.4 | Only managers+ can insert sales data | Staff insert blocked | - |

## TP-10: Data Integrity Tests

| ID | Test | Expected | Status |
|----|------|----------|--------|
| TP-10.1 | Deleting a tenant cascades to all child records | All related rows removed | - |
| TP-10.2 | Deleting a supplier nullifies ingredient.supplier_id | SET NULL behavior | - |
| TP-10.3 | Deleting an ingredient cascades recipe_items | Related recipe_items removed | - |
| TP-10.4 | Deleting a recipe cascades recipe_items and sales_data | Related rows removed | - |
| TP-10.5 | Recipe items reference valid recipes and ingredients | FK constraints enforced | - |
| TP-10.6 | Ingredient price must be >= 0 | CHECK constraint | - |
| TP-10.7 | Yield percent must be 0-100 | CHECK constraint | - |
| TP-10.8 | Selling price must be >= 0 | CHECK constraint | - |

---

## Test Execution Notes

- All RLS tests require creating test users via Supabase Auth and testing with their JWT tokens
- Calculation tests can be validated both via SQL (`SELECT public.calc_*()`) and TypeScript unit tests
- Audit log tests should verify the immutability triggers cannot be bypassed
- Plan limit tests should test boundary conditions (exactly at limit, one over)
