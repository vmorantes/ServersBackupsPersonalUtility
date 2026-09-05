# Verificar

!!! quote "Un respaldo que nunca se ha restaurado no es un respaldo: es un archivo."

```bash
backupctl verify
```

## Cuatro niveles

De más barato a más concluyente. Cada uno detecta cosas que el anterior no.

| Nivel | Orden | Coste | Detecta |
|---|---|---|---|
| 1 | `verify --quick` | segundos | Zip truncado o corrupto |
| 2 | `verify` | ~10 s | Además: `.gz` ilegibles, archivos ausentes, bases sin datos |
| 3 | `verify` (con manifiesto) | incluido | Además: corrupción o manipulación **archivo a archivo** |
| 4 | `verify --restore-test <bd>` | minutos | Que el volcado **se puede volver a montar** |

### Nivel 1 — rápido

```bash
backupctl verify --quick
```

Solo el CRC del zip. Pensado para cron: barato y detecta el fallo más común
(transferencia o escritura truncada).

### Nivel 2 y 3 — completo

```bash
backupctl verify
```

```
[ >>  ] [1/5] Estructura del zip
[  OK ] el zip es íntegro (CRC correcto).
[ >>  ] [2/5] Integridad de los archivos comprimidos
[  OK ] 486 archivos .gz descomprimen correctamente.
[ >>  ] [3/5] Manifiesto y sumas de verificación
[INFO ] Origen: servidor.example · Generado: 2026-09-05 03:30 · MySQL 10.11.6 · Con datos: si
[  OK ] 486 sumas SHA-256 coinciden con el manifiesto.
[ >>  ] [4/5] Estructura y contenido
BASE DE DATOS   TABLAS  INSERT  ESTADO
tienda          41      160     ok
blog            22      31      ok
catalogo_viejo  12      0       sin datos
```

El estado por base de datos significa:

| Estado | Qué quiere decir |
|---|---|
| `ok` | Los seis archivos están y tienen contenido |
| `vacía` | Sin ninguna tabla. Puede ser legítimo |
| `sin datos` | Hay tablas pero ningún `INSERT`. **Revísalo**: o está vacía de verdad, o el volcado se interrumpió |
| `INCOMPLETA` | Falta algún archivo obligatorio. **Es un fallo** |

!!! success "Detección de manipulación"
    Las sumas SHA-256 del manifiesto se comprueban archivo a archivo. Si un
    `.gz` cambió tras generarse el respaldo, se identifica **exactamente cuál**:

    ```
    [ERROR] hay archivos cuya suma no coincide con el manifiesto:
            ./blog/data.sql.gz: La suma no coincide
    ```

    Un zip puede tener el CRC correcto y aun así contener datos alterados si se
    reempaquetó. Las sumas cierran ese hueco.

### Nivel 4 — restauración real

```bash
backupctl verify --restore-test tienda
backupctl verify --restore-test tienda --with-data     # incluye los datos
```

Es la única comprobación concluyente:

1. Crea una base de datos `verifybk_<marca de tiempo>`.
2. Restaura ahí `tables`, `functions`, `views`, `others` (y `data` con
   `--with-data`).
3. Cuenta tablas, vistas, rutinas y triggers.
4. **Elimina la base de datos temporal.**

```
[INFO ] Base de datos temporal: verifybk_20260905153012_4471
[  OK ]   tables restaurado.
[  OK ]   data restaurado.
[  OK ]   functions restaurado.
[  OK ]   views restaurado.
[  OK ]   others restaurado.
[INFO ] Restaurado: 41 tablas, 6 vistas, 3 rutinas, 2 triggers.
[INFO ] Base de datos temporal verifybk_20260905153012_4471 eliminada.
```

!!! info "Tu producción no se toca"
    `database.sql` se ignora a propósito en esta prueba: contiene un
    `CREATE DATABASE` del nombre **original** y lo recrearía. Todo va a la base
    desechable, que se borra al terminar incluso si la prueba falla.

!!! warning "Requiere privilegios"
    El usuario de MySQL necesita `CREATE` y `DROP`. Si tu usuario de respaldo es
    de solo lectura (recomendable), usa otro perfil o concédelos temporalmente.

## Verificar un respaldo concreto

```bash
backupctl verify                                        # el más reciente
backupctl verify all_databases_20260904_033010.zip      # por nombre
backupctl verify /ruta/a/otro.zip                       # por ruta
```

## Con qué frecuencia

| Nivel | Cuándo |
|---|---|
| `--quick` | Semanal, en cron. Ya va en la programación por defecto |
| Completo | Cuando algo huele raro, o tras cambiar el script |
| `--restore-test` | **Mensual**, y siempre antes de una migración |

## Respaldos antiguos

```
[AVISO] sin MANIFEST.txt (respaldo generado por una versión anterior).
```

No es un error: los respaldos anteriores a `backupctl` 2.0 no llevan
manifiesto. Se omiten las sumas y el resto de comprobaciones se hacen igual.

## Códigos de salida

- **0** — sin problemas
- **1** — se encontraron problemas
- **2** — no se pudo ni empezar (archivo inexistente, faltan órdenes)

```bash
backupctl verify --quick || echo "REVISAR EL RESPALDO"
```
