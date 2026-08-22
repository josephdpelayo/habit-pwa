-- Skandi Fit: incremento atómico de la cuota diaria de análisis con IA.
--
-- La tabla skandi_ai_usage llegó con la 073, pero contarla desde el endpoint (leer, sumar,
-- escribir) tiene una carrera: dos fotos subidas casi al mismo tiempo leen el mismo valor y
-- la segunda pisa a la primera, así que el tope se puede rebasar. Este RPC hace el chequeo y
-- el incremento en una sola sentencia: el WHERE del ON CONFLICT no deja pasar el update si
-- ya se llegó al límite, y sin update no hay RETURNING, que es como distinguimos "cuota
-- agotada" de "vas en la llamada N".
--
-- Devuelve el número de llamada del día (1, 2, 3...) o -1 si la cuota está agotada.

create or replace function public.skandi_bump_ai_usage(p_user uuid, p_limit integer)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  n integer;
begin
  insert into public.skandi_ai_usage (user_id, day, calls)
  values (p_user, current_date, 1)
  on conflict (user_id, day) do update
    set calls = public.skandi_ai_usage.calls + 1,
        updated_at = now()
    where public.skandi_ai_usage.calls < p_limit
  returning calls into n;

  if n is null then
    return -1;
  end if;
  return n;
end;
$$;

revoke all on function public.skandi_bump_ai_usage(uuid, integer) from public;
grant execute on function public.skandi_bump_ai_usage(uuid, integer) to service_role;

-- Devolver una llamada al bote cuando el análisis falla antes de gastar tokens (foto que no
-- se pudo descargar, formato no soportado): cobrar cuota por un error nuestro es injusto.
create or replace function public.skandi_refund_ai_usage(p_user uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.skandi_ai_usage
  set calls = greatest(calls - 1, 0), updated_at = now()
  where user_id = p_user and day = current_date;
end;
$$;

revoke all on function public.skandi_refund_ai_usage(uuid) from public;
grant execute on function public.skandi_refund_ai_usage(uuid) to service_role;
