# Importar el plan a Intervals.icu

Este paquete carga 23 entrenamientos estructurados y una nota de surf en el calendario personal de Intervals.icu. No contiene credenciales.

## 1. Validar antes de cargar

En Terminal, abrir esta carpeta y ejecutar:

```bash
python3 importar_intervals.py
```

Debe indicar que el plan es valido y que esta en modo de vista previa.

## 2. Obtener la clave personal

En Intervals.icu, abrir **Settings** y buscar **Developer Settings** cerca de la parte inferior. Copiar la clave API personal. No compartirla ni guardarla dentro de este paquete.

## 3. Cargar el calendario

Ejecutar:

```bash
python3 importar_intervals.py --commit
```

El programa solicita la clave de forma oculta y carga o actualiza el bloque. Los identificadores son estables: repetir la carga actualiza estos eventos en lugar de duplicarlos.

## 4. Enviar a Garmin automaticamente

En **Intervals.icu > Settings > Garmin**:

1. Conectar Garmin Connect.
2. Activar **Upload planned workouts**.
3. Incluir los tipos **Run**, **Ride** y **Swim** en los filtros de carga.
4. Sincronizar el reloj o ciclocomputador con Garmin Connect.

Intervals.icu normalmente envia aproximadamente los siguientes siete dias, no las cinco semanas completas de una sola vez. Conforme avanza el calendario, los siguientes entrenamientos se transfieren automaticamente.

## Consideraciones

- Carrera y bicicleta son los formatos mas fiables para Garmin.
- Probar N1 en el reloj antes de depender de todas las sesiones de natacion. Algunos modelos interpretan de forma diferente descansos, drills y repeticiones.
- B4 aparece como bicicleta. Si se elige surf el 15 de septiembre, omitir o eliminar B4.
- La nota de surf permanece en Intervals.icu, pero no es un entrenamiento estructurado de Garmin.
- Las zonas de carrera deben estar configuradas antes de importar para que `Z1 HR` y `Z2 HR` se resuelvan correctamente.

# Leer Garmin y planificar con Claude (`intervals.py`)

`intervals.py` deja que Claude lea lo que registra el reloj (actividades, sueno, HRV, pulso en
reposo, CTL/ATL) y suba entrenamientos nuevos, siempre a traves de Intervals.icu.

Guardar la clave una sola vez en el Llavero de macOS (la pide oculta, no queda en ningun archivo):

```bash
security add-generic-password -a "$USER" -s intervals-icu -w
```

Comandos:

```bash
python3 intervals.py resumen            # 6 semanas: volumen por deporte, CTL/ATL, sueno/HRV
python3 intervals.py actividades --dias 28
python3 intervals.py bienestar --dias 14
python3 intervals.py calendario         # lo planificado en las proximas 4 semanas
python3 intervals.py subir plan.json    # vista previa; --commit para cargarlo
```

Para borrar la clave: `security delete-generic-password -a "$USER" -s intervals-icu`.
