-- ============================================================
-- Lab Operations Analysis | SQLite | synthetic data (not real)
-- Tables: orders, tests, analyzers, patients
-- TAT = turnaround time = resulted_at - collected_at (minutes)
-- ============================================================

-- Q1 [Basic] Total orders and critical results per section
SELECT t.section, COUNT(*) AS orders, SUM(o.is_critical) AS critical_results
FROM orders o JOIN tests t ON t.test_id = o.test_id
GROUP BY t.section
ORDER BY orders DESC;

-- Q2 [Basic] Workload per analyzer (volume + share of total)
SELECT a.analyzer_name, COUNT(*) AS orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_total
FROM orders o JOIN analyzers a ON a.analyzer_id = o.analyzer_id
GROUP BY a.analyzer_name
ORDER BY orders DESC;

-- Q3 [Intermediate] Average TAT per test vs its target
SELECT t.test_name, t.target_tat_min,
       ROUND(AVG((julianday(o.resulted_at) - julianday(o.collected_at)) * 1440), 1) AS avg_tat_min
FROM orders o JOIN tests t ON t.test_id = o.test_id
GROUP BY t.test_id
ORDER BY avg_tat_min - t.target_tat_min DESC;

-- Q4 [Intermediate] % of orders that missed the TAT target, per test
SELECT t.test_name,
       ROUND(100.0 * SUM(CASE WHEN (julianday(o.resulted_at) - julianday(o.collected_at)) * 1440 > t.target_tat_min
                              THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_missed_target
FROM orders o JOIN tests t ON t.test_id = o.test_id
GROUP BY t.test_id
ORDER BY pct_missed_target DESC;

-- Q5 [Intermediate] Repeat rate per analyzer (which one wastes the most reagent?)
SELECT a.analyzer_name, COUNT(*) AS orders, SUM(o.is_repeated) AS repeats,
       ROUND(100.0 * SUM(o.is_repeated) / COUNT(*), 2) AS repeat_rate_pct
FROM orders o JOIN analyzers a ON a.analyzer_id = o.analyzer_id
GROUP BY a.analyzer_name
ORDER BY repeat_rate_pct DESC;

-- Q6 [Intermediate] Orders and critical rate by shift
SELECT shift, COUNT(*) AS orders,
       ROUND(100.0 * SUM(is_critical) / COUNT(*), 2) AS critical_rate_pct
FROM orders
GROUP BY shift;

-- Q7 [Joins x3] Test volume by patient ward (ICU / CCU / Operations / OPD / Ward)
SELECT p.ward, t.section, COUNT(*) AS orders
FROM orders o
JOIN patients p ON p.patient_id = o.patient_id
JOIN tests t    ON t.test_id    = o.test_id
GROUP BY p.ward, t.section
ORDER BY p.ward, orders DESC;

-- Q8 [CTE] Monthly trend with month-over-month change
WITH monthly AS (
  SELECT strftime('%Y-%m', collected_at) AS month, COUNT(*) AS orders
  FROM orders GROUP BY month
)
SELECT month, orders,
       LAG(orders) OVER (ORDER BY month) AS prev_month,
       ROUND(100.0 * (orders - LAG(orders) OVER (ORDER BY month)) / LAG(orders) OVER (ORDER BY month), 1) AS mom_change_pct
FROM monthly;

-- Q9 [Window] Rank analyzers inside each section by average processing time
WITH proc AS (
  SELECT a.section, a.analyzer_name,
         AVG((julianday(o.resulted_at) - julianday(o.received_at)) * 1440) AS avg_proc_min
  FROM orders o JOIN analyzers a ON a.analyzer_id = o.analyzer_id
  GROUP BY a.analyzer_id
)
SELECT section, analyzer_name, ROUND(avg_proc_min, 1) AS avg_proc_min,
       RANK() OVER (PARTITION BY section ORDER BY avg_proc_min DESC) AS slowest_rank
FROM proc;

-- Q10 [Window] Busiest hours of the day (peak workload) with running share
WITH hourly AS (
  SELECT CAST(strftime('%H', collected_at) AS INTEGER) AS hr, COUNT(*) AS orders
  FROM orders GROUP BY hr
)
SELECT hr, orders,
       ROUND(100.0 * SUM(orders) OVER (ORDER BY hr) / SUM(orders) OVER (), 1) AS cumulative_pct
FROM hourly ORDER BY hr;

-- Q11 [Advanced] Slowest 5% of orders per test (approx. 95th percentile TAT)
WITH tat AS (
  SELECT o.test_id,
         (julianday(o.resulted_at) - julianday(o.collected_at)) * 1440 AS tat_min,
         NTILE(20) OVER (PARTITION BY o.test_id
                         ORDER BY (julianday(o.resulted_at) - julianday(o.collected_at))) AS bucket
  FROM orders o
)
SELECT t.test_name, ROUND(MIN(tat_min), 1) AS p95_tat_min
FROM tat JOIN tests t ON t.test_id = tat.test_id
WHERE bucket = 20
GROUP BY t.test_id
ORDER BY p95_tat_min DESC;

-- Q12 [Advanced] Final insight: analyzer x test combos where B-analyzers are slower than their A twin
WITH x AS (
  SELECT a.section, a.analyzer_name, o.test_id,
         AVG((julianday(o.resulted_at) - julianday(o.received_at)) * 1440) AS avg_proc
  FROM orders o JOIN analyzers a ON a.analyzer_id = o.analyzer_id
  WHERE a.section IN ('Biochemistry','Hematology','Immunology')
  GROUP BY a.analyzer_id, o.test_id
)
SELECT t.test_name, b.analyzer_name AS slower, a.analyzer_name AS faster,
       ROUND(b.avg_proc - a.avg_proc, 1) AS extra_min
FROM x a
JOIN x b ON a.test_id = b.test_id AND a.section = b.section AND a.analyzer_name < b.analyzer_name
JOIN tests t ON t.test_id = a.test_id
WHERE b.avg_proc > a.avg_proc
ORDER BY extra_min DESC
LIMIT 10;
