-- Brand market share per segment and month (brand registrations / total market).
WITH brand AS (
    SELECT date(r.registration_date, 'start of month') AS month,
           m.segment,
           COUNT(*) AS brand_registrations
    FROM fact_registrations r
    JOIN fact_orders o ON o.order_id = r.order_id
    JOIN dim_model m  ON m.model_id = o.model_id
    GROUP BY 1, 2
)
SELECT b.month, b.segment, b.brand_registrations, mk.market_registrations,
       ROUND(1.0 * b.brand_registrations / mk.market_registrations, 4) AS market_share
FROM brand b
JOIN fact_market mk ON mk.month = b.month AND mk.segment = b.segment
ORDER BY b.month, b.segment;
