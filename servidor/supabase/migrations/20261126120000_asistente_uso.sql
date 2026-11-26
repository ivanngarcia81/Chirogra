-- Uso del asistente (docs/PLAN-1.4.md §2): cuántas preguntas y vueltas lleva cada suscripción al mes, y los tokens,
-- para el límite y para saber lo que cuesta. No se guarda ninguna pregunta ni respuesta, ni nada de los libros.
--
-- Esquema propio, `asistente`, fuera de la API de datos (que solo expone `public`): solo lo usa la función
-- `asistente`, que entra directo a la base con SUPABASE_DB_URL.

create schema if not exists asistente;
revoke all on schema asistente from public, anon, authenticated;

create table asistente.uso (
  -- `sub:<originalTransactionId>`, `libre:<appTransactionId>` o `prueba`.
  clave text not null,
  -- `AAAA-MM` para las suscripciones; `total` para el uso libre (20 preguntas en total, no al mes).
  periodo text not null,
  preguntas integer not null default 0,
  -- Cada llamada al modelo: una pregunta con herramientas son varias vueltas.
  vueltas integer not null default 0,
  tokens_entrada bigint not null default 0,
  tokens_cache_escritos bigint not null default 0,
  tokens_cache_leidos bigint not null default 0,
  tokens_salida bigint not null default 0,
  creado timestamptz not null default now(),
  actualizado timestamptz not null default now(),
  primary key (clave, periodo)
);

alter table asistente.uso enable row level security;
revoke all on asistente.uso from public, anon, authenticated;

-- Cuenta una vuelta (y una pregunta si es nueva) si cabe en el límite. Devuelve lo usado y si se permitió.
create function asistente.contar(
  p_clave text, p_periodo text, p_pregunta boolean, p_max_preguntas integer, p_max_vueltas integer
) returns table (usadas integer, vueltas_usadas integer, permitido boolean)
language plpgsql
set search_path = ''
as $$
declare
  v_preguntas integer;
  v_vueltas integer;
begin
  insert into asistente.uso (clave, periodo) values (p_clave, p_periodo) on conflict do nothing;
  select u.preguntas, u.vueltas into v_preguntas, v_vueltas
    from asistente.uso u where u.clave = p_clave and u.periodo = p_periodo for update;
  if (p_pregunta and v_preguntas >= p_max_preguntas) or v_vueltas >= p_max_vueltas then
    return query select v_preguntas, v_vueltas, false;
    return;
  end if;
  update asistente.uso u
     set preguntas = u.preguntas + (case when p_pregunta then 1 else 0 end),
         vueltas = u.vueltas + 1,
         actualizado = now()
   where u.clave = p_clave and u.periodo = p_periodo
  returning u.preguntas, u.vueltas into v_preguntas, v_vueltas;
  return query select v_preguntas, v_vueltas, true;
end;
$$;

-- Suma los tokens de una vuelta ya hecha.
create function asistente.sumar_tokens(
  p_clave text, p_periodo text, p_entrada bigint, p_cache_escritos bigint, p_cache_leidos bigint, p_salida bigint
) returns void
language sql
set search_path = ''
as $$
  update asistente.uso
     set tokens_entrada = tokens_entrada + p_entrada,
         tokens_cache_escritos = tokens_cache_escritos + p_cache_escritos,
         tokens_cache_leidos = tokens_cache_leidos + p_cache_leidos,
         tokens_salida = tokens_salida + p_salida,
         actualizado = now()
   where clave = p_clave and periodo = p_periodo;
$$;

revoke all on function asistente.contar(text, text, boolean, integer, integer) from public, anon, authenticated;
revoke all on function asistente.sumar_tokens(text, text, bigint, bigint, bigint, bigint) from public, anon, authenticated;
