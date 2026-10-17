# Migración caliente

La vía rápida para llevar cuentas de un servidor HestiaCP a otro: cuenta, dominios con su
versión de PHP, archivos, bases de datos, correo, cronjobs y certificados, **de servidor vivo a
servidor vivo**, sin pasar por un respaldo. La vía larga —respaldos que se guardan, se verifican
y se restauran— es `backupctl`.

## De dónde viene

Es una copia intacta de la herramienta `HestiaCPCliMigrationUtility`, commit `1474e4c`, la que
migró tres cuentas reales entre dos HestiaCP 1.10.5 el 2026-10-02. Los módulos `BASE_*.sh`,
`construir.sh` y `crear.sh` son **byte a byte** los de ese commit. Lo que se cambie a partir de
aquí va en commits propios, cada uno con su prueba.

No se trajo su historia, ni su archivo de migración de ejemplo, que llevaba datos reales. En su
lugar está `migracion-ejemplo.sh`, con nombres ficticios.

## Cómo se usa, en una línea

Se describe la migración en un archivo (`crear.sh` ayuda a generarlo), `construir.sh` lo
empaqueta en un único archivo ejecutable, ese archivo se sube al servidor de **destino** y se
ejecuta allí como root, por fases: `plan`, `1`, `sincronizar`, `2`, `verificar`.

## Cuidado

- **El paquete construido lleva las contraseñas de las bases de datos en claro.** Este
  directorio ignora `*.paquete.sh` y `migracion-*.sh` (salvo el ejemplo) para que nunca se
  versionen. En el servidor, se borra al terminar.
- Los puntos débiles conocidos, de la migración del 2026-10-02, están en
  `.agents/docs/mejoras-herramienta-migracion.md`. El que más importa: **forzar HTTPS no
  comprueba que haya certificado**.
- El tipo `piecesphp` **no** sirve para CodeIgniter 3: busca otra forma de configuración y otra
  ruta. Falla en voz alta, sin escribir.
