CREATE DATABASE Zepto;
USE zepto;

CREATE TABLE zepto_products (
    product_id VARCHAR(20) PRIMARY KEY,
    product_name VARCHAR(255) NOT NULL,
    category VARCHAR(100),
    brand VARCHAR(100),
    mrp DECIMAL(10, 2),
    selling_price DECIMAL(10, 2),
    cost_price DECIMAL(10, 2),
    stock_available INT,
    supplier_id VARCHAR(20)
);

CREATE TABLE zepto_orders (
    order_id VARCHAR(20) PRIMARY KEY,
    customer_id VARCHAR(20),
    product_id VARCHAR(20),
    city VARCHAR(50),
    dark_store_id VARCHAR(20),
    order_timestamp DATETIME,
    quantity INT,
    delivery_fee DECIMAL(10, 2),
    total_amount DECIMAL(10, 2),
    delivery_time_mins INT,
    payment_mode VARCHAR(30),
    order_status VARCHAR(30),
    customer_rating DECIMAL(3, 1),
    FOREIGN KEY (product_id) REFERENCES zepto_products(product_id)
);

select count(*) from zepto_products;
select count(*) from zepto_orders;

-- Q1. Category-wise Net Revenue & Profit Margin %
SELECT 
    p.category,
    COUNT(o.order_id) AS total_delivered_orders,
    SUM(o.quantity) AS total_units_sold,
    SUM(o.total_amount) AS net_revenue,
    SUM((p.selling_price - p.cost_price) * o.quantity) AS net_profit,
    ROUND(
        SUM((p.selling_price - p.cost_price) * o.quantity) /
        NULLIF(SUM(o.total_amount), 0) * 100, 2
    ) AS profit_margin_pct
FROM zepto_orders o
INNER JOIN zepto_products p
    ON o.product_id = p.product_id
WHERE o.order_status = 'Delivered'
GROUP BY p.category
ORDER BY net_profit DESC;

-- Q2. Top 3 Best-Selling Products per Category
WITH ProductRevenue AS (
    SELECT
        p.category,
        p.product_name,
        p.brand,
        SUM(o.total_amount) AS total_revenue,
        DENSE_RANK() OVER(
            PARTITION BY p.category
            ORDER BY SUM(o.total_amount) DESC
        ) AS rnk
    FROM zepto_orders o
    JOIN zepto_products p
        ON o.product_id = p.product_id
    WHERE o.order_status = 'Delivered'
    GROUP BY p.category, p.product_name, p.brand
)
SELECT
    category,
    rnk,
    product_name,
    brand,
    total_revenue
FROM ProductRevenue
WHERE rnk <= 3
ORDER BY category, rnk;

-- Q3. Unsold Products & Blocked Capital
SELECT
    p.product_id,
    p.product_name,
    p.category,
    p.stock_available,
    (p.cost_price * p.stock_available) AS blocked_capital
FROM zepto_products p
LEFT JOIN zepto_orders o
    ON p.product_id = o.product_id
    AND o.order_status = 'Delivered'
WHERE o.order_id IS NULL
ORDER BY blocked_capital DESC;

-- Q4. 15-Minute Delivery SLA Impact
SELECT
    city,
    CASE
        WHEN delivery_time_mins <= 15
            THEN 'On-Time'
        ELSE 'Delayed'
    END AS delivery_sla_status,
    COUNT(order_id) AS total_orders,
    ROUND(AVG(delivery_time_mins),1) AS avg_delivery_time,
    ROUND(AVG(customer_rating),2) AS avg_rating
FROM zepto_orders
WHERE order_status = 'Delivered'
GROUP BY city, delivery_sla_status
ORDER BY city;

-- Q5. Month-on-Month Revenue Growth %
WITH MonthlySales AS (
    SELECT
        DATE_FORMAT(order_timestamp,'%Y-%m') AS order_month,
        SUM(total_amount) AS current_month_revenue
    FROM zepto_orders
    WHERE order_status='Delivered'
    GROUP BY DATE_FORMAT(order_timestamp,'%Y-%m')
)
SELECT
    order_month,
    current_month_revenue,
    LAG(current_month_revenue)
        OVER(ORDER BY order_month) AS previous_month_revenue,
    ROUND(
        (
            current_month_revenue -
            LAG(current_month_revenue)
            OVER(ORDER BY order_month)
        )
        /
        NULLIF(
            LAG(current_month_revenue)
            OVER(ORDER BY order_month),0
        )
        *100,2
    ) AS mom_growth_pct
FROM MonthlySales
ORDER BY order_month;

-- Q6. Customer Segmentation
WITH CustomerMetrics AS (
    SELECT
        customer_id,
        COUNT(order_id) AS total_orders,
        SUM(total_amount) AS total_spent
    FROM zepto_orders
    WHERE order_status='Delivered'
    GROUP BY customer_id
)
SELECT
    CASE
        WHEN total_spent >= 5000
             AND total_orders >= 5
            THEN 'VIP Customer'
        WHEN total_spent >= 2000
             OR total_orders >= 3
            THEN 'Loyal Customer'
        ELSE 'Regular Customer'
    END AS customer_segment,
    COUNT(*) AS customer_count,
    ROUND(AVG(total_spent),2) AS avg_lifetime_value
FROM CustomerMetrics
GROUP BY customer_segment
ORDER BY avg_lifetime_value DESC;

-- Q7. Peak Ordering Hours
WITH HourlyOrders AS (
    SELECT
        HOUR(order_timestamp) AS order_hour,
        COUNT(order_id) AS total_orders,
        SUM(total_amount) AS hourly_revenue
    FROM zepto_orders
    WHERE order_status='Delivered'
    GROUP BY HOUR(order_timestamp)
)
SELECT
    order_hour,
    total_orders,
    hourly_revenue,
    ROUND(
        total_orders * 100.0 /
        SUM(total_orders) OVER(),2
    ) AS pct_of_daily_orders
FROM HourlyOrders
ORDER BY total_orders DESC;

-- Q8. Top 10 Dark Stores by Cancellation Rate 
SELECT
    dark_store_id,
    city,
    COUNT(order_id) AS total_orders,
    SUM(
        CASE
            WHEN order_status='Cancelled'
            THEN 1
            ELSE 0
        END
    ) AS cancelled_orders,
    ROUND(
        SUM(
            CASE
                WHEN order_status='Cancelled'
                THEN 1
                ELSE 0
            END
        ) * 100.0
        / COUNT(order_id),2
    ) AS cancellation_rate_pct,
    SUM(
        CASE
            WHEN order_status='Cancelled'
            THEN total_amount
            ELSE 0
        END
    ) AS lost_revenue
FROM zepto_orders
GROUP BY dark_store_id, city
HAVING COUNT(order_id) >= 10
ORDER BY cancellation_rate_pct DESC
LIMIT 10;

-- Q9. Pareto Analysis (80/20 Rule) 
WITH BrandSales AS (
    SELECT
        p.brand,
        SUM(o.total_amount) AS brand_revenue
    FROM zepto_orders o
    JOIN zepto_products p
        ON o.product_id = p.product_id
    WHERE o.order_status='Delivered'
    GROUP BY p.brand
),
CumulativeSales AS (
    SELECT
        brand,
        brand_revenue,
        SUM(brand_revenue) OVER(
            ORDER BY brand_revenue DESC
            ROWS UNBOUNDED PRECEDING
        ) AS running_total,
        SUM(brand_revenue) OVER() AS grand_total
    FROM BrandSales
)
SELECT
    brand,
    brand_revenue,
    ROUND(
        running_total/grand_total*100,
        2
    ) AS cumulative_revenue_pct
FROM CumulativeSales
WHERE (running_total-brand_revenue)/grand_total <= 0.80
ORDER BY brand_revenue DESC;

-- Q10. Stock-Out Risk Alert for Fast-Moving Products (CTE + Forecasting) 

WITH RecentVelocity AS (
    SELECT
        product_id,
        SUM(quantity) AS units_sold_last_30d
    FROM zepto_orders
    WHERE order_status = 'Delivered'
    GROUP BY product_id
)
SELECT
    p.product_id,
    p.product_name,
    p.category,
    p.stock_available,
    r.units_sold_last_30d,
    ROUND(
        p.stock_available /
        (r.units_sold_last_30d / 30.0),
        1
    ) AS estimated_days_of_stock_left,
    CASE
        WHEN p.stock_available / (r.units_sold_last_30d / 30.0) <= 3
            THEN 'Critical Risk'
        WHEN p.stock_available / (r.units_sold_last_30d / 30.0) <= 7
            THEN 'High Risk'
        WHEN p.stock_available / (r.units_sold_last_30d / 30.0) <= 15
            THEN 'Medium Risk'
        ELSE 'Low Risk'
    END AS stock_risk_level
FROM zepto_products p
JOIN RecentVelocity r
    ON p.product_id = r.product_id
ORDER BY estimated_days_of_stock_left ASC
LIMIT 15;






