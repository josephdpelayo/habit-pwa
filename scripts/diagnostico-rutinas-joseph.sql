-- Solo lectura: qué rutinas, programas y semana ve la cuenta de Joseph en HABIT.
with u as (
  select u.id, u.email from auth.users u where lower(u.email) = 'josephdpelayo@gmail.com'
)
select 'cuenta' as que, u.id::text as id, p.name || ' · rol ' || coalesce(p.role,'?')
       || ' · coaching_beta ' || coalesce(p.coaching_beta::text,'?') as detalle, null::timestamptz as cuando
from u left join public.profiles p on p.id = u.id
union all
select 'rutina propia', b.id::text,
       b.name || ' (' || jsonb_array_length(coalesce(b.exercises,'[]')) || ' ejercicios)', b.updated_at
from public.boards b join u on b.owner_id = u.id
union all
select 'rutina asignada', b.id::text, b.name, null
from public.board_assignments a join u on a.user_id = u.id join public.boards b on b.id = a.board_id
union all
select 'programa', pr.id::text,
       pr.name || case when pr.is_active then ' · ACTIVO' else '' end
       || coalesce(' · inicia ' || pr.start_date, ''), pr.updated_at
from public.coaching_programs pr join u on pr.user_id = u.id
union all
select 'semana base', t.dow::text, coalesce(t.board_name, '(descanso)'), null
from public.coaching_week_templates t join u on t.user_id = u.id
order by 1, 3;
