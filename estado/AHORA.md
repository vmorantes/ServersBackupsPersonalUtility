# Ahora

> **Para retomar: `/abrir-jornada`.** Esta skill lee este archivo y exige que conteste las ocho
> preguntas de abajo. Si alguna no se contesta aquí, **el estado falló y arreglarlo es el primer
> trabajo del día**.

- **Actualizado:** 2026-10-17, noche, al enviar `#148`.
- **Formato:** contrato de `cerrar-jornada` §2.2. Tope: 200 líneas.

## Al retomar — el primer paso, uno solo

1. Comprobar los dos nombres de sesión (§1) en la lista de sesiones, y **medir si hay coder**.
2. `bash .agents/scripts/verificar.sh` — tiene que salir en verde.
3. Comprobar que la ronda de cierre `#146` llegó a commitearse (§2). Si no, pedir su reporte.
4. Seguir lo que el PO conteste en «Espera al PO».

## Espera al PO

1. **Lunes 2026-10-19: la migración del servidor grande.** Todo en
   `docs/migracion/caliente.md` (sitio: Migración → Migración caliente de cuentas), desde la rama
   `feat/migracion-caliente`. Primero el analizador con `--rapido` en el origen; empezar por la
   cuenta más pequeña. Lo añadido (analizador, `codeigniter3`, arreglos de `plan`/`verificar`, cron
   suspendidos) **nunca ha corrido en un servidor**: la guía lo dice arriba.
2. **El DNS no se migra** y ese servidor sirve sus zonas. El alta del dominio en el destino crea
   una zona desde plantilla, y añadir registros encima los duplica (dos MX). Hay que REEMPLAZAR los
   registros de cada zona por los del origen, con la IP nueva: procedimiento en la guía, «Recrear
   una zona en el servidor nuevo», **nunca probado**; primero con una zona poco importante.
   Ya hay herramienta: `recrear-zonas.sh`, pasos en la guía, «Recrear una zona en el servidor
   nuevo». Sin probar en servidor: una zona poco importante primero, sin `--aplicar`.
3. **Dominios con el correo en Microsoft 365**: en su propuesta, `eliminar_mail="true"` y
   `correo="false"`. CONFIRMADO en la fuente: con dominio de correo local, el servidor no manda al
   MX lo que él mismo envía a ese dominio (`50-hestiacp.md`, «Zonas DNS al migrar»).
4. **Rotar las credenciales que estuvieron versionadas**: las claves S3 de los `rclone_*.conf` y
   las contraseñas de Restic del perfil `TejidoTesting`. Siguen en la historia de git y en el
   remoto (ADR 0020).
5. **Secretos en `HestiaCPCliMigrationUtility`**: su `MIGRACION.sh` versionado lleva seis
   contraseñas de base de datos reales y tres dominios reales, en cuatro commits (A-018 §2).
6. **`git push`** de `release/2.1` y de `feat/migracion-caliente`. Lo que falta por subir de
   verdad solo lo sabe el PO: aquí no se refresca el remoto. Para medir lo local:
   `git rev-list --count master..feat/migracion-caliente`.
7. **La migración del 2026-10-02**: `migraciones/PENDIENTES.md` (fuera de git, datos reales).
   Fases A y B antes de apagar el servidor viejo.
8. **`rm ~/.local/bin/backupctl`** — resto de una «prueba» que nunca debió ejecutarse.
9. **Bajarse el `.tgz` de las claves** fuera del servidor que protegen.

## 1. Sesiones

El renombrado es **obligatorio para trabajar** (PO, 2026-09-24).

```
/rename ServersBackupsPersonalUtility-Arquitecto-Main
/rename ServersBackupsPersonalUtility-Coder-Main
```

Tras un `/clear` no hace falta renombrar. Hace falta si la sesión se mató. El nombre **no
sustituye a la identificación**: al coder se le pide un dato verificable antes de la primera
instrucción. El coder de hoy se identificó en `#124→#125`.

## 2. En vuelo

**`#154`: commitear la documentación de las zonas** (`docs/migracion/caliente.md`,
`tools/migracion-caliente/README.md`) y este estado. Código ya hecho y revisado: `164f7cf`
(analizador exporta zonas), `18b9792` y `0e79e79` (`recrear-zonas.sh`, endurecido tras revisión;
122 afirmaciones). Reporte esperado: `#155`.

Tramo: `estado/tramos/2026-10-17-1700-migracion-caliente.md`, rondas `#124`–`#155`.

## 3. Contadores

- **`#NNN`, cadena con el coder.** Último usado: **#154**. El próximo: **#155** (reporte).
  El `#123` se emitió y el canal lo descartó: consume número igual.
- **`A-NNN`, mensajes al PO.** Último usado: **A-036**. El próximo: **A-037**.

Los mensajes etiquetados `#082` y `#083` del 2026-10-17 son en realidad el `#103` y el `#104`
(tramo del andamiaje, hallazgo 1).

## 4. Qué espera al PO

Arriba, en «Espera al PO». Si cambia, se cambia en los dos sitios o en ninguno.

## 5. Mandato vigente

- **PO, 2026-10-17**: unificar aquí las dos vías —respaldos y migración caliente—, con la otra
  herramienta como subherramienta y un analizador de solo lectura delante (ADR 0018). Urgencia: el
  lunes 2026-10-19. Regla del PO: la herramienta nunca toca el servidor viejo (ADR 0019).
- **PO, 2026-10-17**: las claves de los respaldos fuera del repositorio, obtenidas por él sin pasar
  por los agentes (ADR 0020). **Después del lunes.**
- **Aparcado**: la fase 2 de la 2.1 (ADR 0013), sin servidor de pruebas donde ensayarla.

## 6. Qué falta, medible

### Para el lunes

1. Hecho y commiteado en `feat/migracion-caliente`: copia intacta (13/13 sumas, `d3461b8`),
   `codeigniter3` (`3be710b`, `6220a9e`), falso OK de `verificar` (`641733a`), analizador
   (`dd414c2`, `51e0b2a`), IP de destino vacía (`c02449c`), cron suspendidos (`2efdc4b`), guía.
2. **Zonas DNS**: HECHO (`recrear-zonas.sh`), sin probar en servidor. Antes: La vía verificada (reemplazar el `.conf` de la zona y regenerar)
   está en `50-hestiacp.md`. Depende de la respuesta del PO (Espera §2).
3. `IP_ORIGEN="REVISAR_IP_ORIGEN"` cuando no se lee ninguna IP: dejar vacío (roadmap).

### Después del lunes

Roadmap, secciones «Migración caliente» y «Claves de los respaldos fuera del repositorio».

### Del andamiaje (frente que el PO no ha nombrado)

La guarda, **tres defectos**, que frenaron el trabajo varias veces más el 2026-10-17:
- **A**: confunde el contenido de un texto con una orden (bloqueó escribir `scp`, `backupctl`,
  órdenes del panel y una de git en documentos y estado).
- **B**: no distingue la ruta de un borrado legítimo, ni el directorio real cuando el cwd es otro.
- **C**: `REDIRECCION_AL_SISTEMA` (`guardia.py:89`) bloquea toda redirección a `/var/…`, y el
  repositorio vive en `/var/www/html/`.
- Y no deja restaurar un archivo concreto con checkout (lo trata como el árbol entero).

## 7. Decidido y sin implementar

- **ADR 0020**: el método para que el PO obtenga las claves de los respaldos. Hoy `lib/restic.sh:40`
  las escribe en `<perfil>/output/HestiaCP/` y `adoptar` las busca ahí.
- **ADR 0018 §6**: unificar la migración caliente con la CLI y la web.
- **ADR 0013**: la fase 2 sin terminar; fases 3 y 4 sin empezar.
- **ADR 0015** (interfaz por tareas): sin empezar; necesita una sesión de diseño con el PO.
- **La web puede contradecir a la línea de órdenes** (lee el servidor por su cuenta). Decisión del
  PO (2026-09-24): fase 3. Mientras tanto, si discrepan, manda `hestia status`.

## 8. Trampas del área en curso

- **Migración caliente**: la cabecera de `BASE_GENERAL.sh` está desfasada (dice «dos fases» y que
  la fase 2 recopia archivos; no lo hace). Manda el código, y la guía ya lo dice.
- **Los helpers PHP están duplicados** entre `BASE_LEER_CONFIG.sh` y `BASE_CONFIGURAR_DB.sh`, ahora
  también con lógica (guardas de `codeigniter3`). Un tipo registrado en uno solo falla asimétrico.
- **El paquete del analizador se construye justo antes de subirlo**: un paquete viejo miente. El
  informe dice de qué commit sale.
- `.agents/context/50-hestiacp.md`, sección «Leer un HestiaCP sin escribir nada»: lo verificado
  **no se vuelve a verificar**. Las listas del panel escriben en `error.log` si se consulta algo
  que no existe; el analizador no usa ninguna.
- `.agents/context/30-trampas.md`, T1 (credenciales) y T20–T26.
- `.agents/context/20-convenciones.md`: «vacío» y «no lo sé» no se escriben igual.
- `core.fileMode=false` en la copia de trabajo: un bit de ejecución solo llega a git con
  `git update-index --chmod=+x`.

## La lección que no se poda

**Una corrección parcial que se anuncia como completa es peor que no corregir**, porque quien
la lee se fía. Y un documento correcto en lo que afirma puede ser peligroso por lo que omite.
Las dos costaron un servidor del PO cada una. El 2026-10-17 el arquitecto volvió a escribir en la
guía del lunes una frase que no había medido («y lo dice en el plan»); la cazó la lectura en frío
del coder. El relato entero, en `abrir-jornada` §7.

## Para una sesión nueva

Lee este archivo, el último de `estado/tramos/`, y los ADR **0018, 0019 y 0020**. Luego
`.agents/README.md` para el orden del resto.
