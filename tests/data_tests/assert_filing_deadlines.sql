-- Filing deadlines for the studied quarters, worked out by hand: 45 days after quarter end, moved to the next
-- business day. Q4 2025's 45th day was Saturday 14 Feb 2026 and Monday 16 Feb was Presidents' Day, so the
-- deadline was Tuesday 17 Feb. Only quarters present in the data are checked.
with expected (period_of_report, filing_deadline) as (
    select cast(p as date), cast(d as date) from (values
        ('2023-09-30', '2023-11-14'), ('2023-12-31', '2024-02-14'), ('2024-03-31', '2024-05-15'),
        ('2024-06-30', '2024-08-14'), ('2024-09-30', '2024-11-14'), ('2024-12-31', '2025-02-14'),
        ('2025-03-31', '2025-05-15'), ('2025-06-30', '2025-08-14'), ('2025-09-30', '2025-11-14'),
        ('2025-12-31', '2026-02-17'), ('2026-03-31', '2026-05-15'), ('2026-06-30', '2026-08-14')
    ) as v (p, d)
)

select q.period_of_report, q.filing_deadline as actual, e.filing_deadline as expected
from {{ ref('int_quarters') }} as q
inner join expected as e using (period_of_report)
where q.filing_deadline <> e.filing_deadline
