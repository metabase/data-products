with item_price as (
  select
    item.id as item_id
    , billing_scheme
    , quantity
    , price.unit_amount
    , tier.flat_amount as tier_flat_amount
    , tier.unit_amount as tier_unit_amount
    , up_to_quantity as tier_up_to_quantity
    , lag(up_to_quantity) over (partition by item.id order by order_index) as tier_last_up_to_quantity
    , order_index
  from {stripe_schema}.subscription_item item
  left join {stripe_price} price
    on item.plan_id = price.id
  left join {stripe_price_tier} tier
    on price.id = tier.price_id

), item_tiered_amount as (
  select
    item_price.*
    , case billing_scheme
        when 'per_unit' then quantity * unit_amount
        when 'tiered' then
          case
            when quantity > tier_up_to_quantity
              then coalesce(tier_flat_amount, (tier_up_to_quantity - coalesce(tier_last_up_to_quantity, 0)) * tier_unit_amount)
            when (quantity > tier_last_up_to_quantity or tier_last_up_to_quantity is null)
              and (quantity <= tier_up_to_quantity or tier_up_to_quantity is null)
                then coalesce(tier_flat_amount, (quantity - coalesce(tier_last_up_to_quantity, 0)) * tier_unit_amount)
          end
      end as amount
  from item_price

), item_amount as (
  select
    item_id
    , sum(amount) as amount
  from item_tiered_amount
  group by 1

), final as (
  select
    item.id
    , created as created_at
    , price.name as price_name
    , price.product_name
    , price.billing_scheme as price_billing_scheme
    , price.recurring_interval as price_recurring_interval
    , price.recurring_interval_count as price_recurring_interval_count
    , price.description as price_description
    , item.quantity as price_quantity
    , amount as price_amount
    , subscription_id
    , plan_id as price_id
    , price.product_id
  from {stripe_schema}.subscription_item item
  left join {stripe_price} price
    on item.plan_id = price.id
  left join item_amount
    on item.id = item_amount.item_id
)

select * from final