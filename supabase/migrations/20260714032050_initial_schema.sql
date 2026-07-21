-- Household Budget App — Postgres schema (first cut, for iteration)
-- Conventions: uuid PKs, money as integer cents (bigint), month periods as
-- first-of-month DATE. Every tenant-owned row carries household_id.

create extension if not exists pgcrypto;  -- gen_random_uuid()

-- Enums -----------------------------------------------------------------------
create type member_role      as enum ('owner', 'member');
create type split_rule       as enum ('full', 'equal', 'income_weighted', 'custom');
create type budget_goal_type as enum ('percent_of_income', 'fixed_amount');
create type income_source     as enum ('salary', 'rent', 'dividend', 'other');

-- Tenancy ---------------------------------------------------------------------
create table households (
    id            uuid primary key default gen_random_uuid(),
    name          text not null,
    base_currency text not null default 'USD',
    created_at    timestamptz not null default now()
);

create table users (  -- mirrors Supabase auth identities
    id           uuid primary key,               -- = Supabase auth user id
    household_id uuid not null references households(id) on delete cascade,
    email        text not null unique,
    role         member_role not null default 'member',
    created_at   timestamptz not null default now()
);

create table members (  -- payers/participants; may have no login
    id           uuid primary key default gen_random_uuid(),
    household_id uuid not null references households(id) on delete cascade,
    user_id      uuid references users(id) on delete set null,  -- nullable
    name         text not null,
    is_active    boolean not null default true,
    created_at   timestamptz not null default now()
);
create index on members (household_id);

-- Categorization --------------------------------------------------------------
create table category_groups (  -- flexible | fixed | investments | savings
    id           uuid primary key default gen_random_uuid(),
    household_id uuid not null references households(id) on delete cascade,
    name         text not null,
    unique (household_id, name)
);

create table categories (
    id                uuid primary key default gen_random_uuid(),
    household_id      uuid not null references households(id) on delete cascade,
    category_group_id uuid references category_groups(id) on delete set null,
    name              text not null,
    is_active         boolean not null default true,
    unique (household_id, name)
);
create index on categories (household_id);

create table merchant_category_map (  -- location -> category auto-fill
    id           uuid primary key default gen_random_uuid(),
    household_id uuid not null references households(id) on delete cascade,
    merchant     text not null,
    category_id  uuid not null references categories(id) on delete cascade,
    unique (household_id, merchant)
);

-- Income ----------------------------------------------------------------------
create table properties (  -- rental properties feeding income + future tax
    id           uuid primary key default gen_random_uuid(),
    household_id uuid not null references households(id) on delete cascade,
    name         text not null
);

create type billing_cadence as enum ('monthly', 'quarterly', 'semiannual', 'annual');

create table property_taxes (  -- assessed tax, rate-based or static per period
    id                   uuid primary key default gen_random_uuid(),
    household_id         uuid not null references households(id) on delete cascade,
    property_id          uuid not null references properties(id) on delete cascade,
    period_start         date not null,             -- effective from
    period_end           date,                       -- nullable = current
    assessed_value_cents bigint,                     -- optional, used with rate_pct
    rate_pct             numeric(6,4),               -- nullable, e.g. 0.0087 = 0.87%
    amount_cents         bigint,                     -- nullable, static annual bill
    created_at           timestamptz not null default now(),
    check ( rate_pct is not null or amount_cents is not null )
);
create index on property_taxes (household_id, property_id);

create table property_insurance_policies (
    id             uuid primary key default gen_random_uuid(),
    household_id   uuid not null references households(id) on delete cascade,
    property_id    uuid not null references properties(id) on delete cascade,
    carrier        text,
    policy_number  text,
    premium_cents  bigint not null,
    cadence        billing_cadence not null default 'annual',
    period_start   date not null,
    period_end     date,                             -- nullable = current/auto-renewing
    created_at     timestamptz not null default now()
);
create index on property_insurance_policies (household_id, property_id);

create table incomes (
    id           uuid primary key default gen_random_uuid(),
    household_id uuid not null references households(id) on delete cascade,
    member_id    uuid not null references members(id) on delete cascade,
    property_id  uuid references properties(id) on delete set null,  -- rental only
    period       date not null,                 -- first-of-month
    source       income_source not null,
    amount_cents bigint not null,
    tax_meta     jsonb not null default '{}',   -- brackets later
    created_at   timestamptz not null default now()
);
create index on incomes (household_id, period);

-- Expenses & resolved splits --------------------------------------------------
create table expenses (
    id                    uuid primary key default gen_random_uuid(),
    household_id          uuid not null references households(id) on delete cascade,
    txn_date              date not null,
    merchant              text,
    amount_cents          bigint not null,
    category_id           uuid references categories(id) on delete set null,
    paid_by_member_id     uuid not null references members(id),
    split_rule            split_rule not null default 'full',
    full_target_member_id uuid references members(id),  -- for split_rule = 'full'
    custom_weights        jsonb,                          -- for 'custom': {member_id: pct}
    created_at            timestamptz not null default now()
);
create index on expenses (household_id, txn_date);
create index on expenses (household_id, category_id);

create table expense_splits (  -- resolved per-member attribution
    id           uuid primary key default gen_random_uuid(),
    expense_id   uuid not null references expenses(id) on delete cascade,
    member_id    uuid not null references members(id),
    amount_cents bigint not null,               -- this member's resolved share
    frozen_at    timestamptz,                    -- null = live for open month
    unique (expense_id, member_id)
);

-- Budgets ---------------------------------------------------------------------
create table monthly_budgets (
    id           uuid primary key default gen_random_uuid(),
    household_id uuid not null references households(id) on delete cascade,
    category_id  uuid not null references categories(id) on delete cascade,
    period       date not null,                 -- first-of-month
    goal_type    budget_goal_type not null,
    percent      numeric(6,4),                   -- when percent_of_income (0.30 = 30%)
    amount_cents bigint,                          -- when fixed_amount
    unique (household_id, category_id, period),
    check ( (goal_type = 'percent_of_income' and percent is not null)
         or (goal_type = 'fixed_amount'      and amount_cents is not null) )
);

-- Settlement (month-end who-owes-whom, pairwise; no netting) -------------------
create table settlements (
    id                 uuid primary key default gen_random_uuid(),
    household_id       uuid not null references households(id) on delete cascade,
    period             date not null,            -- first-of-month
    owed_by_member_id  uuid not null references members(id),
    owed_to_member_id  uuid not null references members(id),
    amount_cents       bigint not null,
    paid_back_at       timestamptz,              -- null = unsettled
    created_at         timestamptz not null default now()
);
create index on settlements (household_id, period);
