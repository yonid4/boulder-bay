-- PostGIS backs the straight-line distance pre-filter that narrows candidate
-- gyms before Mapbox is asked for real travel times.
--
-- Supabase convention is to keep extensions out of `public`; `gyms.geog` will be
-- declared as `extensions.geography(Point, 4326)`.
create extension if not exists postgis with schema extensions;
