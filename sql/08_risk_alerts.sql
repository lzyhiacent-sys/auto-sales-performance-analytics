-- Business alerts: dealers needing attention on the rolling 12 months.
SELECT dealer_id, dealer_name, region,
       CASE
           WHEN target_achievement < 0.85 THEN 'Registrations below 85% of target'
           WHEN stock_days > 75          THEN 'Stock coverage above 75 days'
           WHEN po_to_reg_conversion < 0.90 THEN 'PO to registration conversion below 90%'
           WHEN avg_discount_pct > 0.075 THEN 'Average discount above 7.5%'
       END AS alert,
       target_achievement, stock_days, po_to_reg_conversion, avg_discount_pct
FROM v_dealer_scorecard
WHERE target_achievement < 0.85
   OR stock_days > 75
   OR po_to_reg_conversion < 0.90
   OR avg_discount_pct > 0.075
ORDER BY target_achievement;
