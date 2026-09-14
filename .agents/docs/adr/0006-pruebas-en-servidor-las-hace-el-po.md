# 0006 — Las pruebas contra un servidor las hace el PO

- **Estado:** Aceptada
- **Fecha:** 2026-09-14
- **Decide:** Product Owner
- **Estructural:** sí (cómo se trabaja)

## En cristiano

Ningún agente ejecuta nada contra un servidor, tampoco contra el de pruebas. El coder prueba
en esta máquina, en aislado, con datos falsos. Lo que solo se puede comprobar en un servidor
lo prueba el PO, siguiendo una guía que le dice qué hacer, qué debería ver y cómo comprobarlo
por fuera. Así ninguna prueba puede tocar un servidor sin que el PO esté delante.

## Contexto

- Hasta el 2026-09-13, la sesión que construyó el proyecto probaba `deploy`, `backup`,
  `adoptar` y otras órdenes contra un servidor de pruebas real, con permiso del PO en cada
  tanda (`.agents/HERENCIA.md`).
- Ese servidor tiene cuentas y datos reales, y los perfiles guardan credenciales de
  producción (ADR 0008). Ningún `--dry-run` de `backupctl` está libre de efectos
  (`.agents/context/30-trampas.md` T4).
- La guarda (ADR 0003) ya bloquea toda conexión. Se estudió cómo autorizar pruebas puntuales
  y no hay un mecanismo del que se pueda garantizar que funciona (ver alternativas).
- El PO, el 2026-09-14: «Prefiero probar yo si no hay garantía de seguridad».

## Decisión

Los agentes no se conectan a ningún servidor ni ejecutan órdenes de `backupctl` con perfil.
Toda ronda que cambie lo que se ejecuta en un servidor o contra él termina con una **guía de
comprobación para el PO** en `estado/AHORA.md`: pasos (primero por la web), qué debe verse y
cómo verificarlo por fuera (conteos, sumas, el panel). Esa rama no se fusiona hasta que el PO
confirma el resultado (ADR 0007).

## Alternativas descartadas

| Alternativa | Por qué no |
| --- | --- |
| Permiso del PO por tanda, como antes | El permiso vive en el chat, no en una barrera; ya hubo una «prueba» que escribió en el sistema del PO sin permiso |
| La guarda pregunta al PO antes de cada conexión (`permissionDecision: "ask"`) | La documentación no garantiza qué hace en modo automático ni en una sesión sin nadie mirando (consultado el 2026-09-14) |
| Un archivo de autorización que solo escribe el PO y la guarda lee | La guarda no puede demostrar quién escribió el archivo; y una orden autorizada sigue usando credenciales de producción |

## Consecuencias

- El banco de pruebas local deja de ser una comodidad: es la única forma de que el coder
  pruebe algo más que la sintaxis. Es la primera tarea de producto (roadmap).
- La información de si algo funciona en un servidor tarda más en llegar: depende de que el PO
  pruebe.
- Las guías de comprobación se convierten en un entregable de cada ronda que toca servidores.

## Reversión

1. Un ADR nuevo que la reemplace y diga con qué garantía se permite probar en un servidor.
2. Ajustar `guardia.py` y `probar_guardia.py` a ese mecanismo, y las reglas 30 y 40.
3. Comprobar que `verificar.sh` pasa.

## Verificación

`probar_guardia.py` bloquea `ssh`, `backupctl <orden con perfil>` y `web/server.py`; los
reportes que tocan servidores terminan con una guía para el PO.
