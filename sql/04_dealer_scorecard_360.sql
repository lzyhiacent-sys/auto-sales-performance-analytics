-- "Fiche 360" per dealer over a rolling 12-month window.
-- One row per dealer with every KPI of the scorecard.
WITH params AS (
    SELECT DATE('2025-10-01') AS p_start,
           DATE('2026-09-30') AS p_end,
           DATE('2026-07-01') AS last3_start          -- for stock coverage
),
orders AS (
    SELECT o.*
    FROM fact_orders o, params p
    WHERE o.order_date BETWEEN p.p_start AND p.p_end
),
po AS (
    SELECT dealer_id,
           COUNT(*)                                              AS orders,
           ROUND(SUM(net_price_eur))                             AS order_value_eur,
           SUM(order_status = 'Registered')                      AS orders_registered,
           SUM(order_status = 'Cancelled')                       AS orders_cancelled,
           ROUND(AVG(discount_pct), 4)                           AS avg_discount_pct,
           ROUND(AVG(dealer_margin_eur))                         AS avg_margin_per_unit_eur,
           ROUND(1.0 * SUM(energy = 'BEV') / COUNT(*), 3)        AS bev_share_orders,
           ROUND(1.0 * SUM(channel = 'Fleet') / COUNT(*), 3)     AS fleet_share_orders
    FROM orders
    GROUP BY dealer_id
),
reg AS (
    SELECT o.dealer_id,
           COUNT(*) AS registrations,
           ROUND(AVG(julianday(r.registration_date) - julianday(o.order_date)), 1) AS avg_lead_time_days,
           SUM(r.registration_date >= p.last3_start)                              AS regs_last_3m
    FROM fact_registrations r
    JOIN fact_orders o ON o.order_id = r.order_id
    CROSS JOIN params p
    WHERE r.registration_date BETWEEN p.p_start AND p.p_end
    GROUP BY o.dealer_id
),
tgt AS (
    SELECT t.dealer_id, SUM(t.target_registrations) AS target_registrations
    FROM fact_targets t, params p
    WHERE t.month BETWEEN p.p_start AND p.p_end
    GROUP BY t.dealer_id
),
stk AS (
    SELECT s.dealer_id, SUM(s.stock_units) AS stock_units
    FROM fact_stock s, params p
    WHERE s.snapshot_date = p.p_end
    GROUP BY s.dealer_id
)
SELECT d.dealer_id, d.dealer_name, d.region, d.size_class,
       po.orders, po.order_value_eur,
       reg.registrations, tgt.target_registrations,
       ROUND(1.0 * reg.registrations / tgt.target_registrations, 3)            AS target_achievement,
       -- conversion PO -> registration, on orders that are closed (registered or cancelled)
       ROUND(1.0 * po.orders_registered / (po.orders_registered + po.orders_cancelled), 3)
                                                                               AS po_to_reg_conversion,
       reg.avg_lead_time_days,
       stk.stock_units,
       -- days of stock = stock / average daily registrations over the last 3 months
       ROUND(stk.stock_units / (reg.regs_last_3m / 92.0), 1)                   AS stock_days,
       po.avg_discount_pct, po.avg_margin_per_unit_eur,
       po.bev_share_orders, po.fleet_share_orders
FROM dim_dealer d
JOIN po  ON po.dealer_id  = d.dealer_id
JOIN reg ON reg.dealer_id = d.dealer_id
JOIN tgt ON tgt.dealer_id = d.dealer_id
JOIN stk ON stk.dealer_id = d.dealer_id
ORDER BY d.dealer_id;
