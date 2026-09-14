# 0007 — `master` es la rama estable; se trabaja en ramas propias

- **Estado:** Aceptada
- **Fecha:** 2026-09-14
- **Decide:** Product Owner
- **Estructural:** sí (cómo se trabaja con git)

## En cristiano

La rama `master` es siempre la versión estable: la que el PO despliega en sus servidores. El
trabajo se hace en otras ramas, que los agentes crean, commitean y fusionan con libertad, pero
solo llega a `master` lo que está terminado y comprobado. Lo que cambia el comportamiento en un
servidor espera en su rama hasta que el PO lo haya probado. Subir a GitHub lo hace solo el PO.

## Contexto

- Hasta hoy los 47 commits se hicieron directamente en `master`
  (`docs/desarrollo/repositorio.md`, «Ramas», proponía ramas solo para cambios grandes).
- El PO, el 2026-09-14: «Master rama estable (ustedes pueden mergear y commitear cuando
  quieran, pero estable)». Y sobre subir: «Solo yo».
- Los agentes no pueden probar en un servidor (ADR 0006).

## Decisión

- **Ramas de trabajo** creadas desde `master` por el coder, con el nombre que diga la
  instrucción: `<tipo>/<tema>` en kebab-case (`feat/…`, `fix/…`, `docs/…`, `chore/…`).
- **Fusión** a `master` con `git merge --no-ff <rama>`, hecha por el coder cuando la
  instrucción lo ordene, si se cumple todo:
  1. `verificar.sh` en verde en la rama y, tras fusionar, en `master`;
  2. revisión de `code-reviewer`, y de `security-auditor` si toca lo que corre con
     privilegios, credenciales, `ssh` o la web;
  3. **si cambia lo que se ejecuta en un servidor o contra él, la conformidad del PO tras
     probarlo** con la guía de la ronda (ADR 0006). Documentación, configuración de agentes,
     pruebas y herramientas locales no la necesitan.
- Sin `rebase`, `squash` ni reescritura (siguen prohibidos).
- **`git push`, solo el PO.** Borrar o renombrar ramas, también.

## Alternativas descartadas

| Alternativa | Por qué no |
| --- | --- |
| Seguir todo en `master` | Contradice la decisión del PO: `master` dejaría de ser desplegable a mitad de una tanda |
| Fusionar sin esperar la prueba del PO lo que toca servidores | `master` pasaría a contener código que nadie ha ejecutado en un servidor |
| Rama `develop` permanente | Una rama más que sincronizar para un solo PO |
| Fusionar con `rebase` o `squash` | Reescribe o aplana la historia; los commits atómicos son el registro de cada ronda |

## Consecuencias

- Una rama puede quedarse días esperando la prueba del PO: `estado/AHORA.md` dice cuáles.
- Varias ramas vivas a la vez pueden chocar al fusionar; el arquitecto las ordena.
- `docs/desarrollo/repositorio.md`, «Ramas», se actualiza con esta decisión.

## Reversión

Volver a trabajar en `master`: fusionar las ramas abiertas y quitar la sección «Ramas» de
`30-protocolo-coder.md`, este criterio de `40-salvaguardas.md` §3 y la de
`docs/desarrollo/repositorio.md`. No afecta al remoto.

## Verificación

`git log --first-parent master` posterior a este ADR solo muestra fusiones; los reportes del
coder muestran la rama de la instrucción.
