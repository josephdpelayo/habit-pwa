# HABIT Entrenar — release 117

## Despliegue

1. Publicar primero `migrations/117_training_reliability_and_admin.sql` en Supabase.
2. Verificar que la migración termina completa y que existen los RPC:
   `start_training_session`, `finish_training_session`,
   `set_training_session_paused`, `save_coaching_week` y
   `training_score_history`.
3. Publicar después el HTML, `habit-training.js`, el service worker y los
   manifiestos. Todos comparten la versión `20260911-1`.
4. Abrir una vez la PWA con conexión para que el service worker descargue el
   shell nuevo antes de probar sin conexión.

No publicar el HTML antes de la migración: contiene compatibilidad para varias
columnas antiguas, pero seguridad, transacciones, snapshots y solicitudes de
cambio dependen de la 117.

## Verificación rápida

- Un socio no puede insertar ni modificar `role`, `is_instructor` o
  `coaching_beta`.
- Otro socio solo es visible mediante `profile_cards` (nombre/avatar), no desde
  la tabla completa `profiles`.
- Dos pestañas no pueden iniciar dos entrenamientos simultáneos.
- Recargar durante un entrenamiento restaura sesión, series, pausa y reloj.
- Con la red desconectada, peso, repeticiones, tiempo, RIR y check quedan como
  pendientes; al reconectar pasan a `Guardado` sin duplicarse.
- Finalizar sin conexión deja el cierre pendiente y se sincroniza después.
- Editar o eliminar una rutina no cambia los nombres del reporte de una sesión
  nueva, porque el reporte usa `exercise_snapshot`.
- Una plancha registra segundos; un ejercicio de fuerza registra peso/reps.
- El lunes antes del primer entrenamiento conserva la racha de semanas previas.
- Un día de descanso programado no aparece como cliente “sin plan”.
- Resolver o posponer una alerta la retira de la bandeja correspondiente.
- Dos coaches editando la misma semana reciben conflicto de versión en vez de
  sobrescribir el trabajo del otro.
- Cambiar un día creado por el coach genera una solicitud aprobable/rechazable.
- Duplicar una rutina crea una nueva versión; editar una existente deja copia
  en `board_version_history`.

## Comandos de control

```sh
npm run check
npm run check:sql -- migrations/117_training_reliability_and_admin.sql
npm run lint
```
