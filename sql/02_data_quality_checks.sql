-- Data quality: every check should return 0 rows / 0 issues.
-- Run before any reporting so KPIs are built on consistent data.

SELECT 'registered orders without a registration' AS check_name, COUNT(*) AS issues
FROM fact_orders o
LEFT JOIN fact_registrations r ON r.order_id = o.order_id
WHERE o.order_status = 'Registered' AND r.order_id IS NULL
UNION ALL
SELECT 'registrations on cancelled or open orders', COUNT(*)
FROM fact_registrations r
JOIN fact_orders o ON o.order_id = r.order_id
WHERE o.order_status <> 'Registered'
UNION ALL
SELECT 'registration before order date', COUNT(*)
FROM fact_registrations r
JOIN fact_orders o ON o.order_id = r.order_id
WHERE r.registration_date < o.order_date
UNION ALL
SELECT 'model x energy not in reference list', COUNT(*)
FROM fact_orders o
LEFT JOIN dim_model_energy me ON me.model_id = o.model_id AND me.energy = o.energy
WHERE me.model_id IS NULL
UNION ALL
SELECT 'net price inconsistent with list price and discount', COUNT(*)
FROM fact_orders
WHERE ABS(net_price_eur - list_price_eur * (1 - discount_pct)) > 1;
