begin;

-- =====================================
-- TABLES
-- =====================================
create table if not exists city (
  id bigserial primary key,
  name text not null unique,
  created_at timestamptz not null default now()
);

create table if not exists app_user (
  id bigserial primary key,
  user_name text not null,
  user_contact text,
  login text not null,
  password_hash text not null,
  is_admin boolean not null default false,
  tickets_sold integer not null default 0,
  city_id bigint references city(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint app_user_tickets_sold_non_negative_chk check (tickets_sold >= 0)
);

create unique index if not exists app_user_login_uk on app_user (lower(login));

create table if not exists user_city_access (
  user_id bigint not null references app_user(id) on delete cascade,
  city_id bigint not null references city(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, city_id)
);

create table if not exists ticket (
  id bigserial primary key,
  seller_id bigint references app_user(id) on delete set null,
  city_id bigint not null references city(id) on delete restrict,
  buyer_name text,
  buyer_contact text,
  sold_at timestamptz,
  is_sold boolean not null default false,
  assigned_by bigint references app_user(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint ticket_sold_consistency_chk check (
    (is_sold = false and sold_at is null)
    or
    (is_sold = true and sold_at is not null)
  )
);

create table if not exists ticket_numbers (
  id bigserial primary key,
  ticket_id bigint not null references ticket(id) on delete cascade,
  city_id bigint not null references city(id) on delete restrict,
  number char(4) not null,
  constraint ticket_numbers_format_chk check (number ~ '^[0-9]{4}$'),
  constraint ticket_numbers_range_chk check (number between '0000' and '9999'),
  constraint ticket_numbers_city_number_uk unique (city_id, number),
  constraint ticket_numbers_ticket_number_uk unique (ticket_id, number)
);

alter table ticket_numbers
drop constraint if exists ticket_numbers_range_chk;

alter table ticket_numbers
add constraint ticket_numbers_range_chk
check (number between '0000' and '9999');

create table if not exists sale (
  id bigserial primary key,
  ticket_id bigint not null references ticket(id) on delete cascade,
  value numeric(10,2) not null,
  seller_id bigint not null references app_user(id) on delete restrict,
  city_id bigint not null references city(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint sale_ticket_uk unique (ticket_id)
);

create table if not exists winners_history (
  id bigserial primary key,
  winner_name text not null,
  winner_contact text,
  winner_ticket_id bigint not null references ticket(id) on delete restrict,
  constraint winners_history_ticket_uk unique (winner_ticket_id)
);

create table if not exists app_session (
  token text primary key,
  user_id bigint not null references app_user(id) on delete cascade,
  city_id bigint not null references city(id) on delete restrict,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);

create table if not exists log_erro (
  id bigserial primary key,
  source text not null,
  operation text,
  error_message text not null,
  stack_trace text,
  payload jsonb,
  user_id bigint references app_user(id) on delete set null,
  city_id bigint references city(id) on delete set null,
  session_token text,
  created_at timestamptz not null default now()
);

create index if not exists idx_ticket_city on ticket(city_id);
create index if not exists idx_ticket_seller on ticket(seller_id);
create index if not exists idx_ticket_numbers_ticket on ticket_numbers(ticket_id);
create index if not exists idx_ticket_numbers_city on ticket_numbers(city_id);
create index if not exists idx_sale_city on sale(city_id);
create index if not exists idx_session_user on app_session(user_id);
create index if not exists idx_session_exp on app_session(expires_at);
create index if not exists idx_log_erro_created_at on log_erro(created_at);
create index if not exists idx_log_erro_user_id on log_erro(user_id);
create index if not exists idx_log_erro_city_id on log_erro(city_id);

-- =====================================
-- TRIGGERS
-- =====================================
create or replace function set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_app_user_updated_at on app_user;
create trigger trg_app_user_updated_at
before update on app_user
for each row execute function set_updated_at();

create or replace function sync_tickets_sold_counter()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' then
    if new.is_sold and new.seller_id is not null then
      update app_user set tickets_sold = tickets_sold + 1 where id = new.seller_id;
    end if;
    return new;
  end if;

  if tg_op = 'DELETE' then
    if old.is_sold and old.seller_id is not null then
      update app_user set tickets_sold = greatest(tickets_sold - 1, 0) where id = old.seller_id;
    end if;
    return old;
  end if;

  if tg_op = 'UPDATE' then
    if old.is_sold and old.seller_id is not null then
      update app_user set tickets_sold = greatest(tickets_sold - 1, 0) where id = old.seller_id;
    end if;

    if new.is_sold and new.seller_id is not null then
      update app_user set tickets_sold = tickets_sold + 1 where id = new.seller_id;
    end if;

    return new;
  end if;

  return null;
end;
$$;

drop trigger if exists trg_ticket_sync_tickets_sold on ticket;
create trigger trg_ticket_sync_tickets_sold
after insert or update or delete on ticket
for each row execute function sync_tickets_sold_counter();

create or replace function enforce_ticket_max_4_numbers()
returns trigger
language plpgsql
as $$
begin
  if (
    select count(*) from ticket_numbers tn where tn.ticket_id = new.ticket_id
  ) >= 4 then
    raise exception 'Ticket % ja possui 4 numeros.', new.ticket_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_ticket_max_4_numbers on ticket_numbers;
create trigger trg_ticket_max_4_numbers
before insert on ticket_numbers
for each row execute function enforce_ticket_max_4_numbers();

-- =====================================
-- HELPERS
-- =====================================
create or replace function app_get_session_user(p_token text)
returns table (
  user_id bigint,
  is_admin boolean,
  city_id bigint,
  user_city_id bigint
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user app_user%rowtype;
  v_session app_session%rowtype;
begin
  select * into v_session
  from app_session s
  where s.token = p_token;

  if not found then
    raise exception 'Sessao inexistente.';
  end if;

  select * into v_user from app_user u where u.id = v_session.user_id;
  if not found then
    raise exception 'Usuario nao encontrado.';
  end if;

  return query
  select v_user.id, v_user.is_admin, v_session.city_id, v_user.city_id;
end;
$$;

create or replace function app_accessible_cities(p_user_id bigint, p_is_admin boolean, p_default_city bigint)
returns table (id bigint, name text)
language sql
security definer
set search_path = public
as $$
  with mine as (
    select c.id, c.name
    from city c
    where p_is_admin
       or c.id = p_default_city
       or exists (
         select 1 from user_city_access a
         where a.user_id = p_user_id and a.city_id = c.id
       )
  )
  select distinct m.id, m.name
  from mine m
  order by m.name;
$$;

-- =====================================
-- AUTH / SESSION RPC
-- =====================================
create or replace function app_get_login_payload(
  p_login text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user app_user%rowtype;
  v_city_id bigint;
begin
  select * into v_user
  from app_user
  where lower(login) = lower(trim(p_login));

  if not found then
    return null;
  end if;

  if v_user.is_admin then
    select c.id into v_city_id from city c where lower(c.name) = 'teresina' limit 1;
    if v_city_id is null then
      select id into v_city_id from city order by id limit 1;
    end if;
  else
    select a.city_id into v_city_id
    from user_city_access a
    where a.user_id = v_user.id
    order by a.city_id
    limit 1;

    if v_city_id is null then
      v_city_id := v_user.city_id;
    end if;
  end if;

  if v_city_id is null then
    raise exception 'Usuario sem cidade configurada.';
  end if;

  return jsonb_build_object(
    'city_id', v_city_id,
    'password_hash', v_user.password_hash,
    'user', jsonb_build_object(
      'id', v_user.id,
      'user_name', v_user.user_name,
      'user_contact', v_user.user_contact,
      'login', v_user.login,
      'is_admin', v_user.is_admin,
      'city_id', v_user.city_id
    )
  );
end;
$$;

create or replace function app_create_session(
  p_user_id bigint,
  p_city_id bigint
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user app_user%rowtype;
  v_token text;
  v_expires timestamptz;
begin
  select * into v_user from app_user where id = p_user_id;
  if not found then
    raise exception 'Usuario nao encontrado.';
  end if;

  if not exists (
    select 1 from city c where c.id = p_city_id
  ) then
    raise exception 'Cidade invalida.';
  end if;

  if v_user.is_admin then
    null;
  elsif not exists (
    select 1
    from app_accessible_cities(v_user.id, false, v_user.city_id) c
    where c.id = p_city_id
  ) then
    raise exception 'Usuario nao possui acesso a esta cidade.';
  end if;

  delete from app_session where user_id = v_user.id;
  delete from app_session where expires_at <= now();

  v_token := md5(random()::text || clock_timestamp()::text || p_user_id::text) ||
             md5(random()::text || clock_timestamp()::text || p_city_id::text);
  v_expires := now() + interval '3 days';

  insert into app_session (token, user_id, city_id, expires_at)
  values (v_token, v_user.id, p_city_id, v_expires);

  return jsonb_build_object(
    'token', v_token,
    'expires_at', v_expires,
    'city_id', p_city_id,
    'user', jsonb_build_object(
      'id', v_user.id,
      'user_name', v_user.user_name,
      'user_contact', v_user.user_contact,
      'login', v_user.login,
      'is_admin', v_user.is_admin,
      'city_id', v_user.city_id
    )
  );
end;
$$;

create or replace function app_validate_session(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session app_session%rowtype;
  v_user app_user%rowtype;
begin
  select * into v_session
  from app_session s
  where s.token = p_token;

  if not found then
    return null;
  end if;

  select * into v_user from app_user where id = v_session.user_id;
  if not found then
    return null;
  end if;

  return jsonb_build_object(
    'city_id', v_session.city_id,
    'user', jsonb_build_object(
      'id', v_user.id,
      'user_name', v_user.user_name,
      'user_contact', v_user.user_contact,
      'login', v_user.login,
      'is_admin', v_user.is_admin,
      'city_id', v_user.city_id
    )
  );
end;
$$;

create or replace function app_logout(p_token text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from app_session where token = p_token;
end;
$$;

create or replace function app_switch_city(
  p_token text,
  p_city_id bigint
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ctx record;
  v_allowed boolean;
begin
  select * into v_ctx from app_get_session_user(p_token);

  if v_ctx.is_admin then
    v_allowed := exists (select 1 from city where id = p_city_id);
  else
    v_allowed := exists (
      select 1
      from app_accessible_cities(v_ctx.user_id, false, v_ctx.user_city_id) c
      where c.id = p_city_id
    );
  end if;

  if not v_allowed then
    raise exception 'Usuario nao possui acesso a esta cidade.';
  end if;

  update app_session set city_id = p_city_id where token = p_token;
end;
$$;

create or replace function app_log_error(
  p_source text,
  p_error_message text,
  p_operation text default null,
  p_stack_trace text default null,
  p_payload jsonb default null,
  p_token text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id bigint;
  v_city_id bigint;
begin
  if p_token is not null and trim(p_token) <> '' then
    select s.user_id, s.city_id
    into v_user_id, v_city_id
    from app_session s
    where s.token = p_token
      and s.expires_at > now()
    limit 1;
  end if;

  insert into log_erro (
    source,
    operation,
    error_message,
    stack_trace,
    payload,
    user_id,
    city_id,
    session_token
  )
  values (
    coalesce(nullif(trim(p_source), ''), 'app'),
    nullif(trim(coalesce(p_operation, '')), ''),
    coalesce(nullif(trim(p_error_message), ''), 'Erro desconhecido.'),
    p_stack_trace,
    p_payload,
    v_user_id,
    v_city_id,
    nullif(trim(coalesce(p_token, '')), '')
  );
end;
$$;

-- =====================================
-- DATA RPC
-- =====================================
create or replace function app_bootstrap(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ctx record;
  v_user app_user%rowtype;
  v_sellers jsonb := '[]'::jsonb;
  v_tickets jsonb := '[]'::jsonb;
  v_cities jsonb := '[]'::jsonb;
begin
  select * into v_ctx from app_get_session_user(p_token);
  select * into v_user from app_user where id = v_ctx.user_id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', u.id,
        'user_name', u.user_name,
        'user_contact', u.user_contact,
        'login', u.login,
        'is_admin', u.is_admin,
        'city_id', u.city_id
      ) order by u.user_name
    ),
    '[]'::jsonb
  ) into v_sellers
  from app_user u
  where u.is_admin = false
    and (v_ctx.is_admin = true)
    and (
      u.city_id = v_ctx.city_id
      or exists (
        select 1 from user_city_access a
        where a.user_id = u.id and a.city_id = v_ctx.city_id
      )
    );

  with selected_tickets as (
    select t.id, t.seller_id, t.is_sold, t.sold_at, t.created_at, t.assigned_by, t.buyer_name, t.buyer_contact
    from ticket t
    where t.city_id = v_ctx.city_id
      and (
        v_ctx.is_admin = true
        or t.seller_id = v_ctx.user_id
      )
  ),
  ticket_numbers_by_ticket as (
    select
      tn.ticket_id,
      jsonb_agg((tn.number)::int order by tn.number) as numbers
    from ticket_numbers tn
    join selected_tickets st on st.id = tn.ticket_id
    group by tn.ticket_id
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', st.id,
        'numbers', coalesce(nbt.numbers, '[]'::jsonb),
        'seller_id', st.seller_id,
        'is_sold', st.is_sold,
        'sold_at', st.sold_at,
        'created_at', st.created_at,
        'assigned_by', st.assigned_by,
        'buyer_name', st.buyer_name,
        'buyer_contact', st.buyer_contact
      ) order by st.id
    ),
    '[]'::jsonb
  ) into v_tickets
  from selected_tickets st
  left join ticket_numbers_by_ticket nbt on nbt.ticket_id = st.id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object('id', c.id, 'name', c.name)
      order by c.name
    ),
    '[]'::jsonb
  ) into v_cities
  from app_accessible_cities(v_ctx.user_id, v_ctx.is_admin, v_ctx.user_city_id) c;

  return jsonb_build_object(
    'city_id', v_ctx.city_id,
    'user', jsonb_build_object(
      'id', v_user.id,
      'user_name', v_user.user_name,
      'user_contact', v_user.user_contact,
      'login', v_user.login,
      'is_admin', v_user.is_admin,
      'city_id', v_user.city_id
    ),
    'sellers', v_sellers,
    'tickets', v_tickets,
    'cities', v_cities
  );
end;
$$;

create or replace function app_generate_tickets(
  p_token text,
  p_quantity integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ctx record;
  v_ticket_count integer;
  v_needed_numbers integer;
  v_available_numbers integer;
  v_numbers text[];
begin
  select * into v_ctx from app_get_session_user(p_token);

  if not v_ctx.is_admin then
    raise exception 'Apenas administradores podem gerar bilhetes.';
  end if;

  if p_quantity is null or p_quantity <= 0 then
    raise exception 'Quantidade invalida.';
  end if;

  -- Prevent concurrent generation in the same city to avoid conflicts and retries.
  perform pg_advisory_xact_lock(v_ctx.city_id);

  select count(*) into v_ticket_count
  from ticket t
  where t.city_id = v_ctx.city_id;

  if v_ticket_count + p_quantity > 2500 then
    raise exception 'Limite maximo de 2500 bilhetes por cidade.';
  end if;

  v_needed_numbers := p_quantity * 4;

  select count(*) into v_available_numbers
  from generate_series(0, 9999) gs
  where not exists (
    select 1
    from ticket_numbers tn
    where tn.city_id = v_ctx.city_id
      and tn.number = lpad(gs::text, 4, '0')
  );

  if v_available_numbers < v_needed_numbers then
    raise exception 'Nao ha numeros suficientes disponiveis.';
  end if;

  select array_agg(num) into v_numbers
  from (
    select lpad(gs::text, 4, '0') as num
    from generate_series(0, 9999) gs
    where not exists (
      select 1
      from ticket_numbers tn
      where tn.city_id = v_ctx.city_id
        and tn.number = lpad(gs::text, 4, '0')
    )
    order by random()
    limit v_needed_numbers
  ) available_numbers;

  if v_numbers is null or array_length(v_numbers, 1) <> v_needed_numbers then
    raise exception 'Nao ha numeros suficientes disponiveis.';
  end if;

  create temporary table if not exists tmp_new_tickets (
    seq integer not null,
    ticket_id bigint not null
  ) on commit drop;

  truncate table tmp_new_tickets;

  with inserted_tickets as (
    insert into ticket (seller_id, city_id, buyer_name, buyer_contact, sold_at, is_sold, assigned_by)
    select null, v_ctx.city_id, null, null, null, false, null
    from generate_series(1, p_quantity)
    returning id
  )
  insert into tmp_new_tickets (seq, ticket_id)
  select row_number() over (order by id), id
  from inserted_tickets;

  insert into ticket_numbers (ticket_id, city_id, number)
  select
    t.ticket_id,
    v_ctx.city_id,
    v_numbers[((t.seq - 1) * 4) + n.idx]
  from tmp_new_tickets t
  cross join generate_series(1, 4) as n(idx);
end;
$$;

create or replace function app_create_seller(
  p_token text,
  p_user_name text,
  p_user_contact text,
  p_login text,
  p_password_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ctx record;
  v_user_id bigint;
begin
  select * into v_ctx from app_get_session_user(p_token);

  if not v_ctx.is_admin then
    raise exception 'Apenas administradores podem criar vendedores.';
  end if;

  if coalesce(trim(p_user_name), '') = '' then
    raise exception 'Nome do vendedor e obrigatorio.';
  end if;

  if char_length(trim(p_user_name)) > 20 then
    raise exception 'Nome do vendedor deve ter no maximo 20 caracteres.';
  end if;

  if nullif(trim(coalesce(p_user_contact, '')), '') is not null
     and length(regexp_replace(p_user_contact, '[^0-9]', '', 'g')) <> 11 then
    raise exception 'Contato do vendedor deve conter 11 digitos.';
  end if;

  if coalesce(trim(p_login), '') = '' then
    raise exception 'Login do vendedor e obrigatorio.';
  end if;

  if coalesce(trim(p_password_hash), '') = '' then
    raise exception 'Hash de senha e obrigatorio.';
  end if;

  if exists (
    select 1
    from app_user u
    where lower(u.login) = lower(trim(p_login))
  ) then
    raise exception 'Login ja existe.';
  end if;

  insert into app_user (
    user_name,
    user_contact,
    login,
    password_hash,
    is_admin,
    city_id
  )
  values (
    trim(p_user_name),
    nullif(regexp_replace(coalesce(p_user_contact, ''), '[^0-9]', '', 'g'), ''),
    trim(p_login),
    p_password_hash,
    false,
    v_ctx.city_id
  )
  returning id into v_user_id;

  insert into user_city_access (user_id, city_id)
  values (v_user_id, v_ctx.city_id)
  on conflict do nothing;

  return jsonb_build_object(
    'id', v_user_id,
    'user_name', trim(p_user_name),
    'login', trim(p_login),
    'is_admin', false,
    'city_id', v_ctx.city_id
  );
end;
$$;

create or replace function app_create_city(
  p_token text,
  p_name text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ctx record;
  v_city city%rowtype;
begin
  select * into v_ctx from app_get_session_user(p_token);

  if not v_ctx.is_admin then
    raise exception 'Apenas administradores podem criar cidades.';
  end if;

  if coalesce(trim(p_name), '') = '' then
    raise exception 'Nome da cidade e obrigatorio.';
  end if;

  if exists (
    select 1 from city c where lower(c.name) = lower(trim(p_name))
  ) then
    raise exception 'Cidade ja existe.';
  end if;

  insert into city (name)
  values (trim(p_name))
  returning * into v_city;

  return jsonb_build_object(
    'id', v_city.id,
    'name', v_city.name
  );
end;
$$;

create or replace function app_update_seller(
  p_token text,
  p_seller_id bigint,
  p_user_name text,
  p_user_contact text,
  p_login text,
  p_password_hash text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ctx record;
  v_user app_user%rowtype;
begin
  select * into v_ctx from app_get_session_user(p_token);

  if not v_ctx.is_admin then
    raise exception 'Apenas administradores podem editar vendedores.';
  end if;

  select * into v_user
  from app_user u
  where u.id = p_seller_id
    and u.is_admin = false;

  if not found then
    raise exception 'Vendedor nao encontrado.';
  end if;

  if coalesce(trim(p_user_name), '') = '' then
    raise exception 'Nome do vendedor e obrigatorio.';
  end if;

  if char_length(trim(p_user_name)) > 20 then
    raise exception 'Nome do vendedor deve ter no maximo 20 caracteres.';
  end if;

  if nullif(trim(coalesce(p_user_contact, '')), '') is not null
     and length(regexp_replace(p_user_contact, '[^0-9]', '', 'g')) <> 11 then
    raise exception 'Contato do vendedor deve conter 11 digitos.';
  end if;

  if coalesce(trim(p_login), '') = '' then
    raise exception 'Login do vendedor e obrigatorio.';
  end if;

  if exists (
    select 1
    from app_user u
    where lower(u.login) = lower(trim(p_login))
      and u.id <> v_user.id
  ) then
    raise exception 'Login ja existe.';
  end if;

  update app_user u
  set user_name = trim(p_user_name),
      user_contact = nullif(regexp_replace(coalesce(p_user_contact, ''), '[^0-9]', '', 'g'), ''),
      login = trim(p_login),
      password_hash = case
        when nullif(trim(coalesce(p_password_hash, '')), '') is null then u.password_hash
        else p_password_hash
      end
  where u.id = v_user.id;

  return jsonb_build_object(
    'id', v_user.id,
    'user_name', trim(p_user_name),
    'user_contact', nullif(regexp_replace(coalesce(p_user_contact, ''), '[^0-9]', '', 'g'), ''),
    'login', trim(p_login),
    'is_admin', false,
    'city_id', v_user.city_id
  );
end;
$$;

create or replace function app_delete_seller(
  p_token text,
  p_seller_id bigint
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ctx record;
begin
  select * into v_ctx from app_get_session_user(p_token);

  if not v_ctx.is_admin then
    raise exception 'Apenas administradores podem excluir vendedores.';
  end if;

  if not exists (
    select 1
    from app_user u
    where u.id = p_seller_id
      and u.is_admin = false
  ) then
    return false;
  end if;

  if exists (
    select 1
    from ticket t
    where t.seller_id = p_seller_id
      and t.is_sold = true
  ) then
    raise exception 'Nao e possivel excluir vendedor com vendas registradas.';
  end if;

  update ticket
  set seller_id = null,
      assigned_by = null
  where seller_id = p_seller_id
    and is_sold = false;

  delete from user_city_access where user_id = p_seller_id;
  delete from app_user where id = p_seller_id and is_admin = false;

  return found;
end;
$$;

create or replace function app_assign_tickets_by_range(
  p_token text,
  p_start integer,
  p_end integer,
  p_seller_id bigint
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ctx record;
  v_start text;
  v_end text;
  v_updated integer;
begin
  select * into v_ctx from app_get_session_user(p_token);

  if not v_ctx.is_admin then
    raise exception 'Apenas administradores podem atribuir bilhetes.';
  end if;

  if p_start is null or p_end is null or p_start < 1 or p_end > 9999 or p_start > p_end then
    raise exception 'Intervalo invalido.';
  end if;

  if not exists (
    select 1 from app_user u
    where u.id = p_seller_id and u.is_admin = false
  ) then
    raise exception 'Vendedor invalido.';
  end if;

  v_start := lpad(p_start::text, 4, '0');
  v_end := lpad(p_end::text, 4, '0');

  update ticket t
  set seller_id = p_seller_id,
      assigned_by = v_ctx.user_id
  where t.city_id = v_ctx.city_id
    and exists (
      select 1
      from ticket_numbers tn
      where tn.ticket_id = t.id
        and tn.city_id = v_ctx.city_id
        and tn.number between v_start and v_end
    );

  get diagnostics v_updated = row_count;
  return v_updated;
end;
$$;

create or replace function app_assign_tickets_by_numbers(
  p_token text,
  p_numbers integer[],
  p_seller_id bigint
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ctx record;
  v_formatted text[];
  v_updated integer;
begin
  select * into v_ctx from app_get_session_user(p_token);

  if not v_ctx.is_admin then
    raise exception 'Apenas administradores podem atribuir bilhetes.';
  end if;

  if p_numbers is null or array_length(p_numbers, 1) is null then
    raise exception 'Informe ao menos um numero.';
  end if;

  if not exists (
    select 1 from app_user u
    where u.id = p_seller_id and u.is_admin = false
  ) then
    raise exception 'Vendedor invalido.';
  end if;

  select array_agg(distinct lpad(n::text, 4, '0')) into v_formatted
  from unnest(p_numbers) n
  where n between 1 and 9999;

  if v_formatted is null or array_length(v_formatted, 1) is null then
    raise exception 'Numeros invalidos.';
  end if;

  update ticket t
  set seller_id = p_seller_id,
      assigned_by = v_ctx.user_id
  where t.city_id = v_ctx.city_id
    and exists (
      select 1
      from ticket_numbers tn
      where tn.ticket_id = t.id
        and tn.city_id = v_ctx.city_id
        and tn.number = any(v_formatted)
    );

  get diagnostics v_updated = row_count;
  return v_updated;
end;
$$;

create or replace function app_assign_tickets_by_quantity(
  p_token text,
  p_quantity integer,
  p_seller_id bigint
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ctx record;
  v_updated integer;
begin
  select * into v_ctx from app_get_session_user(p_token);

  if not v_ctx.is_admin then
    raise exception 'Apenas administradores podem atribuir bilhetes.';
  end if;

  if p_quantity is null or p_quantity <= 0 then
    raise exception 'Quantidade invalida.';
  end if;

  if not exists (
    select 1 from app_user u
    where u.id = p_seller_id and u.is_admin = false
  ) then
    raise exception 'Vendedor invalido.';
  end if;

  update ticket t
  set seller_id = p_seller_id,
      assigned_by = v_ctx.user_id
  where t.city_id = v_ctx.city_id
    and t.seller_id is null
    and t.id in (
      select t2.id
      from ticket t2
      where t2.city_id = v_ctx.city_id
        and t2.seller_id is null
      order by t2.id
      limit p_quantity
    );

  get diagnostics v_updated = row_count;
  return v_updated;
end;
$$;

create or replace function app_toggle_ticket_sold(
  p_token text,
  p_ticket_id bigint,
  p_is_sold boolean,
  p_buyer_name text default null,
  p_buyer_contact text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ctx record;
  v_ticket ticket%rowtype;
  v_effective_seller_id bigint;
begin
  select * into v_ctx from app_get_session_user(p_token);

  select * into v_ticket
  from ticket t
  where t.id = p_ticket_id
    and t.city_id = v_ctx.city_id;

  if not found then
    raise exception 'Bilhete nao encontrado.';
  end if;

  if not v_ctx.is_admin then
    if v_ticket.seller_id is distinct from v_ctx.user_id then
      raise exception 'Sem permissao para este bilhete.';
    end if;
    if v_ticket.is_sold then
      raise exception 'Bilhetes vendidos so podem ser alterados por administradores.';
    end if;
  end if;

  if p_is_sold and v_ticket.seller_id is null then
    if v_ctx.is_admin then
      v_effective_seller_id := v_ctx.user_id;
    else
      raise exception 'Bilhete sem vendedor atribuido.';
    end if;
  else
    v_effective_seller_id := v_ticket.seller_id;
  end if;

  if p_is_sold
     and nullif(trim(coalesce(p_buyer_name, '')), '') is not null
     and char_length(trim(p_buyer_name)) > 20 then
    raise exception 'Nome do comprador deve ter no maximo 20 caracteres.';
  end if;

  if p_is_sold
     and nullif(trim(coalesce(p_buyer_contact, '')), '') is not null
     and length(regexp_replace(p_buyer_contact, '[^0-9]', '', 'g')) <> 11 then
    raise exception 'Telefone do comprador deve conter 11 digitos.';
  end if;

  update ticket t
  set is_sold = p_is_sold,
      seller_id = case
        when p_is_sold and t.seller_id is null then v_effective_seller_id
        when p_is_sold then t.seller_id
        else null
      end,
      sold_at = case when p_is_sold then now() else null end,
      buyer_name = case when p_is_sold then nullif(trim(coalesce(p_buyer_name, '')), '') else null end,
      buyer_contact = case
        when p_is_sold
        then nullif(regexp_replace(coalesce(p_buyer_contact, ''), '[^0-9]', '', 'g'), '')
        else null
      end
  where t.id = v_ticket.id;

  if p_is_sold then
    insert into sale (ticket_id, value, seller_id, city_id, created_at)
    values (v_ticket.id, 2.00, v_effective_seller_id, v_ctx.city_id, now())
    on conflict (ticket_id)
    do update set
      value = excluded.value,
      seller_id = excluded.seller_id,
      city_id = excluded.city_id,
      created_at = excluded.created_at;
  else
    delete from sale where ticket_id = v_ticket.id;
  end if;
end;
$$;

create or replace function app_delete_ticket_by_id(
  p_token text,
  p_ticket_id bigint
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ctx record;
begin
  select * into v_ctx from app_get_session_user(p_token);

  if not v_ctx.is_admin then
    raise exception 'Apenas administradores podem excluir bilhetes.';
  end if;

  delete from ticket t
  where t.id = p_ticket_id
    and t.city_id = v_ctx.city_id;

  return found;
end;
$$;

create or replace function app_delete_ticket_by_number(
  p_token text,
  p_number integer
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ctx record;
  v_number text;
  v_ticket_id bigint;
begin
  select * into v_ctx from app_get_session_user(p_token);

  if not v_ctx.is_admin then
    raise exception 'Apenas administradores podem excluir bilhetes.';
  end if;

  if p_number is null or p_number < 0 or p_number > 9999 then
    raise exception 'Numero invalido. Use valores entre 0000 e 9999.';
  end if;

  v_number := lpad(p_number::text, 4, '0');

  select t.id into v_ticket_id
  from ticket t
  join ticket_numbers tn on tn.ticket_id = t.id
  where t.city_id = v_ctx.city_id
    and tn.city_id = v_ctx.city_id
    and tn.number = v_number
  limit 1;

  if v_ticket_id is null then
    return false;
  end if;

  delete from ticket where id = v_ticket_id;
  return found;
end;
$$;

create or replace function app_delete_tickets_by_range(
  p_token text,
  p_start integer,
  p_end integer
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ctx record;
  v_start text;
  v_end text;
  v_deleted integer;
begin
  select * into v_ctx from app_get_session_user(p_token);

  if not v_ctx.is_admin then
    raise exception 'Apenas administradores podem excluir bilhetes.';
  end if;

  if p_start is null or p_end is null or p_start < 0 or p_end > 9999 or p_start > p_end then
    raise exception 'Intervalo invalido.';
  end if;

  v_start := lpad(p_start::text, 4, '0');
  v_end := lpad(p_end::text, 4, '0');

  with to_delete as (
    select distinct t.id
    from ticket t
    where t.city_id = v_ctx.city_id
      and exists (
        select 1
        from ticket_numbers tn
        where tn.ticket_id = t.id
          and tn.city_id = v_ctx.city_id
          and tn.number between v_start and v_end
      )
  )
  delete from ticket t
  using to_delete d
  where t.id = d.id;

  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

create or replace function app_update_ticket_numbers(
  p_token text,
  p_ticket_id bigint,
  p_numbers integer[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ctx record;
  v_ticket ticket%rowtype;
  v_numbers text[];
  v_conflict_number text;
begin
  select * into v_ctx from app_get_session_user(p_token);

  if not v_ctx.is_admin then
    raise exception 'Apenas administradores podem editar bilhetes.';
  end if;

  select * into v_ticket
  from ticket t
  where t.id = p_ticket_id
    and t.city_id = v_ctx.city_id;

  if not found then
    raise exception 'Bilhete nao encontrado.';
  end if;

  if v_ticket.is_sold then
    raise exception 'Bilhete vendido nao pode ter numeros editados.';
  end if;

  if p_numbers is null or array_length(p_numbers, 1) is distinct from 4 then
    raise exception 'Informe exatamente 4 numeros.';
  end if;

  select array_agg(distinct lpad(n::text, 4, '0') order by lpad(n::text, 4, '0'))
  into v_numbers
  from unnest(p_numbers) n
  where n between 0 and 9999;

  if v_numbers is null or array_length(v_numbers, 1) is distinct from 4 then
    raise exception 'Numeros invalidos. Informe 4 numeros unicos entre 0000 e 9999.';
  end if;

  select vn.number into v_conflict_number
  from unnest(v_numbers) as vn(number)
  where exists (
    select 1
    from ticket_numbers tn
    where tn.city_id = v_ctx.city_id
      and tn.number = vn.number
      and tn.ticket_id <> p_ticket_id
  )
  limit 1;

  if v_conflict_number is not null then
    raise exception 'Numero % ja esta em uso em outro bilhete.', v_conflict_number;
  end if;

  delete from ticket_numbers where ticket_id = p_ticket_id;

  insert into ticket_numbers (ticket_id, city_id, number)
  select p_ticket_id, v_ctx.city_id, vn.number
  from unnest(v_numbers) as vn(number);
end;
$$;

-- =====================================
-- RLS: bloqueia acesso direto; app usa RPC
-- =====================================
alter table app_user enable row level security;
alter table city enable row level security;
alter table user_city_access enable row level security;
alter table ticket enable row level security;
alter table ticket_numbers enable row level security;
alter table sale enable row level security;
alter table winners_history enable row level security;
alter table app_session enable row level security;

revoke all on table app_user from anon, authenticated;
revoke all on table user_city_access from anon, authenticated;
revoke all on table ticket from anon, authenticated;
revoke all on table ticket_numbers from anon, authenticated;
revoke all on table sale from anon, authenticated;
revoke all on table winners_history from anon, authenticated;
revoke all on table app_session from anon, authenticated;

-- cidade pode ser lida para seleção no app
grant select on table city to anon, authenticated;

drop policy if exists city_read_all on city;
create policy city_read_all on city
for select
using (true);

-- =====================================
-- SEED INICIAL
-- =====================================
insert into city (name)
values ('teresina')
on conflict (name) do nothing;

with c as (
  select id from city where lower(name) = 'teresina' limit 1
)
insert into app_user (user_name, login, password_hash, is_admin, city_id)
select
  'V3R0N1C4',
  'V3R0N1C4',
  '$2a$10$jpaqZRrrA1.pxKzEr7xM4O.lWaypr7D8ywY4BrosMYn6wl/bgmkZm',
  true,
  c.id
from c
where not exists (
  select 1 from app_user u where lower(u.login) = lower('V3R0N1C4')
);

insert into user_city_access (user_id, city_id)
select u.id, c.id
from app_user u
join city c on lower(c.name) = 'teresina'
where lower(u.login) = lower('V3R0N1C4')
on conflict do nothing;

commit;
