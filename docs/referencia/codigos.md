# Códigos de salida

| Código | Significado | Qué hacer |
|---|---|---|
| `0` | Todo correcto | Nada |
| `1` | La operación encontró problemas | Revisar la salida o el log |
| `2` | Error de uso o de entorno | No se pudo ni empezar |
| `130` | Interrumpido con ++ctrl+c++ | — |

## Por orden

| Orden | `0` | `1` | `2` |
|---|---|---|---|
| `backup` | Todas las bases respaldadas | Alguna falló | Sin MySQL, sin disco, ya hay uno en curso |
| `verify` | Sin problemas | Se encontraron problemas | Archivo inexistente o corrupto |
| `restore` | Restaurado | Algún segmento falló | Base no está en el respaldo, sin MySQL |
| `status` | Todo bien | Algo requiere atención | — |
| `doctor` | Sin fallos (los avisos no cuentan) | Hay fallos | — |
| `migrate` | Migrado y comprobado | Fallos o recuentos que no cuadran | Destino no preparado |
| `deploy` | Desplegado | — | Sin SSH, sin rsync |
| `config --check` | Válida | Inválida | — |
| `restic` | Volcado | — | Sin root, sin HestiaCP, ningún `restic.conf` |

## Usarlos

```bash
# Lo esencial en cron
backupctl backup || echo "Respaldo FALLIDO en $(hostname)"

# Encadenar solo si el anterior fue bien
backupctl backup && backupctl verify --quick

# Distinguir los tres casos
backupctl backup
case $? in
    0) echo "correcto" ;;
    1) echo "respaldo incompleto: revisar el log" ;;
    2) echo "no se pudo ejecutar: revisar el entorno" ;;
esac
```

!!! tip "`status` como comprobación externa"
    ```bash
    backupctl status >/dev/null || curl -fsS https://hc-ping.com/xxx/fail
    ```
    Devuelve `1` si el respaldo se está quedando viejo, si MySQL no responde, si
    el disco anda justo o si el último log tenía errores.

## Distinguir 1 de 2

Es la distinción más útil de todas:

- **`1`** — el sistema funcionó y encontró un problema **con los datos**. Un
  respaldo incompleto, un archivo corrupto, un recuento que no cuadra. Hay algo
  que investigar en el contenido.
- **`2`** — el sistema **no pudo trabajar**. Falta una orden, MySQL no responde,
  no hay espacio, la configuración es inválida. Hay algo que arreglar en el
  entorno.

Un `2` recurrente en cron casi siempre es entorno: `PATH` distinto, credenciales
caducadas o disco lleno. Empieza por `backupctl doctor`.
