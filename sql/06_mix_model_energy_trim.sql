-- Registration mix by model x energy x trim and by channel, rolling 12 months.
WITH reg AS (
    SELECT o.model_id, o.energy, o.trim, o.channel
    FROM fact_registrations r
    JOIN fact_orders o ON o.order_id = r.order_id
    WHERE r.registration_date BETWEEN '2025-10-01' AND '2026-09-30'
)
SELECT m.model, m.segment, reg.energy, reg.trim, reg.channel,
       COUNT(*)                                            AS registrations,
       ROUND(1.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 4)    AS share_of_total,
       ROUND(1.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY m.model), 4) AS share_within_model
FROM reg
JOIN dim_model m ON m.model_id = reg.model_id
GROUP BY m.model, m.segment, reg.energy, reg.trim, reg.channel
ORDER BY m.model, registrations DESC;
