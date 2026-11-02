# Tu fuerza de HABIT en el reloj

Lo que entrenas de fuerza vive en HABIT. Esto lo copia a Garmin Connect como **workouts de
fuerza de verdad** (ejercicio, series, repeticiones, descanso y peso) y los agenda en el
calendario, así que el Venu 4 los puede **iniciar y seguir**: nombre del ejercicio, animación,
cuenta de repeticiones y el peso editable por serie.

HABIT manda. Cambias la rutina en la app, corres `sync` y el reloj se entera.

## Por qué no va por Intervals.icu

Correr y bici sí viajan por Intervals (`../intervals_import/`). La fuerza, no: su exportador a
Garmin **ignora** ejercicio, repeticiones y peso, y descarta los pasos que no tienen duración,
así que al reloj llegan bloques de tiempo ("Go 0:40") sin decir qué hacer. Es una petición
abierta en su foro desde septiembre de 2026. Para seguir el entreno en el reloj, el workout
tiene que nacer como workout de fuerza de Garmin Connect, y eso es lo que hace este programa.

## Una vez

```bash
cd garmin_sync
./habit-garmin login-habit --email josephdpelayo@gmail.com
./habit-garmin login-garmin --email <tu correo de Garmin>
```

Las dos piden la contraseña oculta y **no la guardan**: de HABIT queda el refresh token en el
Llavero de macOS (servicio `habit-supabase`) y de Garmin los tokens en `~/.garminconnect`
(permisos 0600). Si Garmin pide código de verificación, lo teclea ahí mismo.

## Cada vez

```bash
./habit-garmin semana            # qué hay planeado y a qué ejercicio de Garmin se mapea cada uno
./habit-garmin sync              # vista previa: qué subiría, qué dejaría igual, qué borraría
./habit-garmin sync --commit     # lo escribe en Garmin Connect y lo agenda
```

Después del `--commit`, el reloj los recibe en la siguiente sincronización con Garmin Connect
en el teléfono (el programa pide el envío a los dispositivos).

Repetir `sync` no duplica nada: cada día lleva una firma de su contenido
(`~/.habit-garmin/state.json`). Un día que no cambió se deja igual; uno que cambió en HABIT se
vuelve a subir; un día que ya no existe en HABIT —o que pasó a descanso— se borra de Garmin.
Un entreno ya hecho (`done`) o saltado (`skipped`) no se toca.

`./habit-garmin limpiar --commit` borra de Garmin todo lo que subió este programa.

## Que se sincronice solo cada mañana

`app.habittraininghub.garmin-sync.plist` corre `sync --commit` todos los días a las 6:00, así
no hay que acordarse. Cargarlo una vez:

```bash
cp garmin_sync/app.habittraininghub.garmin-sync.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/app.habittraininghub.garmin-sync.plist
```

Lo que imprima queda en `~/.habit-garmin/sync.log`. Para quitarlo, `launchctl unload` con la
misma ruta.

## Cómo se traduce cada ejercicio

Garmin tiene su propio catálogo de 1 527 ejercicios en inglés. El mapeo va así, y `semana` dice
por cuál de estos pasó cada ejercicio:

| marca | significado |
| --- | --- |
| `·` | lo fijaste a mano en `exercise_map.json` |
| `✓` | el nombre coincide con uno del catálogo de Garmin |
| `~` | parecido (coincide la mayoría de las palabras) |
| `?` | no se encontró: va solo con la categoría, y el nombre de HABIT queda en la nota del paso |

Lo que salga `~` o `?` se arregla pegando en `exercise_map.json` las líneas que `semana` imprime
al final, ya listas. El nombre que escribiste en HABIT siempre viaja en la nota del paso, aunque
Garmin le diga de otra forma.

Los objetivos se traducen como en la app:

- `8-10` → 8 repeticiones (el piso del rango: registrar de menos nunca inventa progreso)
- `10-9-8-...` → pirámide: un bloque de una serie por escalón
- `20s`, `1:30` → serie de tiempo (los aguantes de front lever o de pino)
- `al fallo`, `AMRAP` → el paso termina con el botón de vuelta del reloj
- sin descanso escrito → 90 s, salvo calentamiento y movilidad, que van sin descanso

## Si algo se rompe

- **"No hay sesión de HABIT guardada"** o falla el refresh: vuelve a correr `login-habit`.
  Supabase rota el refresh token en cada uso: el programa guarda el nuevo, pero si una corrida
  se interrumpe a la mitad el guardado puede perderse y hay que volver a entrar.
- **Garmin rechaza la sesión**: `login-garmin` otra vez. Los tokens caducan.
- **Garmin cambia su API** (no es pública): esto usa `python-garminconnect`, que se actualiza
  con `./.venv/bin/pip install -U 'garminconnect[workout]'`.
- **Antes de tocar nada**: `./.venv/bin/python check_garmin_sync.py` prueba sin red el mapa y el
  armado de los pasos.
