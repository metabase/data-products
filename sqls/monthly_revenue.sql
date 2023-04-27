with customer_summary as (
  select
    stripe_customer_id
    , min(date_trunc('month', recognized_at))::date as min_month_per_customer
    , max(date_trunc('month', recognized_at))::date as max_month_per_customer
  from {revenue} invoice
  group by 1

), months_per_customer as (
  select
    *
  from customer_summary 
  join generate_series(min_month_per_customer, max_month_per_customer + interval '1 month', '1 month'::interval) month on true

),

month_summary as (
  select
    months_per_customer.month
    , months_per_customer.stripe_customer_id
    , rev.customer_name
    , sum(rev.amount) as total_per_customer
   from {revenue} rev
   full outer join months_per_customer
     on months_per_customer.month::date = rev.month
       and months_per_customer.stripe_customer_id = rev.stripe_customer_id
  group by 1,2,3

 ), summary_including_previous_values as (
    select
        *
        , lag(total_per_customer) over (partition by stripe_customer_id order by month) as total_per_customer_previous_month
        , lead(total_per_customer) over (partition by stripe_customer_id order by month) as total_per_customer_next_month
    from month_summary

), monthly_revenue as (
  select distinct
    month::date as month
    , concat(case
               when extract('month' from date_trunc('quarter', month)) = 1 then 'Q1 '
               when extract('month' from date_trunc('quarter', month)) = 4 then 'Q2 '
               when extract('month' from date_trunc('quarter', month)) = 7 then 'Q3 '
               when extract('month' from date_trunc('quarter', month)) = 10 then 'Q4 '
             end,
            extract('year' from month)
            ) as quarter
    , date_trunc('quarter', month)::date as quarter_at
    , stripe_customer_id
    , coalesce(total_per_customer_previous_month, 0) as beginning_rev
    , total_per_customer as ending_rev
    , total_per_customer_next_month as total_next_month
    , case when total_per_customer_previous_month is null then total_per_customer else 0 end as new_rev
    , case when total_per_customer_previous_month < total_per_customer then (total_per_customer - total_per_customer_previous_month) else 0 end as expansion_rev
    , case when total_per_customer_previous_month > total_per_customer then (total_per_customer - total_per_customer_previous_month) else 0 end as contraction_rev
    , case when month < date_trunc('month', current_date)::date and total_per_customer_next_month is null then (-1 * total_per_customer) else 0 end as churn_rev
from summary_including_previous_values

-- By Month --
), monthly_summary as (
  select
    month
    , quarter
    , quarter_at
    , sum(new_rev) as new_rev
    , sum(expansion_rev) as expansion_rev
    , sum(contraction_rev) as contraction_rev
    , sum(churn_rev) as churn_rev
    , lag(sum(ending_rev)) over (order by month) as beginning_rev
    , sum(ending_rev) as ending_rev
  from monthly_revenue
  group by 1,2,3
)

select
  quarter
  , quarter_at 
  , month
  , new_rev
  , expansion_rev
  , contraction_rev
  , coalesce(lag(churn_rev) over (order by month), 0) as churn_rev
  , beginning_rev
  , ending_rev
from monthly_summary
order by 3
