WITH mrr_changes AS (
    SELECT
        establishment_id,
        product,
        event_month::DATE AS event_month,
        accumulated_mrr,
        LEAD(event_month::DATE) OVER (PARTITION BY establishment_id, product ORDER BY event_month::DATE) AS next_event_month,
        LEAD(accumulated_mrr) OVER (PARTITION BY establishment_id, product ORDER BY event_month::DATE) AS next_accumulated_mrr
    FROM tabela_mrr
),
last_valid_month AS (
    SELECT
        establishment_id,
        product,
        MAX(event_month) AS last_event_month
    FROM tabela_mrr
    GROUP BY establishment_id, product
),
mrr_monthly_distribution AS (
    SELECT
        mrr.establishment_id,
        mrr.product,
        GENERATE_SERIES(
            mrr.event_month,
            LEAST(
                COALESCE(mrr.next_event_month - INTERVAL '1 month', lvm.last_event_month),
                '2025-12-01'::DATE
            ),
            '1 month'
        )::DATE AS distributed_month,
        mrr.accumulated_mrr
    FROM mrr_changes mrr
    JOIN last_valid_month lvm
        ON mrr.establishment_id = lvm.establishment_id
        AND mrr.product = lvm.product
    WHERE mrr.accumulated_mrr > 0
),
invoice_summary AS (
    SELECT
        establishment_id,
        product_code AS product,
        DATE_TRUNC('month', invoice_expired_dt)::DATE AS invoice_month, -- Normalizando para o primeiro dia do mês
        SUM(paid) AS total_paid
    FROM invoices
    GROUP BY establishment_id, product_code, DATE_TRUNC('month', invoice_expired_dt)
)
SELECT 
    m.establishment_id,
    m.product,
    m.distributed_month,
    m.accumulated_mrr,
    COALESCE(i.total_paid, 0) AS total_paid,
    CASE 
        WHEN m.accumulated_mrr = i.total_paid THEN 'match'
        WHEN m.accumulated_mrr > i.total_paid THEN 'partially_discount'
        WHEN m.accumulated_mrr < i.total_paid THEN 'overpaid'
        WHEN i.total_paid IS NULL THEN 'total_discount'
        WHEN (2 * m.accumulated_mrr) = i.total_paid THEN 'duplicate'
        ELSE 'unknown'
    END AS classification
FROM mrr_monthly_distribution m
LEFT JOIN invoice_summary i
    ON m.establishment_id = i.establishment_id
    AND m.product = i.product
    AND m.distributed_month = i.invoice_month
ORDER BY m.establishment_id, m.product, m.distributed_month;
