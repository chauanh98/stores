---
name: fifo-revenue-audit
description: Audits FIFO inventory cost calculation, daily revenue metrics, invoice parsing, and profit reporting logic.
---

# FIFO Inventory & Revenue Audit Workflow

Use this skill when modifying or debugging inventory cost calculations, daily revenue reports, or Excel invoice imports.

## 1. Domain Business Rules Reference
- Check project documents:
  - `FIFO_EXAMPLE.md`
  - `DEBUG_REVENUE.md`
  - `FIX_SINGLE_DAY_CALCULATION.md`
  - `REVENUE_FIX_EXPLANATION.md`

---

## 2. Core FIFO Audit Steps

### A. Batch Tracking Integrity
1. Verify that each inventory batch retains:
   - `importDate` / `timestamp`
   - `initialQuantity`
   - `remainingQuantity`
   - `unitCost` (Giá vốn nhập)
2. Ensure selling deductions consume batches strictly in order of **oldest batch first (FIFO)**.

### B. Daily Revenue & Profit Formula
$$\text{Profit} = \text{Selling Price} - \text{FIFO Cost of Goods Sold (COGS)}$$

Check that:
- [ ] Invoices with discounts/returns adjust the final revenue calculation accurately.
- [ ] Multi-day date filters (start of day `00:00:00` to end of day `23:59:59`) correctly capture single-day vs date-range transactions without timezone clipping.
- [ ] Floating point values for currency/quantities use precise rounding or integer cents/đồng where applicable.

---

## 3. Unit Test Verification
Run revenue calculation test suite:
```bash
flutter test test/domain/
```
