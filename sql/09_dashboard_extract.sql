-- Dealer x month extract that feeds the dashboard (filters re-aggregate it).
WITH months AS (
    SELECT month, dealer_id, target_registrations FROM fact_targets
),
po AS (
    SELECT dealer_id, date(order_date, 'start of month') AS month,
           COUNT(*)                         AS orders,
           SUM(net_price_eur)               AS order_value_eur,
           SUM(order_status = 'Registered') AS orders_registered,
           SUM(order_status = 'Cancelled')  AS orders_cancelled,
           SUM(discount_pct)                AS discount_sum,
           SUM(dealer_margin_eur)           AS margin_sum,
           SUM(energy = 'BEV')              AS bev_orders
    FROM fact_orders
    GROUP BY 1, 2
),
reg AS (
    SELECT o.dealer_id, date(r.registration_date, 'start of month') AS month,
           COUNT(*) AS registrations,
           SUM(julianday(r.registration_date) - julianday(o.order_date)) AS lead_days_sum
    FROM fact_registrations r
    JOIN fact_orders o ON o.order_id = r.order_id
    GROUP BY 1, 2
),
stk AS (
    SELECT dealer_id, date(snapshot_date, 'start of month') AS month,
           SUM(stock_units) AS stock_units
    FROM fact_stock
    GROUP BY 1, 2
)
SELECT m.dealer_id, m.month,
       COALESCE(po.orders, 0) AS orders,
       ROUND(COALESCE(po.order_value_eur, 0)) AS order_value_eur,
       COALESCE(po.orders_registered, 0) AS orders_registered,
       COALESCE(po.orders_cancelled, 0)  AS orders_cancelled,
       ROUND(COALESCE(po.discount_sum, 0), 4) AS discount_sum,
       ROUND(COALESCE(po.margin_sum, 0)) AS margin_sum,
       COALESCE(po.bev_orders, 0) AS bev_orders,
       COALESCE(reg.registrations, 0) AS registrations,
       ROUND(COALESCE(reg.lead_days_sum, 0)) AS lead_days_sum,
       m.target_registrations,
       COALESCE(stk.stock_units, 0) AS stock_units
FROM months m
LEFT JOIN po  ON po.dealer_id  = m.dealer_id AND po.month  = m.month
LEFT JOIN reg ON reg.dealer_id = m.dealer_id AND reg.month = m.month
LEFT JOIN stk ON stk.dealer_id = m.dealer_id AND stk.month = m.month
ORDER BY m.dealer_id, m.month;
