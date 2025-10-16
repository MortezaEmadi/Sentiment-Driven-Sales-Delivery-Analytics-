USE olist;
GO

DECLARE @window_start date = '2016-10-01';
DECLARE @window_end   date = '2018-09-01';  -- exclusive, gives Oct-2016 .. Aug-2018
DECLARE @brl_per_usd  decimal(10,4) = 5.2000; -- 20,000,000 BRL ≈ 3,846,232 USD


-- B1) Delivered orders coverage inside the window
SELECT 
  MIN(o.purchase_ts) AS first_purchase,
  MAX(o.purchase_ts) AS last_purchase,
  COUNT(DISTINCT o.order_id) AS delivered_orders_in_window
FROM dbo.v_orders o
WHERE o.order_status = 'delivered'
  AND o.purchase_ts >= @window_start
  AND o.purchase_ts <  @window_end;

-- B2) Total sales (items + freight) in BRL and USD
SELECT 
  CAST(SUM(r.revenue_brl) AS decimal(18,2))                                AS total_sales_brl,
  CAST(SUM(r.revenue_brl) / NULLIF(@brl_per_usd,0) AS decimal(18,2))       AS total_sales_usd,
  @brl_per_usd                                                               AS fx_brl_per_usd_used
FROM dbo.v_orders o
JOIN dbo.v_order_revenue r ON r.order_id = o.order_id
WHERE o.order_status = 'delivered'
  AND o.purchase_ts >= @window_start
  AND o.purchase_ts <  @window_end;
  ------------------------------------------------------------------------------
  ---
----DECLARE @window_start date = '2016-10-01';
----DECLARE @window_end   date = '2018-09-01';  
----DECLARE @brl_per_usd  decimal(10,4) = 5.2000;

SELECT 
  MIN(o.purchase_ts) AS first_purchase,
  MAX(o.purchase_ts) AS last_purchase,
  COUNT(DISTINCT o.order_id) AS delivered_orders_in_window
FROM dbo.v_orders o
WHERE o.order_status = 'delivered'
  AND o.purchase_ts >= @window_start
  AND o.purchase_ts <  @window_end;

-- total sales in BRL and USD
SELECT 
  CAST(SUM(r.revenue_brl) AS decimal(18,2))                                AS total_sales_brl,
  CAST(SUM(r.revenue_brl) / NULLIF(@brl_per_usd,0) AS decimal(18,2))       AS total_sales_usd,
  @brl_per_usd                                                               AS fx_brl_per_usd_used
FROM dbo.v_orders o
JOIN dbo.v_order_revenue r ON r.order_id = o.order_id
WHERE o.order_status = 'delivered'
  AND o.purchase_ts >= @window_start
  AND o.purchase_ts <  @window_end;
  ------------------------------------------
  ---------Yearly snapshots of sales, customers, orders + top-3 categories)
--DECLARE @window_start date = '2016-10-01';
--DECLARE @window_end   date = '2018-09-01';  
--DECLARE @brl_per_usd  decimal(10,4) = 5.2000; 

  ;WITH y AS (
  SELECT 
    YEAR(o.purchase_ts) AS [year],
    SUM(r.revenue_brl)  AS sales_brl,
    COUNT(DISTINCT o.customer_id) AS customers,
    COUNT(DISTINCT o.order_id)    AS orders
  FROM dbo.v_orders o
  JOIN dbo.v_order_revenue r ON r.order_id = o.order_id
  WHERE o.order_status='delivered'
    AND o.purchase_ts >= '2016-01-01' AND o.purchase_ts < '2019-01-01'
  GROUP BY YEAR(o.purchase_ts)
),
cat AS (
  SELECT 
    YEAR(o.purchase_ts) AS [year],
    pr.product_category_name,
    SUM(oi.price + oi.freight_value) AS sales_brl
  FROM dbo.v_orders o
  JOIN dbo.v_order_items oi ON oi.order_id = o.order_id
  JOIN dbo.v_products     pr ON pr.product_id = oi.product_id
  WHERE o.order_status='delivered'
    AND o.purchase_ts >= '2016-01-01' AND o.purchase_ts < '2019-01-01'
  GROUP BY YEAR(o.purchase_ts), pr.product_category_name
),
cat_top AS (
  SELECT [year], product_category_name, sales_brl,
         ROW_NUMBER() OVER (PARTITION BY [year] ORDER BY sales_brl DESC) AS rn
  FROM cat
)
SELECT 
  y.[year],
  CAST(y.sales_brl AS decimal(18,2)) AS sales_brl,
  CAST(y.sales_brl / NULLIF(@brl_per_usd,0) AS decimal(18,2)) AS sales_usd,
  y.customers,
  y.orders,
  -- ordered top-3 list
  (
    SELECT STRING_AGG(product_category_name, ', ') 
           WITHIN GROUP (ORDER BY sales_brl DESC)
    FROM cat_top t
    WHERE t.[year]=y.[year] AND t.rn<=3
  ) AS top3_categories_by_revenue
FROM y
ORDER BY y.[year];

-----------------------------------------------------------------------------
---
--DECLARE @window_start date = '2016-10-01';
--DECLARE @window_end   date = '2018-09-01';  
--DECLARE @brl_per_usd  decimal(10,4) = 5.2000; 

-- Revenue by quarter 
SELECT 
  FORMAT(DATEFROMPARTS(YEAR(o.purchase_ts), (DATEPART(QUARTER, o.purchase_ts)-1)*3+1, 1), 'yyyy-\\Qq') AS year_quarter,
  CAST(SUM(r.revenue_brl) AS decimal(18,2)) AS sales_brl,
  COUNT(DISTINCT o.order_id) AS orders
FROM dbo.v_orders o
JOIN dbo.v_order_revenue r ON r.order_id = o.order_id
WHERE o.order_status='delivered'
  AND o.purchase_ts >= '2016-01-01' AND o.purchase_ts < '2019-01-01'
GROUP BY YEAR(o.purchase_ts), DATEPART(QUARTER, o.purchase_ts)
ORDER BY MIN(o.purchase_ts);

--2018 YTD (Jan..Aug) vs full 2017
WITH y2017 AS (
  SELECT SUM(r.revenue_brl) AS sales_brl
  FROM dbo.v_orders o
  JOIN dbo.v_order_revenue r ON r.order_id=o.order_id
  WHERE o.order_status='delivered'
    AND o.purchase_ts >= '2017-01-01' AND o.purchase_ts < '2018-01-01'
),
y2018_ytd AS (
  SELECT SUM(r.revenue_brl) AS sales_brl
  FROM dbo.v_orders o
  JOIN dbo.v_order_revenue r ON r.order_id=o.order_id
  WHERE o.order_status='delivered'
    AND o.purchase_ts >= '2018-01-01' AND o.purchase_ts < '2018-09-01'
)
SELECT 
  CAST(y2017.sales_brl AS decimal(18,2))         AS sales_2017_brl,
  CAST(y2018_ytd.sales_brl AS decimal(18,2))     AS sales_2018_ytd_brl,
  CAST( ( (y2018_ytd.sales_brl - y2017.sales_brl) / y2017.sales_brl ) * 100.0 
        AS decimal(9,2) )                        AS pct_change_vs_2017
FROM y2017 CROSS JOIN y2018_ytd;
----------------------------------------------------------
--Part E: Payment method shares (orders and revenue)
-- E1) Share of orders by primary payment type 
--DECLARE @window_start date = '2016-10-01';
--DECLARE @window_end   date = '2018-09-01';  -- exclusive, gives Oct-2016 .. Aug-2018
--DECLARE @brl_per_usd  decimal(10,4) = 5.2000; -- 20,000,000 BRL ≈ 3,846,232 USD

SELECT 
  pp.primary_payment_type,
  COUNT(*) AS orders,
  CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS decimal(5,2)) AS pct_orders
FROM dbo.v_orders o
JOIN dbo.v_payments pp ON pp.order_id = o.order_id
WHERE o.order_status='delivered'
  AND o.purchase_ts >= '2016-01-01' AND o.purchase_ts < '2019-01-01'
GROUP BY pp.primary_payment_type
ORDER BY orders DESC;

-- E2) Revenue share by primary payment type (sanity check)
SELECT 
  pp.primary_payment_type,
  CAST(SUM(r.revenue_brl) AS decimal(18,2)) AS revenue_brl,
  CAST(100.0 * SUM(r.revenue_brl) / SUM(SUM(r.revenue_brl)) OVER () AS decimal(5,2)) AS pct_revenue
FROM dbo.v_orders o
JOIN dbo.v_payments pp ON pp.order_id = o.order_id
JOIN dbo.v_order_revenue r ON r.order_id = o.order_id
WHERE o.order_status='delivered'
  AND o.purchase_ts >= '2016-01-01' AND o.purchase_ts < '2019-01-01'
GROUP BY pp.primary_payment_type
ORDER BY revenue_brl DESC;

-- E3) % of orders with single installment (≈ 55%)
SELECT 
  CAST(100.0 * SUM(CASE WHEN p.max_installments = 1 THEN 1 ELSE 0 END) / COUNT(*) AS decimal(5,2))
  AS pct_orders_single_installment
FROM dbo.v_orders o
JOIN dbo.v_payments p ON p.order_id = o.order_id
WHERE o.order_status='delivered'
  AND o.purchase_ts >= '2016-01-01' AND o.purchase_ts < '2019-01-01';
  --------------------------------------------------------------------------------------
  ---Sales by state f
  ;WITH state_sales AS (
  SELECT c.uf, SUM(r.revenue_brl) AS sales_brl
  FROM dbo.v_orders o
  JOIN dbo.v_order_revenue r ON r.order_id = o.order_id
  JOIN dbo.v_customers c     ON c.customer_id = o.customer_id
  WHERE o.order_status='delivered'
    AND o.purchase_ts >= '2016-01-01' AND o.purchase_ts < '2019-01-01'
  GROUP BY c.uf
)
SELECT TOP (10)
  CASE uf 
    WHEN 'SP' THEN 'São Paulo (SP)'
    WHEN 'RJ' THEN 'Rio de Janeiro (RJ)'
    WHEN 'MG' THEN 'Minas Gerais (MG)'
    ELSE uf
  END AS state,
  CAST(sales_brl AS decimal(18,2)) AS sales_brl,
  CAST(100.0 * sales_brl / SUM(sales_brl) OVER() AS decimal(5,2)) AS pct_of_total
FROM state_sales
ORDER BY sales_brl DESC;
---------------------------------------------------------------------------------
--buy one product per session
;WITH item_counts AS (
  SELECT order_id, COUNT(*) AS item_count
  FROM dbo.v_order_items
  GROUP BY order_id
)
SELECT
  SUM(CASE WHEN item_count=1 THEN 1 ELSE 0 END) AS one_item_orders,
  COUNT(*) AS total_orders,
  CAST(100.0 * SUM(CASE WHEN item_count=1 THEN 1 ELSE 0 END) / COUNT(*) AS decimal(5,2)) AS pct_orders_one_item
FROM item_counts;

-- G2) # and % of CUSTOMERS whose EVERY order has exactly 1 item
;WITH item_counts AS (
  SELECT order_id, COUNT(*) AS item_count
  FROM dbo.v_order_items
  GROUP BY order_id
),
order_items_per_customer AS (
  SELECT o.customer_id,
         SUM(CASE WHEN ic.item_count=1 THEN 1 ELSE 0 END) AS orders_with_1_item,
         COUNT(*) AS orders_total
  FROM dbo.v_orders o
  JOIN item_counts ic ON ic.order_id = o.order_id
  WHERE o.order_status='delivered'
  GROUP BY o.customer_id
)
SELECT
  SUM(CASE WHEN orders_with_1_item = orders_total THEN 1 ELSE 0 END) AS customers_always_1_item,
  COUNT(*) AS customers_total,
  CAST(100.0 * SUM(CASE WHEN orders_with_1_item = orders_total THEN 1 ELSE 0 END) / COUNT(*) AS decimal(5,2)) AS pct_customers_always_1_item
FROM order_items_per_customer;
------------------------------------------------------------------------------------
----top  catgeories above the avg
;WITH cat_rev AS (
  SELECT pr.product_category_name,
         SUM(oi.price + oi.freight_value) AS sales_brl
  FROM dbo.v_orders o
  JOIN dbo.v_order_items oi ON oi.order_id = o.order_id
  JOIN dbo.v_products pr     ON pr.product_id = oi.product_id
  WHERE o.order_status='delivered'
    AND o.purchase_ts >= '2016-01-01' AND o.purchase_ts < '2019-01-01'
  GROUP BY pr.product_category_name
),
avg_rev AS (
  SELECT AVG(sales_brl) AS avg_cat_sales FROM cat_rev
)
SELECT TOP (7)
  c.product_category_name,
  CAST(c.sales_brl AS decimal(18,2)) AS sales_brl
FROM cat_rev c
CROSS JOIN avg_rev a
WHERE c.sales_brl > a.avg_cat_sales
ORDER BY c.sales_brl DESC;
-------------------------------------------------------------------------

--Monthly average review score and the minimum month
;WITH month_scores AS (
  SELECT 
    CAST(EOMONTH(o.purchase_ts) AS date) AS month_end,
    AVG(TRY_CONVERT(int, re.review_score)) AS avg_score
  FROM dbo.stg_order_reviews re
  JOIN dbo.v_orders o ON o.order_id = re.order_id
  GROUP BY CAST(EOMONTH(o.purchase_ts) AS date)
)
SELECT TOP (1) 
  month_end, CAST(avg_score AS decimal(4,2)) AS avg_score_min
FROM month_scores
ORDER BY avg_score ASC;

--full monthly table to feed a plot
SELECT 
  CAST(EOMONTH(o.purchase_ts) AS date) AS month_end,
  CAST(AVG(TRY_CONVERT(int, re.review_score)) AS decimal(4,2)) AS avg_score
FROM dbo.stg_order_reviews re
JOIN dbo.v_orders o ON o.order_id = re.order_id
GROUP BY CAST(EOMONTH(o.purchase_ts) AS date)
ORDER BY month_end;

--score by delivery delay bins + >=20 days 
;WITH d AS (
  SELECT 
    o.order_id,
    DATEDIFF(day, o.purchase_ts, o.delivered_ts) AS actual_days
  FROM dbo.v_orders o
  WHERE o.order_status='delivered' AND o.delivered_ts IS NOT NULL
)
SELECT
  CASE
    WHEN actual_days < 5  THEN '0-4'
    WHEN actual_days < 10 THEN '5-9'
    WHEN actual_days < 15 THEN '10-14'
    WHEN actual_days < 20 THEN '15-19'
    ELSE '20+'
  END AS delay_bin,
  CAST(AVG(TRY_CONVERT(int, re.review_score)) AS decimal(4,2)) AS avg_review_score,
  COUNT(*) AS n_orders
FROM d
JOIN dbo.stg_order_reviews re ON re.order_id = d.order_id
GROUP BY CASE
    WHEN actual_days < 5  THEN '0-4'
    WHEN actual_days < 10 THEN '5-9'
    WHEN actual_days < 15 THEN '10-14'
    WHEN actual_days < 20 THEN '15-19'
    ELSE '20+'
  END
ORDER BY MIN(actual_days);

--pearson correlation between delay days and review score
;WITH base AS (
  SELECT
      CAST(DATEDIFF(day, o.purchase_ts, o.delivered_ts) AS bigint) AS delay_days,
      TRY_CONVERT(bigint, re.review_score)                         AS score
  FROM dbo.v_orders o
  JOIN dbo.stg_order_reviews re ON re.order_id = o.order_id
  WHERE o.order_status = 'delivered'
    AND o.delivered_ts IS NOT NULL
    AND re.review_score IS NOT NULL
)
SELECT
    COUNT_BIG(*) AS n,
    AVG(CAST(delay_days AS decimal(38,10))) AS mean_delay,
    AVG(CAST(score      AS decimal(38,10))) AS mean_score,
    CAST(
      (
        COUNT_BIG(*) * SUM(CAST(delay_days AS decimal(38,10)) * CAST(score AS decimal(38,10)))
        - SUM(CAST(delay_days AS decimal(38,10))) * SUM(CAST(score AS decimal(38,10)))
      )
      /
      NULLIF(
        SQRT(
          ( COUNT_BIG(*) * SUM(CAST(delay_days AS decimal(38,10)) * CAST(delay_days AS decimal(38,10)))
            - POWER(SUM(CAST(delay_days AS decimal(38,10))), 2) )
          *
          ( COUNT_BIG(*) * SUM(CAST(score AS decimal(38,10)) * CAST(score AS decimal(38,10)))
            - POWER(SUM(CAST(score AS decimal(38,10))), 2) )
        ),
        0
      )
      AS decimal(18,6)
    ) AS pearson_r
FROM base;


---------------------------------------------------------------------------------






----------------------------------

