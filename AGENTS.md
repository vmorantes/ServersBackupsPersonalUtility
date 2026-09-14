# AGENTS.md

Entrada para agentes de cualquier proveedor. Claude Code lee además `.claude/CLAUDE.md`.

**Qué es esto**: `backupctl`, una herramienta bash (`bin/`, `lib/`) que respalda, verifica,
restaura y migra bases de datos y cuentas de servidores HestiaCP, con una interfaz web local
en Python (`web/`). Se despliega en servidores de producción, a veces con `sudo`, y maneja
credenciales de MySQL, Restic, S3 y SSH.

**Cómo se trabaja**: tres roles —Product Owner, arquitecto, coder— con el protocolo de
`.agents/rules/30-protocolo-coder.md` (ADR 0001). Si llegas como coder, lo que te llega es
tu instrucción completa: no decides arquitectura ni escribes documentación.

## Antes de tocar nada

1. `estado/AHORA.md` — qué está pasando ahora y qué número de mensaje toca.
2. `.agents/rules/` completo. Las que no se negocian: `40-salvaguardas.md`.
3. `.agents/README.md` — el resto, en orden.

## Lo que no se hace nunca

- Conectarse a un servidor, a MySQL o al almacenamiento remoto (`ssh`, `rsync` remoto,
  `mysql`, `mysqldump`, `restic`, `rclone`), ni ejecutar órdenes de `backupctl` distintas de
  `--help`, `version` y `profiles`.
- Leer, imprimir o copiar los `env.sh` de los perfiles, `<Perfil>/output/HestiaCP/`,
  `ESTADO.md` o `.git/config`: tienen credenciales reales.
- `sudo`, instalar paquetes, escribir fuera del repositorio y de `/tmp`.
- Cambiar el estado de git sin orden; `git push`, nunca.
- Mencionar a una IA en código, documentación para personas o commits.

## Verificación

```
bash .agents/scripts/verificar.sh
```

Su salida real va en cada reporte.
