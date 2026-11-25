-- Dealer x model x energy registrations and dealer x channel orders, rolling 12 months.
SELECT 'mix' AS kind, o.dealer_id, m.model AS k1, o.energy AS k2, COUNT(*) AS n
FROM fact_registrations r
JOIN fact_orders o ON o.order_id = r.order_id
JOIN dim_model m  ON m.model_id = o.model_id
WHERE r.registration_date BETWEEN '2025-10-01' AND '2026-09-30'
GROUP BY o.dealer_id, m.model, o.energy
UNION ALL
SELECT 'channel', dealer_id, channel, '', COUNT(*)
FROM fact_orders
WHERE order_date BETWEEN '2025-10-01' AND '2026-09-30'
GROUP BY dealer_id, channel;
