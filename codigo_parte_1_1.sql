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
)
SELECT *
FROM mrr_monthly_distribution
WHERE NOT EXISTS (
    SELECT 1 
    FROM mrr_changes mc 
    WHERE mrr_monthly_distribution.product = mc.product
    AND mrr_monthly_distribution.establishment_id = mc.establishment_id
    AND mrr_monthly_distribution.distributed_month >= mc.event_month
    AND mrr_monthly_distribution.accumulated_mrr <> mc.accumulated_mrr 
)
ORDER BY establishment_id, product, distributed_month;
