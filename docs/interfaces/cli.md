# CLI y automatización

La compuerta para servidores: sin preguntas, con códigos de salida fiables.

```bash
backupctl [opciones globales] <orden> [opciones de la orden]
```

## Opciones globales

| Opción | Efecto |
|---|---|
| `-p`, `--profile <nombre>` | Perfil (servidor) con el que trabajar |
| `-y`, `--yes` | Responder que sí a todo. **Modo desatendido** |
| `--debug` | Salida detallada |
| `--no-color` | Sin códigos de color |
| `--plain` | TUI en texto plano |
| `-h`, `--help` | Ayuda |
| `-V`, `--version` | Versión |

## Comportamiento sin terminal

`backupctl` detecta si hay terminal y se adapta. Es lo que permite usar los
mismos módulos desde el menú y desde cron:

| Aspecto | Con terminal | Sin terminal (cron) |
|---|---|---|
| Colores | Sí | No (los logs quedan limpios) |
| Salida de `backup` | Pantalla **y** log | Solo log |
| Confirmaciones | Se preguntan | Se toma el valor por defecto |
| Sin orden | Abre la TUI | Ayuda y código 2 |

!!! warning "Las confirmaciones toman el valor por defecto"
    Sin terminal, una confirmación cuyo valor por defecto es «no» responde
    **no**. Las operaciones destructivas no se ejecutan por accidente en un
    script. Si quieres que sí, usa `--yes` explícitamente.

## Códigos de salida

| Código | Significado |
|---|---|
| `0` | Todo correcto |
| `1` | La operación encontró problemas |
| `2` | Error de uso o de entorno (no se pudo ni empezar) |

Ver [Códigos de salida](../referencia/codigos.md).

```bash
if ! backupctl backup; then
    echo "El respaldo falló" | mail -s "ALERTA" admin@example.com
fi

backupctl status || systemctl restart cron
```

## Encadenar operaciones

```bash
# Respaldar y verificar en una línea
backupctl backup && backupctl verify --quick

# Respaldo semanal con prueba de restauración
backupctl backup && backupctl verify --restore-test tienda --with-data

# Migración desatendida
backupctl -y migrate --to admin@nuevo.example --fresh
```

## Registro

`backup`, `restic` y `migrate` escriben su propio log en `$LOG_DIR` y lo rotan.
Por eso la línea de cron no necesita redirección con fecha, que es donde estaba
[el fallo del `%`](../operacion/automatizacion.md#el-fallo-del-porcentaje).

```bash
backupctl logs --list       # todos, con recuento de errores
backupctl logs --errors     # solo errores y avisos del último
backupctl logs --follow     # seguir en vivo
```

## Varios servidores desde un mismo sitio

```bash
for p in $(backupctl profiles | tail -n +3 | awk '{print $1}'); do
    echo "=== $p ==="
    backupctl -p "$p" status || echo "  ⚠ $p requiere atención"
done
```

## Depurar

```bash
backupctl --debug backup --dry-run
```

`--debug` muestra las opciones de `mysqldump` detectadas, la ruta del fichero
de credenciales temporal, el perfil resuelto y cada vista procesada.

Para reproducir el entorno de cron:

```bash
env -i HOME="$HOME" PATH=/usr/bin:/bin bash -c '/home/admin/scripts/bin/backupctl status'
```

## Auxiliar interno

```bash
backupctl exec-count <bd>
```

Devuelve el número de tablas de una base de datos. Lo usa `migrate` por SSH para
comparar recuentos entre origen y destino. No está pensado para uso directo.
