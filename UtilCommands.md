# Comandos útiles

> Este archivo se conserva por costumbre. El recetario completo y actualizado
> está en la documentación:
>
> ```bash
> mkdocs serve      # http://127.0.0.1:8000 → Guías → Recetas
> ```
>
> O directamente en [`docs/guias/recetas.md`](docs/guias/recetas.md).

## Lo que más se usa

```bash
backupctl                      # menú interactivo
backupctl status               # ¿estoy protegido?
backupctl doctor               # ¿qué está mal?
backupctl backup               # respaldar
backupctl verify               # comprobar el último respaldo
backupctl list                 # qué respaldos tengo
backupctl inspect              # qué hay dentro del último
backupctl restore '' <bd>      # restaurar
backupctl logs --errors        # qué falló la última vez
```

## Bash

```bash
# Permisos de ejecución a todos los .sh
find . -name '*.sh' -exec chmod +x {} +

# Comprobar la sintaxis de todo sin ejecutarlo
bash -n bin/backupctl lib/*.sh && echo "sintaxis correcta"

# Análisis estático
shellcheck bin/backupctl lib/*.sh
```

## Documentación

```bash
mkdocs serve                   # servir en local con recarga automática
mkdocs build --strict          # compilar y fallar ante cualquier aviso
```

> En crontab, un `%` sin escapar se convierte en un salto de línea y parte la
> orden. `backupctl` escribe su propio log precisamente para que la línea de
> cron no necesite ninguna fecha.
