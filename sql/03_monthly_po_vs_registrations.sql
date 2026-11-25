-- Monthly order intake (PO) vs registrations vs target, network level.
WITH months AS (
    SELECT DISTINCT month FROM fact_targets
),
po AS (
    SELECT date(order_date, 'start of month') AS month,
           COUNT(*)                            AS orders,
           SUM(net_price_eur)                  AS order_value_eur
    FROM fact_orders
    GROUP BY 1
),
reg AS (
    SELECT date(registration_date, 'start of month') AS month,
           COUNT(*)                                   AS registrations
    FROM fact_registrations
    GROUP BY 1
),
tgt AS (
    SELECT month, SUM(target_registrations) AS target_registrations
    FROM fact_targets
    GROUP BY 1
)
SELECT m.month,
       COALESCE(po.orders, 0)              AS orders,
       ROUND(COALESCE(po.order_value_eur, 0)) AS order_value_eur,
       COALESCE(reg.registrations, 0)      AS registrations,
       tgt.target_registrations,
       ROUND(1.0 * COALESCE(reg.registrations, 0) / tgt.target_registrations, 3) AS target_achievement
FROM months m
LEFT JOIN po  ON po.month  = m.month
LEFT JOIN reg ON reg.month = m.month
LEFT JOIN tgt ON tgt.month = m.month
ORDER BY m.month;
