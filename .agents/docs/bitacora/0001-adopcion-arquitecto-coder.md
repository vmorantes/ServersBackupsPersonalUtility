# 0001 — Adopción del modelo arquitecto-coder

- **Fecha:** 2026-09-14
- **Pedido por:** Product Owner
- **ADR relacionados:** 0001–0008

## Qué se pidió

«Te pegué acá `.vscode`, `.agents`, `.claude`, que es una metodología de trabajo agéntica que
uso en otros repos. Obviamente hay que adaptarlo a este.» Con permiso para consultar a la
sesión que había construido el proyecto.

## Qué se encontró al explorar

- El andamiaje pegado describía otro proyecto: plugins PHP de HestiaCP, `panel.php`,
  instaladores. Sus ADR, herencia y contexto habrían sido leídos como verdad por cualquier
  agente.
- La guarda pegada ya estaba activa para todas las sesiones del directorio: bloqueó un `ssh`
  de la sesión anterior el mismo día.
- En este proyecto, a diferencia del otro, el agente probaba contra un servidor de pruebas
  real con permiso del PO por tanda. Copiar «ningún servidor» era una decisión de producto:
  se preguntó (ADR 0006).
- Credenciales reales versionadas en el perfil `TejidoTesting` y un token en la URL del remoto.
  El PO decidió mantenerlas (ADR 0008).
- Ningún `--dry-run` de `backupctl` es inocuo, y sin `-p` se usa el perfil real: la guarda no
  podía permitir órdenes de `backupctl` «en ensayo».
- 31 commits con `Co-Authored-By` ya en el remoto: `menciones_ia.py` habría fallado para
  siempre. Se acotó a los commits posteriores a `4435064`.
- No existe ninguna prueba automatizada.
- Lo que sabía la sesión anterior (exigencias del PO, trampas verificadas contra el servidor,
  trabajo a medias) solo estaba en su conversación y en su memoria nativa: pasó a
  `HERENCIA.md` y a `context/`.

## Qué se instruyó

#001 saludo al coder; #003 commitear la adopción en `chore/adopcion-arquitecto-coder` en seis
commits (agentes, documentación de agentes, editor, símbolo en docs, modelo de ramas, estado),
vaciando antes el índice que el PO había preparado para comparar, y fusionar con `--no-ff`.

## Qué reportó el coder

#004: completado sin desviaciones. `e26d637`, `4021253`, `4ebffe4`, `70c9967`, `b713923`,
`64ac581`; fusión `7977793`. `verificar.sh` en verde en `master`; symlinks con modo 120000.
Sin push.

## Qué quedó fuera

- La auditoría de lo marcado como SOSPECHA (T6) y los datos reales en el código (T7): roadmap.
- `docs/desarrollo/arquitectura.md` desactualizado: roadmap.
- `shellcheck`, `mkdocs build` en `verificar.sh`, hook `commit-msg`: decididos fuera por ahora.

## Aprendido

- Un andamiaje copiado de otro proyecto es más peligroso que ninguno: su documentación suena
  cierta. Hay que retirarlo entero, no parchearlo.
- La guarda de un repositorio con credenciales en el árbol tiene que vigilar también las
  lecturas (`Read`, `Grep`, búsquedas recursivas), no solo lo que escribe o ejecuta.
- Las pruebas de la guarda deben correr sobre un repositorio sintético: así no dependen de los
  datos reales del PO ni los tocan.
- Varias sesiones del mismo directorio y el propio PO pueden cambiar el índice de git a la vez:
  una instrucción que commitea debe empezar dejando el índice vacío y comprobándolo.
