-- Quartile policy: rank dealers on target achievement, compare to the
-- network average and classify. Q1 = top 25 %, Q4 = bottom 25 %.
-- Reads the scorecard view created from 04_dealer_scorecard_360.sql.
WITH ranked AS (
    SELECT s.*,
           NTILE(4) OVER (ORDER BY target_achievement DESC) AS quartile,
           AVG(target_achievement) OVER ()                  AS network_avg_achievement
    FROM v_dealer_scorecard s
)
SELECT dealer_id, dealer_name, region,
       target_achievement,
       ROUND(network_avg_achievement, 3)                         AS network_avg_achievement,
       ROUND(target_achievement - network_avg_achievement, 3)    AS gap_vs_network,
       'Q' || quartile                                           AS quartile,
       CASE quartile
            WHEN 1 THEN 'Outperforming'
            WHEN 4 THEN 'Underperforming'
            ELSE 'In line'
       END                                                       AS classification
FROM ranked
ORDER BY target_achievement DESC;
