-- Supabase Auth stores the app's required display name in raw_user_meta_data.
-- Create the matching application profile in the same transaction as the Auth user.
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

    insert into public.profiles (id, display_name)
    values (new.id, profile_display_name);

    return new;
end;
$$;

revoke all on function public.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();
