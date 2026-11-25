# Rebuilding the report in Power BI

This guide rebuilds the dashboard in Power BI Desktop from the CSV files in
`data/raw/`. Same KPIs, same definitions as the SQL queries.

## 1. Load the data

*Home > Get data > Text/CSV*, load the 8 files from `data/raw/`.
In Power Query, check the types:

| Table | Column | Type |
|---|---|---|
| fact_orders | order_date | Date |
| fact_orders | list_price_eur, net_price_eur, dealer_margin_eur, discount_pct | Decimal number |
| fact_registrations | registration_date, delivery_date | Date |
| fact_stock | snapshot_date | Date |
| fact_targets, fact_market | month | Date |

Add a date table (*Modeling > New table*):

```DAX
Calendar =
ADDCOLUMNS (
    CALENDAR ( DATE ( 2024, 10, 1 ), DATE ( 2026, 12, 31 ) ),
    "Year", YEAR ( [Date] ),
    "Month", FORMAT ( [Date], "YYYY-MM" ),
    "MonthStart", DATE ( YEAR ( [Date] ), MONTH ( [Date] ), 1 )
)
```

Mark it as a date table (*Table tools > Mark as date table*).

## 2. Relationships (star schema)

| From (many) | To (one) | Active |
|---|---|---|
| fact_orders[dealer_id] | dim_dealer[dealer_id] | yes |
| fact_orders[model_id] | dim_model[model_id] | yes |
| fact_orders[order_date] | Calendar[Date] | yes |
| fact_registrations[order_id] | fact_orders[order_id] | yes (single direction) |
| fact_registrations[registration_date] | Calendar[Date] | no (used with USERELATIONSHIP) |
| fact_stock[dealer_id] | dim_dealer[dealer_id] | yes |
| fact_stock[snapshot_date] | Calendar[Date] | yes |
| fact_targets[dealer_id] | dim_dealer[dealer_id] | yes |
| fact_targets[month] | Calendar[Date] | yes |

Registrations are dated by their registration date, not by the order date:
the measures below switch the date relationship with `USERELATIONSHIP`.
If Power BI blocks the inactive relationship because of ambiguity, add
`dealer_id` and `model_id` to `fact_registrations` in Power Query (merge with
`fact_orders`) and relate it directly to the dimensions.

## 3. DAX measures

Create an empty table `_Measures` and add:

```DAX
Orders = COUNTROWS ( fact_orders )

Order Value = SUM ( fact_orders[net_price_eur] )

Registrations =
CALCULATE (
    COUNTROWS ( fact_registrations ),
    USERELATIONSHIP ( fact_registrations[registration_date], Calendar[Date] ),
    CROSSFILTER ( fact_orders[order_date], Calendar[Date], NONE )
)

Target = SUM ( fact_targets[target_registrations] )

Target Achievement = DIVIDE ( [Registrations], [Target] )

Orders Registered =
CALCULATE ( [Orders], fact_orders[order_status] = "Registered" )

Orders Cancelled =
CALCULATE ( [Orders], fact_orders[order_status] = "Cancelled" )

PO to Registration Conversion =
DIVIDE ( [Orders Registered], [Orders Registered] + [Orders Cancelled] )

Avg Lead Time (days) =
CALCULATE (
    AVERAGEX (
        fact_registrations,
        DATEDIFF ( RELATED ( fact_orders[order_date] ), fact_registrations[registration_date], DAY )
    ),
    USERELATIONSHIP ( fact_registrations[registration_date], Calendar[Date] ),
    CROSSFILTER ( fact_orders[order_date], Calendar[Date], NONE )
)

Stock Units (period end) =
CALCULATE ( SUM ( fact_stock[stock_units] ), LASTDATE ( fact_stock[snapshot_date] ) )

Registrations Last 3M =
CALCULATE ( [Registrations], DATESINPERIOD ( Calendar[Date], MAX ( Calendar[Date] ), -3, MONTH ) )

Stock Coverage (days) = DIVIDE ( [Stock Units (period end)], [Registrations Last 3M] / 92 )

Avg Discount % = AVERAGE ( fact_orders[discount_pct] )

Margin per Unit = AVERAGE ( fact_orders[dealer_margin_eur] )

BEV Share = DIVIDE ( CALCULATE ( [Orders], fact_orders[energy] = "BEV" ), [Orders] )

Fleet Share = DIVIDE ( CALCULATE ( [Orders], fact_orders[channel] = "Fleet" ), [Orders] )
```

### Network average and quartiles

```DAX
Network Avg Achievement =
AVERAGEX ( ALL ( dim_dealer ), [Target Achievement] )

Gap vs Network = [Target Achievement] - [Network Avg Achievement]

Quartile =
VAR v = [Target Achievement]
VAR q1 = PERCENTILEX.INC ( ALL ( dim_dealer ), [Target Achievement], 0.75 )
VAR q2 = PERCENTILEX.INC ( ALL ( dim_dealer ), [Target Achievement], 0.50 )
VAR q3 = PERCENTILEX.INC ( ALL ( dim_dealer ), [Target Achievement], 0.25 )
RETURN
    SWITCH ( TRUE (), v >= q1, "Q1", v >= q2, "Q2", v >= q3, "Q3", "Q4" )

Classification =
SWITCH ( [Quartile], "Q1", "Outperforming", "Q4", "Underperforming", "In line" )
```

### Market share

Add `segment` to the brand registrations through `dim_model`, then:

```DAX
Market Registrations = SUM ( fact_market[market_registrations] )
Market Share = DIVIDE ( [Registrations], [Market Registrations] )
```

## 4. Report pages

| Page | Visuals |
|---|---|
| **Overview** | Slicers: period, region, channel. Cards: Orders, Registrations, Target Achievement, PO to Registration Conversion, Avg Lead Time, Stock Coverage, Avg Discount %, BEV Share. Line chart: Orders, Registrations, Target by month. Stacked bar: Registrations by model and energy. |
| **Dealer benchmark** | Bar chart: Target Achievement by dealer, sorted, with a constant line at Network Avg Achievement. Table: dealer, region, Quartile, KPIs, conditional formatting on Quartile. |
| **Fiche 360°** | Dealer slicer (single select). Cards for every KPI next to its network average. Line chart of the dealer vs target. Mix by model and energy. |
| **Market & alerts** | Market Share by segment and month. Table of dealers with alerts (achievement < 85 %, stock > 75 days, conversion < 90 %, discount > 7.5 %). |

Use a drill-through from the benchmark page to the Fiche 360° page on `dealer_id`.

## 5. Check your numbers

For the rolling 12 months (Oct 2025 – Sep 2026, all regions), your cards should
match `outputs/03_monthly_po_vs_registrations.csv` and
`outputs/04_dealer_scorecard_360.csv`.
