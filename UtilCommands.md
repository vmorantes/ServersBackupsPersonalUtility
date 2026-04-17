# Comandos útiles

## Bash

- Darle permisos de ejecución a todos los .sh en el directorio actual y subdirectorios
```bash
find . -wholename "**/*.sh" -exec chmod +x {} \;
```