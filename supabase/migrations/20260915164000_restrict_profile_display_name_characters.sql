-- Keep Auth signup validation aligned with the profiles table constraint.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    profile_display_name text;
begin
    if jsonb_typeof(new.raw_user_meta_data -> 'display_name') is distinct from 'string' then
        raise exception 'display_name must be a string';
    end if;

    profile_display_name := regexp_replace(
        new.raw_user_meta_data ->> 'display_name',
        '^[[:space:]]+|[[:space:]]+$',
        '',
        'g'
    );
    if char_length(profile_display_name) not between 1 and 80 then
        raise exception 'display_name must contain between 1 and 80 characters';
    end if;
    if profile_display_name !~ '^[A-Za-z ]+$' then
        raise exception 'display_name must contain only ASCII letters and spaces';
    end if;

    insert into public.profiles (id, display_name)
    values (new.id, profile_display_name);

    return new;
end;
$$;

revoke all on function public.handle_new_user() from public, anon, authenticated;
