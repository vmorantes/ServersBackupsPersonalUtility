# 0020 — Las claves de los respaldos no viven en el repositorio

- **Estado:** Aceptada (sin implementar)
- **Fecha:** 2026-10-17
- **Decide:** Product Owner
- **Estructural:** sí (dónde viven las credenciales)
- **Reemplaza:** 0008, en lo que toca a las claves de los respaldos

## En cristiano

Las claves con las que se abren los respaldos (contraseñas de Restic, configuración de rclone
con las claves del almacenamiento) ya no se guardan en el repositorio. La herramienta tiene que
darle al PO una forma de obtenerlas él mismo, sin que pasen por los agentes, para guardarlas
aparte.

## Mandato

PO, 2026-10-17, al borrar el único perfil versionado: «nuestra herramienta no puede depender de
guardar llaves en claro en mi repo. Tiene que tener un metodo para que YO en algun punto las
respalde a mano.» Y al precisar: «Me refiero a las claves de los respaldos. Debería obtenerlas
de alguna forma sin que pasen por tus manos y guardarlas yo aparte.» Orden: **después de la
migración del 2026-10-19**.

## Qué cambia respecto al 0008

- **Hecho** (`c603d4f`): retirado del árbol el perfil del servidor de pruebas, y
  `*/output/HestiaCP/` ignorado por git. Ninguna clave de respaldo puede volver a versionarse.
- **Sin cambiar**: el 0008 sigue valiendo para `env.sh` de los perfiles hasta que el PO diga
  otra cosa. Hoy no hay ningún perfil versionado.
- **Sin implementar**: hoy `lib/restic.sh:40` escribe las claves en
  `<perfil>/output/HestiaCP/`, y `adoptar` las busca ahí (`lib/adoptar.sh:149`) para recuperar
  un servidor. La herramienta **depende** de que estén en esa carpeta. El diseño del método
  (dónde las deja, cómo se las lleva el PO, cómo las encuentra `adoptar`) está por hacer, con
  su propio ADR o una revisión de este.

## Consecuencias

- Lo que se versionó hasta hoy **sigue en la historia de git y en el remoto**. Rotar esas
  credenciales es del PO; avisado el 2026-10-17.
- `docs/desarrollo/repositorio.md` ya dice que las claves no se versionan.

## Reversión

Quitar `*/output/HestiaCP/` de `.gitignore`. No se recomienda.
