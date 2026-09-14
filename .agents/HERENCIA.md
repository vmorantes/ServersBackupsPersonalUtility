# Herencia

> **Este documento se puede borrar.** No es historia del proyecto —esa es `git log` y, desde
> la adopción, la bitácora— sino el traspaso de lo que sabía la sesión que construyó
> `backupctl` y no estaba escrito en ningún archivo del repositorio.

- **Fecha:** 2026-09-14
- **Fuente:** las respuestas de esa sesión al arquitecto (2026-09-14) y las tres notas de su
  memoria nativa de Claude Code en esta máquina. Lo que se pudo, se contrastó con el código
  (se indica). Sin datos de los servidores del PO.

## Cuándo se puede borrar

| Lo que aporta | Deja de importar cuando… |
| --- | --- |
| Qué exige el PO | Esté en `rules/` y `context/` y se cumpla sin recordatorio (hoy ya está: `40-salvaguardas.md` §7, `context/20-convenciones.md`) |
| En qué se falló | Cada fallo tenga su prueba o su guarda, y pasen meses sin que vuelva |
| Lo que quedó a medias | Esté cerrado o descartado en el roadmap |
| Cómo se probaba | Exista un banco de pruebas local reutilizable, o el ADR que decida cómo se prueba contra servidores |

Quien lo borre escribe una entrada de bitácora diciendo por qué ya no hacía falta.

---

## Cómo se trabajó

- Una sola sesión de agente, del 2026-09-05 al 2026-09-10 (los tres primeros commits, de
  2026-04-17, son los scripts sueltos que `backupctl` sustituyó). Decidía, implementaba,
  probaba y commiteaba; la continuidad vivía en su conversación y en su memoria nativa.
- **Probaba contra un servidor real**: el perfil `TejidoTesting` apunta a un VPS con HestiaCP
  real que el PO puso a disposición para pruebas. Ahí se ejecutaron de verdad `deploy`,
  `backup`, `adoptar` y otras órdenes, **con permiso explícito del PO en cada tanda** (sus
  palabras al preguntarle: «Haz lo que debas», «Prueba»). El resultado se verificaba por
  fuera: conteos SQL, sumas, el panel de HestiaCP. Nunca por el mensaje de la herramienta.
- Para lógica que no convenía arriesgar en el servidor (el remapeo de IP de
  `lib/adoptar.sh`), se extraía el fragmento bash y se ejecutaba sobre un árbol sintético en
  un temporal, con `v-list-user-ips` / `v-list-sys-ips` falsos. Se montó y se borró en cada
  ocasión: **no queda nada reutilizable** (sin Docker, Vagrant ni devcontainer).
- Versión de HestiaCP contra la que se verificó: **1.10.4** (citada en los comentarios de
  `lib/hestia.sh:217,441,503,706` y `lib/adoptar.sh:14`).

## Qué exige el PO

Pasado a `.agents/rules/40-salvaguardas.md` §7 y a `.agents/context/20-convenciones.md`.

1. **Nada fuera del directorio del proyecto sin permiso explícito**, ni «probando».
2. **Estados claros, no destruir**: toda acción muestra lo que ya hay configurado, con el
   valor real leído del servidor, antes de ofrecerse; si pisa algo, lo dice con el valor que
   se pierde delante. Motivo: la configuración de Restic del panel es una sola para todo el
   HestiaCP, y un botón la sustituía para todas las cuentas sin avisar (2026-09-06).
3. **Las operaciones reales las ejecuta él**, desde la interfaz web: migrar, restaurar datos
   de producción. El agente prueba antes en el servidor de pruebas, verifica por fuera y le
   entrega una guía que separa lo probado de lo no probado. «No puedo auditar tu código, solo
   decirte lo que quiero»; «dame la GUÍA A MÍ».
4. **La interfaz web es el centro.** «Soy anti CLI. CLI es para servidores, no para
   personas.» Todo lo que hace `bin/backupctl` debe poder hacerse desde `web/`, con botones
   atomizados por acción para evitar accidentes.
5. **Documentación agnóstica**: ningún nombre de servidor, dominio, cuenta ni base de datos
   real. Se purgó dos veces (unos 38 archivos) tras filtrarse. Ni placeholders con el nombre
   del PO.

## En qué se falló

| Fallo | Red hoy |
| --- | --- |
| Una «prueba» de `backupctl install` creó `~/.local/bin/backupctl` en el sistema del PO, confirmando la propia sesión el diálogo (2026-09-05) | Regla 40 §2; guarda de hooks |
| La herramienta dio éxitos en falso: el aviso de prueba decía «enviado» sin enviar (`bc52491`); fallos que solo se vieron contra un servidor (`20f486d`) | Verificar por fuera; `context/30-trampas.md` |
| Nombres reales del PO filtrados a `docs/` | Regla 40 §1; purga en `d238a69` y siguientes |
| El modelo de Restic de HestiaCP y la ubicación de su cron, supuestos y corregidos después (`b125085`, `86faa09`) | `hestia-verifier`; `context/50-hestiacp.md` |

Las trampas técnicas que contó la sesión están en `.agents/context/30-trampas.md`.

## Lo que quedó a medias (al 2026-09-14)

Pasado a `.agents/docs/roadmap.md` y a «Espera al PO» de `estado/AHORA.md`.

- **La migración real de la cuenta grande** del servidor de pruebas (23 dominios, 14 bases,
  unos 10 GiB) no se ha ejecutado; de punta a punta solo se probó una cuenta pequeña. La guía
  está en `docs/hestiacp/tres-escenarios.md` y la ejecuta el PO.
- **Sin probar contra un servidor**: buzones de correo y DKIM, certificados SSL, alias web,
  cuentas grandes, y el remapeo de IP en una restauración real (solo con datos sintéticos).
- **El servidor de pruebas se va a dar de baja.** Mientras siga encendido, su retención de
  Restic poda cada noche; las instantáneas buenas de la cuenta grande desaparecen hacia
  principios de octubre de 2026.
- **Dos bloqueos de Restic sin liberar** en los repositorios de dos cuentas de ese servidor,
  de transferencias interrumpidas. Se dejaron a propósito: si frenan la poda nocturna,
  protegen las copias buenas hasta que el PO decida.
