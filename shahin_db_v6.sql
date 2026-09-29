-- ======================================================================
-- شاهين - سكريبت قاعدة البيانات الجديدة (v6)
-- شغّله كاملاً، مرة واحدة، في SQL Editor على مشروع Supabase جديد وفارغ.
-- نفس أسماء الجداول والأعمدة المستخدمة في التطبيق الحالي، ما عدا:
--   * عمود orders.pickup_code انتقل لجدول سري order_secrets
--   * جداول جديدة: order_secrets و driver_live_locations
-- ======================================================================


-- ======================================================================
-- 1) الجداول
-- ======================================================================

create table public.vehicle_types (
    id uuid primary key default gen_random_uuid(),
    name text not null unique,
    description text,
    image_url text,
    capacity text,
    category text check (category in ('light', 'medium', 'heavy')),
    base_price_per_km numeric(10,2),
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table public.users (
    id uuid primary key references auth.users(id) on delete cascade,
    phone text unique not null,
    full_name text,
    email text,
    role text not null default 'customer' check (role in ('customer', 'driver', 'admin', 'support')),
    status text not null default 'active' check (status in ('active', 'suspended', 'blocked')),
    city text,
    profile_image_url text,
    fcm_token text,
    is_onboarded boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table public.driver_profiles (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null unique references public.users(id) on delete cascade,
    vehicle_type_id uuid references public.vehicle_types(id),
    vehicle_plate text,
    date_of_birth date,
    is_online boolean not null default false,
    current_lat double precision,
    current_lng double precision,
    approval_status text not null default 'pending'
        check (approval_status in ('pending', 'under_review', 'approved', 'rejected', 'needs_resubmission')),
    rejection_reason text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table public.driver_documents (
    id uuid primary key default gen_random_uuid(),
    driver_profile_id uuid not null references public.driver_profiles(id) on delete cascade,
    document_type text check (document_type in ('national_id', 'driving_license', 'vehicle_registration', 'personal_photo')),
    image_url text not null,
    status text not null default 'pending' check (status in ('pending', 'under_review', 'approved', 'rejected')),
    rejection_reason text,
    uploaded_at timestamptz not null default now(),
    reviewed_at timestamptz,
    unique (driver_profile_id, document_type)
);

create table public.orders (
    id uuid primary key default gen_random_uuid(),
    customer_id uuid not null references public.users(id) on delete cascade,
    driver_id uuid references public.users(id) on delete set null,

    pickup_location_text text not null,
    pickup_lat double precision not null,
    pickup_lng double precision not null,
    dropoff_location_text text not null,
    dropoff_lat double precision not null,
    dropoff_lng double precision not null,

    required_vehicle_type_id uuid not null references public.vehicle_types(id),
    description text,
    estimated_price numeric(10,2),
    final_price numeric(10,2),
    distance_km numeric(8,2),

    status text not null default 'pending' check (status in (
        'pending', 'accepted', 'driver_on_the_way', 'arrived', 'started',
        'completed', 'cancelled', 're_pending', 'expired', 'failed'
    )),

    cancellation_reason text,
    cancelled_by text check (cancelled_by in ('customer', 'driver', 'admin')),

    created_at timestamptz not null default now(),
    accepted_at timestamptz,
    arrived_at timestamptz,
    started_at timestamptz,
    completed_at timestamptz,
    updated_at timestamptz not null default now()
);

create index orders_customer_idx on public.orders (customer_id, created_at desc);
create index orders_driver_idx on public.orders (driver_id, created_at desc);
create index orders_pending_idx on public.orders (required_vehicle_type_id) where status = 'pending';

-- كود الاستلام (سري): لا أحد يقرأه مباشرة، فقط عبر الدوال بالأسفل
create table public.order_secrets (
    order_id uuid primary key references public.orders(id) on delete cascade,
    pickup_code text not null,
    failed_attempts int not null default 0,
    locked_until timestamptz
);

-- آخر موقع لكل سائق (صف واحد لكل سائق - upsert)
create table public.driver_live_locations (
    driver_id uuid primary key references public.users(id) on delete cascade,
    order_id uuid references public.orders(id) on delete set null,
    lat double precision not null,
    lng double precision not null,
    heading double precision,
    speed double precision,
    updated_at timestamptz not null default now()
);

create table public.order_status_history (
    id uuid primary key default gen_random_uuid(),
    order_id uuid not null references public.orders(id) on delete cascade,
    status text not null,
    changed_by uuid references public.users(id) on delete set null,
    note text,
    created_at timestamptz not null default now()
);

create table public.ratings (
    id uuid primary key default gen_random_uuid(),
    order_id uuid not null references public.orders(id) on delete cascade,
    from_user_id uuid not null references public.users(id) on delete cascade,
    to_user_id uuid not null references public.users(id) on delete cascade,
    rating integer not null check (rating between 1 and 5),
    comment text,
    created_at timestamptz not null default now(),
    unique (order_id, from_user_id),           -- كل طرف يقيّم مرة واحدة
    check (from_user_id <> to_user_id)
);

create table public.reports (
    id uuid primary key default gen_random_uuid(),
    reporter_id uuid not null references public.users(id) on delete cascade,
    reported_user_id uuid not null references public.users(id) on delete cascade,
    order_id uuid references public.orders(id) on delete set null,
    reason text not null,
    details text,
    status text not null default 'pending' check (status in ('pending', 'reviewed', 'resolved', 'dismissed')),
    admin_note text,
    created_at timestamptz not null default now(),
    resolved_at timestamptz
);

create table public.notifications (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.users(id) on delete cascade,
    title text not null,
    body text not null,
    data jsonb,
    is_read boolean not null default false,
    created_at timestamptz not null default now()
);

create table public.audit_logs (
    id uuid primary key default gen_random_uuid(),
    actor_id uuid references public.users(id) on delete set null,
    action text not null,
    target_type text,
    target_id uuid,
    old_data jsonb,
    new_data jsonb,
    ip_address text,
    user_agent text,
    created_at timestamptz not null default now()
);


-- ======================================================================
-- 2) دوال مساعدة
--    (security definer لتجنّب خطأ infinite recursion في سياسات RLS)
-- ======================================================================

create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path = public as $$
    select exists (
        select 1 from public.users
        where id = auth.uid() and role = 'admin' and status = 'active'
    );
$$;

-- سائق موثّق ونشط ومركبته تطابق النوع المطلوب
create or replace function public.is_approved_driver_for(p_vehicle_type_id uuid)
returns boolean
language sql stable security definer set search_path = public as $$
    select exists (
        select 1
        from public.driver_profiles dp
        join public.users u on u.id = dp.user_id
        where dp.user_id = auth.uid()
          and dp.approval_status = 'approved'
          and u.status = 'active'
          and dp.vehicle_type_id = p_vehicle_type_id
    );
$$;

create or replace function public.is_approved_driver()
returns boolean
language sql stable security definer set search_path = public as $$
    select exists (
        select 1
        from public.driver_profiles dp
        join public.users u on u.id = dp.user_id
        where dp.user_id = auth.uid()
          and dp.approval_status = 'approved'
          and u.status = 'active'
    );
$$;

create or replace function public.driver_has_active_order(p_driver_id uuid)
returns boolean
language sql stable security definer set search_path = public as $$
    select exists (
        select 1 from public.orders
        where driver_id = p_driver_id
          and status in ('accepted', 'driver_on_the_way', 'arrived', 'started')
    );
$$;

-- هل المستخدم الحالي عميل لرحلة نشطة مع هذا السائق؟
create or replace function public.can_view_driver_location(p_driver_id uuid)
returns boolean
language sql stable security definer set search_path = public as $$
    select exists (
        select 1 from public.orders o
        where o.customer_id = auth.uid()
          and o.driver_id = p_driver_id
          and o.status in ('accepted', 'driver_on_the_way', 'arrived', 'started')
    );
$$;

-- المسافة بالكيلومتر (هافرساين) - مع حماية من خطأ acos عند تطابق النقطتين
create or replace function public.calculate_distance_km(
    lat1 double precision, lng1 double precision,
    lat2 double precision, lng2 double precision
) returns numeric
language sql immutable as $$
    select round(cast(
        6371 * acos(least(1.0::double precision, greatest(-1.0::double precision,
            cos(radians(lat1)) * cos(radians(lat2)) * cos(radians(lng2) - radians(lng1)) +
            sin(radians(lat1)) * sin(radians(lat2))
        ))) as numeric), 2);
$$;

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
    new.updated_at := now();
    return new;
end;
$$;


-- ======================================================================
-- 3) المحفزات (Triggers)
-- ======================================================================

create trigger trg_users_updated before insert or update on public.users
    for each row execute function public.set_updated_at();
create trigger trg_driver_profiles_updated before insert or update on public.driver_profiles
    for each row execute function public.set_updated_at();
create trigger trg_orders_updated before insert or update on public.orders
    for each row execute function public.set_updated_at();
create trigger trg_vehicle_types_updated before insert or update on public.vehicle_types
    for each row execute function public.set_updated_at();
create trigger trg_driver_live_locations_updated before insert or update on public.driver_live_locations
    for each row execute function public.set_updated_at();

-- --- حارس جدول orders: يحدد مَن يستطيع تغيير ماذا ---------------------
-- (ليس security definer عمداً: يفرّق بين طلبات التطبيق وطلبات السيرفر)
create or replace function public.orders_guard()
returns trigger language plpgsql as $$
declare
    uid uuid := auth.uid();
begin
    -- الأوقات تُضبط من السيرفر دائماً، وقيم التطبيق تُتجاهل
    if new.status is distinct from old.status then
        if new.status = 'accepted' then new.accepted_at := now();
        elsif new.status = 'arrived' then new.arrived_at := now();
        elsif new.status = 'started' then new.started_at := now();
        elsif new.status = 'completed' then new.completed_at := now();
        elsif new.status = 'pending' then
            new.accepted_at := null;
            new.arrived_at := null;
        end if;
    else
        new.accepted_at := old.accepted_at;
        new.arrived_at := old.arrived_at;
        new.started_at := old.started_at;
        new.completed_at := old.completed_at;
    end if;

    -- SQL Editor / service_role / دوال السيرفر (start_trip) لا تخضع للقيود
    if current_user <> 'authenticated' then
        return new;
    end if;
    if public.is_admin() then
        return new;
    end if;

    -- هذه الحقول لا يغيّرها أحد من التطبيق
    if new.id is distinct from old.id
       or new.customer_id is distinct from old.customer_id
       or new.pickup_location_text is distinct from old.pickup_location_text
       or new.pickup_lat is distinct from old.pickup_lat
       or new.pickup_lng is distinct from old.pickup_lng
       or new.dropoff_location_text is distinct from old.dropoff_location_text
       or new.dropoff_lat is distinct from old.dropoff_lat
       or new.dropoff_lng is distinct from old.dropoff_lng
       or new.required_vehicle_type_id is distinct from old.required_vehicle_type_id
       or new.description is distinct from old.description
       or new.estimated_price is distinct from old.estimated_price
       or new.final_price is distinct from old.final_price
       or new.distance_km is distinct from old.distance_km
       or new.created_at is distinct from old.created_at then
        raise exception 'لا يمكن تعديل بيانات الطلب الأساسية';
    end if;

    -- العميل: الإلغاء فقط
    if uid = old.customer_id then
        if new.status = 'cancelled'
           and old.status in ('pending', 'accepted', 'driver_on_the_way')
           and new.driver_id is not distinct from old.driver_id then
            new.cancelled_by := 'customer';
            return new;
        end if;
        raise exception 'العميل يستطيع إلغاء الطلب فقط (قبل بدء الرحلة)';
    end if;

    -- بقية الأطراف لا تلمس حقول الإلغاء
    if new.cancelled_by is distinct from old.cancelled_by
       or new.cancellation_reason is distinct from old.cancellation_reason then
        raise exception 'لا يمكن تعديل بيانات الإلغاء';
    end if;

    -- السائق المرتبط بالطلب
    if uid = old.driver_id then
        if (old.status = 'accepted' and new.status = 'driver_on_the_way')
           or (old.status = 'driver_on_the_way' and new.status = 'arrived')
           or (old.status = 'started' and new.status = 'completed') then
            if new.driver_id is distinct from old.driver_id then
                raise exception 'لا يمكن تغيير السائق';
            end if;
            return new;
        elsif old.status in ('accepted', 'driver_on_the_way')
              and new.status = 'pending' and new.driver_id is null then
            return new;  -- السائق ينسحب من الطلب فيعود للبث
        end if;
        -- ملاحظة: الانتقال arrived -> started لا يتم إلا عبر start_trip (بالكود)
        raise exception 'انتقال حالة غير مسموح';
    end if;

    -- سائق جديد يقبل طلباً متاحاً
    if old.status = 'pending' and old.driver_id is null
       and new.status = 'accepted' and new.driver_id = uid then
        if not public.is_approved_driver_for(old.required_vehicle_type_id) then
            raise exception 'حسابك غير موثّق أو نوع مركبتك لا يطابق الطلب';
        end if;
        if public.driver_has_active_order(uid) then
            raise exception 'لديك رحلة نشطة بالفعل';
        end if;
        return new;
    end if;

    raise exception 'تعديل غير مسموح';
end;
$$;

create trigger trg_orders_guard before update on public.orders
    for each row execute function public.orders_guard();

-- --- إنشاء كود الاستلام تلقائياً مع كل طلب جديد --------------------------
create or replace function public.create_pickup_secret()
returns trigger language plpgsql security definer set search_path = public as $$
begin
    insert into public.order_secrets (order_id, pickup_code)
    values (new.id, lpad(floor(random() * 10000)::int::text, 4, '0'));
    return new;
end;
$$;

create trigger trg_orders_create_secret after insert on public.orders
    for each row execute function public.create_pickup_secret();

-- --- سجل تغيّر الحالات ----------------------------------------------------
create or replace function public.log_order_status_change()
returns trigger language plpgsql security definer set search_path = public as $$
begin
    if tg_op = 'INSERT' or old.status is distinct from new.status then
        insert into public.order_status_history (order_id, status, changed_by)
        values (new.id, new.status, auth.uid());
    end if;
    return new;
end;
$$;

create trigger trg_orders_history after insert or update on public.orders
    for each row execute function public.log_order_status_change();

-- --- حارس users: لا أحد يغيّر دوره أو حالته بنفسه ------------------------
create or replace function public.users_guard()
returns trigger language plpgsql as $$
begin
    if current_user = 'authenticated' and not public.is_admin() then
        if new.role is distinct from old.role or new.status is distinct from old.status then
            raise exception 'لا يمكن تعديل الدور أو حالة الحساب';
        end if;
    end if;
    return new;
end;
$$;

create trigger trg_users_guard before update on public.users
    for each row execute function public.users_guard();

-- --- حارس driver_profiles: السائق لا يوثّق نفسه ---------------------------
create or replace function public.driver_profiles_guard()
returns trigger language plpgsql as $$
begin
    if current_user = 'authenticated' and not public.is_admin() then
        if new.user_id is distinct from old.user_id then
            raise exception 'لا يمكن تغيير مالك الملف';
        end if;
        if new.rejection_reason is distinct from old.rejection_reason then
            raise exception 'سبب الرفض تحدده الإدارة فقط';
        end if;
        if new.approval_status is distinct from old.approval_status then
            if not (new.approval_status = 'under_review'
                    and old.approval_status in ('pending', 'needs_resubmission')) then
                raise exception 'لا يمكن تغيير حالة التوثيق';
            end if;
        end if;
        if old.approval_status = 'approved'
           and new.vehicle_type_id is distinct from old.vehicle_type_id then
            raise exception 'تغيير نوع المركبة بعد الاعتماد يتم عبر الإدارة';
        end if;
    end if;
    return new;
end;
$$;

create trigger trg_driver_profiles_guard before update on public.driver_profiles
    for each row execute function public.driver_profiles_guard();

-- --- تسجيل أي تغيير في حالة توثيق السائق في audit_logs -------------------
create or replace function public.audit_driver_approval()
returns trigger language plpgsql security definer set search_path = public as $$
begin
    if new.approval_status is distinct from old.approval_status then
        insert into public.audit_logs (actor_id, action, target_type, target_id, old_data, new_data)
        values (
            auth.uid(), 'driver_approval_changed', 'driver_profile', new.id,
            jsonb_build_object('approval_status', old.approval_status),
            jsonb_build_object('approval_status', new.approval_status,
                               'rejection_reason', new.rejection_reason)
        );
    end if;
    return new;
end;
$$;

create trigger trg_driver_profiles_audit after update on public.driver_profiles
    for each row execute function public.audit_driver_approval();


-- ======================================================================
-- 4) دوال التطبيق (RPC)
-- ======================================================================

-- الطلبات القريبة للسائق (بنفس الاسم والمعاملات القديمة، بدون كود الاستلام)
-- نوع المركبة يُؤخذ من ملف السائق في الداتا بيز وليس من التطبيق.
create or replace function public.get_nearby_orders_for_driver(
    driver_lat double precision,
    driver_lng double precision,
    driver_vehicle_type_id uuid,
    max_distance_km double precision default 10
)
returns table (
    id uuid,
    customer_id uuid,
    pickup_location_text text,
    pickup_lat double precision,
    pickup_lng double precision,
    dropoff_location_text text,
    dropoff_lat double precision,
    dropoff_lng double precision,
    description text,
    required_vehicle_type_id uuid,
    required_vehicle_type_name text,
    estimated_price numeric,
    distance_km numeric,
    status text,
    created_at timestamptz
)
language sql stable security definer set search_path = public as $$
    select
        o.id, o.customer_id,
        o.pickup_location_text, o.pickup_lat, o.pickup_lng,
        o.dropoff_location_text, o.dropoff_lat, o.dropoff_lng,
        o.description, o.required_vehicle_type_id, vt.name,
        o.estimated_price,
        public.calculate_distance_km(driver_lat, driver_lng, o.pickup_lat, o.pickup_lng),
        o.status, o.created_at
    from public.orders o
    join public.vehicle_types vt on vt.id = o.required_vehicle_type_id
    join public.driver_profiles dp on dp.user_id = auth.uid()
    join public.users u on u.id = dp.user_id
    where dp.approval_status = 'approved'
      and u.status = 'active'
      and o.required_vehicle_type_id = dp.vehicle_type_id
      and o.status = 'pending'
      and o.driver_id is null
      and not public.driver_has_active_order(auth.uid())
      and public.calculate_distance_km(driver_lat, driver_lng, o.pickup_lat, o.pickup_lng) <= max_distance_km
    order by public.calculate_distance_km(driver_lat, driver_lng, o.pickup_lat, o.pickup_lng) asc;
$$;

-- العميل فقط، وفقط عندما تكون الحالة arrived
create or replace function public.get_pickup_code(p_order_id uuid)
returns text
language sql stable security definer set search_path = public as $$
    select s.pickup_code
    from public.order_secrets s
    join public.orders o on o.id = s.order_id
    where s.order_id = p_order_id
      and o.customer_id = auth.uid()
      and o.status = 'arrived';
$$;

-- السائق يدخل الكود؛ التحقق في السيرفر مع حد أقصى 5 محاولات ثم قفل 10 دقائق
-- النتيجة: ok | wrong_code | locked | not_allowed
create or replace function public.start_trip(p_order_id uuid, p_code text)
returns text
language plpgsql security definer set search_path = public as $$
declare
    o public.orders%rowtype;
    s public.order_secrets%rowtype;
begin
    select * into o from public.orders where id = p_order_id for update;
    if not found or o.driver_id is distinct from auth.uid() or o.status <> 'arrived' then
        return 'not_allowed';
    end if;

    select * into s from public.order_secrets where order_id = p_order_id for update;
    if not found then
        return 'not_allowed';
    end if;

    if s.locked_until is not null and s.locked_until > now() then
        return 'locked';
    end if;

    if s.pickup_code = btrim(coalesce(p_code, '')) then
        update public.order_secrets
           set failed_attempts = 0, locked_until = null
         where order_id = p_order_id;
        update public.orders set status = 'started' where id = p_order_id;
        return 'ok';
    end if;

    if s.failed_attempts + 1 >= 5 then
        update public.order_secrets
           set failed_attempts = 0, locked_until = now() + interval '10 minutes'
         where order_id = p_order_id;
        return 'locked';
    end if;

    update public.order_secrets
       set failed_attempts = failed_attempts + 1
     where order_id = p_order_id;
    return 'wrong_code';
end;
$$;

-- بيانات الطرف الآخر في رحلة نشطة (العميل يرى السائق، والسائق يرى العميل)
create or replace function public.get_trip_contact(p_order_id uuid)
returns table (
    full_name text,
    phone text,
    vehicle_type_name text,
    vehicle_plate text
)
language plpgsql stable security definer set search_path = public as $$
declare
    o public.orders%rowtype;
begin
    select * into o from public.orders where id = p_order_id;
    if not found or o.status not in ('accepted', 'driver_on_the_way', 'arrived', 'started') then
        return;
    end if;

    if auth.uid() = o.customer_id and o.driver_id is not null then
        return query
            select u.full_name, u.phone, vt.name, dp.vehicle_plate
            from public.users u
            left join public.driver_profiles dp on dp.user_id = u.id
            left join public.vehicle_types vt on vt.id = dp.vehicle_type_id
            where u.id = o.driver_id;
    elsif auth.uid() = o.driver_id then
        return query
            select u.full_name, u.phone, null::text, null::text
            from public.users u
            where u.id = o.customer_id;
    end if;
end;
$$;

revoke all on function public.get_nearby_orders_for_driver(double precision, double precision, uuid, double precision) from public, anon;
revoke all on function public.get_pickup_code(uuid) from public, anon;
revoke all on function public.start_trip(uuid, text) from public, anon;
revoke all on function public.get_trip_contact(uuid) from public, anon;
grant execute on function public.get_nearby_orders_for_driver(double precision, double precision, uuid, double precision) to authenticated;
grant execute on function public.get_pickup_code(uuid) to authenticated;
grant execute on function public.start_trip(uuid, text) to authenticated;
grant execute on function public.get_trip_contact(uuid) to authenticated;


-- ======================================================================
-- 5) سياسات الأمان (RLS)
-- ======================================================================

alter table public.vehicle_types          enable row level security;
alter table public.users                  enable row level security;
alter table public.driver_profiles        enable row level security;
alter table public.driver_documents       enable row level security;
alter table public.orders                 enable row level security;
alter table public.order_secrets          enable row level security;  -- بدون أي سياسة = لا وصول مباشر
alter table public.driver_live_locations  enable row level security;
alter table public.order_status_history   enable row level security;
alter table public.ratings                enable row level security;
alter table public.reports                enable row level security;
alter table public.notifications          enable row level security;
alter table public.audit_logs             enable row level security;

revoke all on public.order_secrets from anon, authenticated;

-- vehicle_types
create policy "vehicle_types: read" on public.vehicle_types for select using (true);
create policy "vehicle_types: admin" on public.vehicle_types for all
    using (public.is_admin()) with check (public.is_admin());

-- users (الطرف الآخر في الرحلة يُقرأ عبر get_trip_contact فقط)
create policy "users: read own" on public.users for select using (auth.uid() = id);
create policy "users: insert own" on public.users for insert
    with check (auth.uid() = id and role in ('customer', 'driver') and status = 'active');
create policy "users: update own" on public.users for update
    using (auth.uid() = id) with check (auth.uid() = id);
create policy "users: admin" on public.users for all
    using (public.is_admin()) with check (public.is_admin());

-- driver_profiles
create policy "driver_profiles: read own" on public.driver_profiles for select using (auth.uid() = user_id);
create policy "driver_profiles: insert own" on public.driver_profiles for insert
    with check (auth.uid() = user_id and approval_status = 'pending');
create policy "driver_profiles: update own" on public.driver_profiles for update
    using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "driver_profiles: admin" on public.driver_profiles for all
    using (public.is_admin()) with check (public.is_admin());

-- driver_documents (السائق لا يستطيع اعتماد وثيقته بنفسه)
create policy "driver_documents: read own" on public.driver_documents for select using (
    exists (select 1 from public.driver_profiles dp
            where dp.id = driver_profile_id and dp.user_id = auth.uid()));
create policy "driver_documents: insert own" on public.driver_documents for insert with check (
    status in ('pending', 'under_review')
    and exists (select 1 from public.driver_profiles dp
                where dp.id = driver_profile_id and dp.user_id = auth.uid()));
create policy "driver_documents: update own" on public.driver_documents for update using (
    exists (select 1 from public.driver_profiles dp
            where dp.id = driver_profile_id and dp.user_id = auth.uid())
) with check (
    status in ('pending', 'under_review')
    and exists (select 1 from public.driver_profiles dp
                where dp.id = driver_profile_id and dp.user_id = auth.uid()));
create policy "driver_documents: admin" on public.driver_documents for all
    using (public.is_admin()) with check (public.is_admin());

-- orders
create policy "orders: customer read own" on public.orders for select
    using (customer_id = auth.uid());
create policy "orders: driver read assigned or matching pending" on public.orders for select using (
    driver_id = auth.uid()
    or (status = 'pending' and driver_id is null
        and public.is_approved_driver_for(required_vehicle_type_id))
);
create policy "orders: customer create" on public.orders for insert with check (
    customer_id = auth.uid() and status = 'pending' and driver_id is null
    and final_price is null and cancelled_by is null
);
create policy "orders: customer update own" on public.orders for update
    using (customer_id = auth.uid()) with check (customer_id = auth.uid());
create policy "orders: driver update" on public.orders for update using (
    driver_id = auth.uid()
    or (status = 'pending' and driver_id is null
        and public.is_approved_driver_for(required_vehicle_type_id))
) with check (
    driver_id = auth.uid() or (driver_id is null and status = 'pending')
);
create policy "orders: admin" on public.orders for all
    using (public.is_admin()) with check (public.is_admin());

-- driver_live_locations
create policy "live_locations: driver read own" on public.driver_live_locations for select
    using (driver_id = auth.uid());
create policy "live_locations: customer read active trip" on public.driver_live_locations for select
    using (public.can_view_driver_location(driver_id));
create policy "live_locations: driver insert own" on public.driver_live_locations for insert
    with check (driver_id = auth.uid() and public.is_approved_driver());
create policy "live_locations: driver update own" on public.driver_live_locations for update
    using (driver_id = auth.uid()) with check (driver_id = auth.uid());
create policy "live_locations: admin" on public.driver_live_locations for all
    using (public.is_admin()) with check (public.is_admin());

-- order_status_history (الإدراج من المحفز فقط)
create policy "history: participants read" on public.order_status_history for select using (
    exists (select 1 from public.orders o
            where o.id = order_id and (o.customer_id = auth.uid() or o.driver_id = auth.uid())));
create policy "history: admin" on public.order_status_history for all
    using (public.is_admin()) with check (public.is_admin());

-- ratings (بعد اكتمال الرحلة فقط، وللطرف الآخر فقط)
create policy "ratings: read mine" on public.ratings for select
    using (auth.uid() in (from_user_id, to_user_id));
create policy "ratings: insert after completed trip" on public.ratings for insert with check (
    auth.uid() = from_user_id
    and exists (
        select 1 from public.orders o
        where o.id = order_id and o.status = 'completed'
          and ((o.customer_id = auth.uid() and o.driver_id = to_user_id)
            or (o.driver_id = auth.uid() and o.customer_id = to_user_id))
    )
);
create policy "ratings: admin" on public.ratings for all
    using (public.is_admin()) with check (public.is_admin());

-- reports
create policy "reports: create" on public.reports for insert with check (auth.uid() = reporter_id);
create policy "reports: read own" on public.reports for select using (auth.uid() = reporter_id);
create policy "reports: admin" on public.reports for all
    using (public.is_admin()) with check (public.is_admin());

-- notifications
create policy "notifications: read own" on public.notifications for select using (auth.uid() = user_id);
create policy "notifications: mark own read" on public.notifications for update
    using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "notifications: admin" on public.notifications for all
    using (public.is_admin()) with check (public.is_admin());

-- audit_logs (قراءة وإضافة فقط - بدون تعديل أو حذف من التطبيق)
create policy "audit_logs: admin read" on public.audit_logs for select using (public.is_admin());
create policy "audit_logs: admin insert" on public.audit_logs for insert with check (public.is_admin());


-- ======================================================================
-- 6) Realtime (تحديث لحظي لتغيّر الطلبات وموقع السائق)
-- ======================================================================

do $$
begin
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'orders') then
        alter publication supabase_realtime add table public.orders;
    end if;
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'driver_live_locations') then
        alter publication supabase_realtime add table public.driver_live_locations;
    end if;
end $$;


-- ======================================================================
-- 7) Storage
--    driver-docs : عام - صور الملف الشخصي فقط
--    kyc-docs    : خاص - وثائق السائقين (هوية، رخصة، مركبة)
-- ======================================================================

insert into storage.buckets (id, name, public) values
    ('driver-docs', 'driver-docs', true),
    ('kyc-docs', 'kyc-docs', false)
on conflict (id) do nothing;

-- صورة الملف الشخصي: الاسم {user_id}_profile.jpg
create policy "driver-docs: upload own photo" on storage.objects for insert to authenticated
    with check (bucket_id = 'driver-docs' and name = auth.uid()::text || '_profile.jpg');
create policy "driver-docs: read own photo" on storage.objects for select to authenticated
    using (bucket_id = 'driver-docs' and name = auth.uid()::text || '_profile.jpg');
create policy "driver-docs: replace own photo" on storage.objects for update to authenticated
    using (bucket_id = 'driver-docs' and name = auth.uid()::text || '_profile.jpg')
    with check (bucket_id = 'driver-docs' and name = auth.uid()::text || '_profile.jpg');

-- وثائق السائق: المسار {driver_profile_id}/{file}.jpg
create policy "kyc-docs: upload own" on storage.objects for insert to authenticated
    with check (
        bucket_id = 'kyc-docs'
        and (storage.foldername(name))[1] in
            (select id::text from public.driver_profiles where user_id = auth.uid())
    );
create policy "kyc-docs: read own or admin" on storage.objects for select to authenticated
    using (
        bucket_id = 'kyc-docs'
        and (public.is_admin()
             or (storage.foldername(name))[1] in
                (select id::text from public.driver_profiles where user_id = auth.uid()))
    );


-- ======================================================================
-- 8) بيانات أولية
-- ======================================================================

insert into public.vehicle_types (name, description, category, base_price_per_km) values
    ('تكتك', 'مركبة صغيرة ثلاثية العجلات', 'light', 200),
    ('كارو', 'عربة يدوية', 'light', 150),
    ('موتر', 'دراجة نارية', 'light', 100),
    ('بوكس', 'سيارة نقل صغيرة', 'medium', 500),
    ('دفار', 'سيارة دفع رباعي', 'medium', 800),
    ('لوري', 'شاحنة نقل كبيرة', 'heavy', 1500)
on conflict (name) do nothing;


-- ======================================================================
-- 9) بعد التشغيل (شغّلها يدوياً عند الحاجة، بدل القيم بين <>)
-- ======================================================================

-- تحويل حساب إلى أدمن (بعد أن يسجّل من التطبيق مرة واحدة).
-- انتبه: التطبيق الحالي يسجّل خروج أي حساب دوره ليس customer أو driver،
-- فاستخدم رقماً مخصصاً للإدارة وليس رقم تجربة العميل أو السائق.
-- update public.users set role = 'admin' where phone = '<رقم الهاتف كما هو محفوظ>';

-- اعتماد سائق (لا يستلم أي طلب قبل الاعتماد):
-- update public.driver_profiles set approval_status = 'approved'
--  where user_id = '<user id>';

-- فحص سريع:
-- select tablename, policyname, cmd from pg_policies where schemaname = 'public' order by 1, 2;
-- select tablename from pg_publication_tables where pubname = 'supabase_realtime';
