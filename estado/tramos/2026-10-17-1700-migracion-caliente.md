# Tramo: la migración caliente

- **Inicio:** 2026-10-17, 17:00.
- **Mandato del PO:** «Quiero que unifiquemos funciones en este repo unicamente con ambas vias.
  Aquella otra herramienta puede ser una subherramienta de acá. […] hace falta algo, un
  "analizador" del estado de un HestiaCP de solo lectura». Decisión: ADR 0018.
- **Urgencia:** el lunes 2026-10-19 el PO migra un servidor muy grande (Joomla y muchos
  proyectos CodeIgniter 3.1.7). El destino aún no existe. Ya no hay servidor de pruebas.
- **Rama:** `feat/migracion-caliente`, desde `release/2.1`. No desde `master`, como dice ADR 0007
  por omisión: `master` no tiene el andamiaje (guarda, puertas, ADR) que este trabajo necesita.

## Rondas

| Ronda | Qué | Estado | Commits |
| --- | --- | --- | --- |
| #124→#125 | Identificación del coder | completado | — |
| #126→#127 | Entrada intacta de la herramienta, ejemplo saneado, ADR 0018 y estado | completado con desviación: los tres ejecutables entraron en 100644 | `e6afa65` `d3461b8` `e98fe28` `a5d74de` `0c93782` |
| #128→#129 | Restituir los modos; corregir fases, `forzar_ssl` y dos frases falsas del ejemplo | completado; 13/13 modos iguales al origen | `3079010` `76042f6` |
| #130→#131 | Tipo `codeigniter3` | **bloqueado por su propio gate**: la regla de `active_group` no cabe sin tocar el helper compartido. El coder paró, midió y trajo un prototipo probado | — |
| #132→#133 | `codeigniter3` con gancho de guardas en los dos helpers, suite y tres mutaciones | completado: 82 afirmaciones; M1, M2 y M3 muerden | `3be710b` `96e7908` |
| #134→#135 | T1 retirar `TejidoTesting`; T2 falso OK de `plan_dominio_existe`; T3 claves repetidas en CodeIgniter 3 | completado; 25 suites | `c603d4f` `641733a` `6220a9e` `80e1ccf` `d64dd19` |
| #136→#137 | El analizador de solo lectura, con su suite | completado: 79 afirmaciones; M1-M3 muerden; el coder encontró y arregló dos defectos propios leyendo un informe real | `9285e58` `0c3c85f` `dd414c2` `7fc5cd2` |
| #138→#139 | Sello de versión en el paquete del analizador; commitear guía y README | completado; la lectura en frío de la guía encontró cuatro cosas | `51e0b2a` `e7513d1` `cf0e16d` |
| #140→#141 | `IP_DESTINO` vacía en las propuestas; cron suspendido no se migra; correcciones de la guía | completado; 27 suites. La guía commiteada decía que el plan anuncia el cron suspendido: falso, lo escribió el arquitecto sin comprobarlo. Corregido después | `c02449c` `2efdc4b` `154bace` `afc6a3e` |
| #142→#143 | Cierre: commitear la guía corregida (con «Qué se migra y qué no»), ADR 0019 y 0020, roadmap y estado | completado salvo la guía: una frase decía que la herramienta nunca escribe en el origen; el coder no la commiteó | `bb006b6` `3d0612c` `8bec5e9` |
| #144→#145 | Segunda ronda de cierre: la guía corregida y la verificación de DNS en `50-hestiacp.md` | completado; la lectura en frío encontró que la guía decía qué hacer con las zonas y no cómo | `142ce15` `00b0f89` `086268b` |
| #148→#149 | Recrear zonas DNS en el destino (PO: «los DNS entran») | bloqueado en PASO 0: el arquitecto citó `#149` en el tramo sin subir el contador de `AHORA.md` (segunda vez hoy) | — |
| #150→#151 | Contador corregido; seguir con #148 | completado; revisión: restauración sin probar de verdad, órdenes del panel sin ruta (fallarían con sudo), salida 0 con fallo de respaldo | `fcaf260` `164f7cf` `18b9792` |
| #152→#153 | Arreglos de la revisión | completado; restauración probada (6 fallos con ella desactivada); el coder halló un aviso muerto suyo (variable en subshell) | `0e79e79` |
| #154→#155 | Commit de la guía de zonas y el estado | completado; lectura en frío: 3 discrepancias menores de la guía | `b338228` `1137d10` |
| #156→#157 | Commit de las tres correcciones | completado | `9a39d74` `1b21ad9` |
| #158 | Ronda de cierre: estado, tramo, roadmap | en vuelo | ver `git log` |
| #146→#147 | Tercera ronda de cierre: procedimiento para recrear una zona en la guía | ronda de cierre | ver `git log` |

## Hallazgos

1. **La otra herramienta tiene secretos reales versionados.** Su `MIGRACION.sh` lleva seis
   contraseñas de base de datos que no son marcadores y tres dominios reales, en cuatro commits
   de su historia. Medido sin imprimir ningún valor. Avisado al PO en `A-018`. Decide cómo se
   trae: copia sin historia (ADR 0018 §1).
2. **Su tipo «PiecesPHP / CodeIgniter» no es CodeIgniter 3.** Forma `$config['database']…` y
   ruta `app/config/`; CodeIgniter 3 usa `$db['default']` en `application/config/`. Su opción
   `ruta_db` arregla la ruta, no la forma. Falla en voz alta, no corrompe.
3. **La guarda tomó un `grep -r .` en otro repositorio por la raíz de este** (cwd distinto).
   Variante del defecto B: no mira el directorio real. No se esquivó: se buscó sobre archivos
   nombrados.

4. **13 de 13 sumas iguales** al commit de origen. Pero `core.fileMode=false` en esta copia de
   trabajo dejó el `chmod +x` solo en el disco: los tres ejecutables entraron en 100644. Lo vio el
   coder y no improvisó un commit fuera del plan. Afecta a todo el repositorio: un bit de
   ejecución solo llega a git con `git update-index --chmod=+x`.
5. **El ejemplo del coder se saltaba `sincronizar`** en la secuencia de fases, afirmaba que la
   herramienta no ejecuta con las contraseñas de marcador (sin verificar) y contaba una anécdota
   de PHP que no ocurrió. Lo vio el arquitecto leyendo el archivo, no el reporte.
6. **`forzar_ssl` solo es verdad con el literal `"true"`** (`cfg_si`, `BASE_CONFIG.sh:547`): una
   errata lo desactiva en silencio. Lo vio el coder.
7. **Precisiones al ADR 0018**, que no se edita: §3 «byte a byte» es verdad del contenido, y de
   los modos solo tras `#128`; §5 la ruta de `piecesphp` es `public_html/app/config/…`, relativa
   a la carpeta del dominio.
8. **Defecto C de la guarda**, nuevo: `REDIRECCION_AL_SISTEMA` (`guardia.py:89`) bloquea toda
   redirección a `/var/…`, y el repositorio vive en `/var/www/html/`. Muerde cada ruta absoluta.
   La línea 90 ya acota a `/var/lib`. Y el defecto A volvió a morder al arquitecto al escribir
   este mismo tramo. Sin tocar: frente (b), no nombrado.

9. **`sincronizar` borra en el destino lo que no exista en el origen** (`BASE_GENERAL.sh:999-1003`)
   y solo se puede repetir hasta apuntar el DNS. La cabecera del origen habla de «dos fases» y no
   la nombra: la secuencia real es de cinco pasos. Lo vio el coder; va a la guía del lunes.
10. **El tipo nuevo no se fía de `$active_group`**: si el proyecto no usa el grupo `default`, se
   niega. Y CodeIgniter 3 admite `application/config/<ENTORNO>/database.php`, que manda sobre el
   general: el analizador tiene que detectarlo.

11. **El helper de escritura no toca el `database.php`**: escribe un archivo aparte y el shell
    compara, copia y deshace. Y los patrones están **duplicados** entre lectura y escritura con
    sintaxis distinta: un tipo mal registrado en uno solo falla de forma asimétrica.
12. **Drupal y PrestaShop no anclan su patrón a un grupo**: con una segunda conexión en el
    archivo reescribirían la última, no la de `default`. Preexistente, sin tocar.
13. **Gancho de guardas, decidido por el arquitecto** (`#132`): aditivo, inerte para los tipos
    existentes (WordPress byte a byte igual con y sin él, prueba B3), y ampliado a la lectura,
    que el prototipo no cubría: sin eso se migraría la base de otro grupo sin error.

14. **Verificación de HestiaCP 1.10.5 para el analizador** (subagente, 2026-10-17). Las listas del
    panel no escriben si el objeto existe, pero **escriben en `error.log` si no existe**, y arman el
    json sin escapar. Los tamaños guardados son viejos. **Decisión: el analizador no llama a ninguna
    orden del panel**; lee los `.conf` y mide con `du`/`find`. Borrador para `50-hestiacp.md` en el
    scratchpad del arquitecto, depositado en `50-hestiacp.md` tras `#133`.
15. **Los buzones viven en `/home/<u>/mail/<dominio>/<cuenta>/` (Maildir).** Cierra el SIN VERIFICAR
    de MAIL del paso 8: excluir MAIL no impide que el correo entre en la instantánea, como WEB.
16. **`plan_dominio_existe` da «existe» para un dominio que no existe** (`BASE_PLAN.sh:50`): la
    salida de error del panel contiene el nombre buscado. Confirmado por lectura del arquitecto. No
    destruye (la fase 1 crea sin consultarla), pero el `plan` mentiría en un destino nuevo y
    `verificar` daría un falso OK. Va en la ronda siguiente, con su prueba.

17. **Clave repetida en el grupo `default`: se reescribe la que la aplicación NO usa.** En PHP gana la
    última; el patrón de array casa una vez por grupo y reescribe la primera. Código 0, parece bien.
    Lo vio el coder. Se cierra con una segunda guarda.
18. **La guarda no deja restaurar un archivo concreto con checkout**: no distingue un archivo del
    árbol entero. Las instrucciones no deben ofrecerlo mientras no se ajuste.
19. **El PO borró `TejidoTesting/` del disco** a mitad de la ronda `#132`. El coder lo vio, no lo
    restauró y lo reportó: exactamente lo que dice la regla. Mandato nuevo del PO: las claves de los
    respaldos fuera del repositorio, obtenidas por él sin pasar por los agentes. **Después del
    lunes.**

20. **El falso positivo tenía una segunda cara**: el punto del dominio actuaba como comodín y la
    ficha de un subdominio hacía «existir» al dominio padre. Lo encontró el coder al escribir un
    caso que nadie le pidió. Arreglado con `grep -F` en `641733a`.
21. **`docs/desarrollo/repositorio.md` decía que versionar las claves era «una decisión
    deliberada».** Corregido por el arquitecto, con el aviso de rotar lo que se versionó.

22. **`cfg_validar` no valida el valor de `php`, solo que no esté vacío.** Un centinela de texto
    habría sido aceptado y la migración habría corrido con una plantilla inexistente. El analizador
    deja `php=""`, que sí se rechaza. Lo midió el coder en el gate.
23. **La fase 2 NO vuelve a copiar archivos**, aunque la cabecera de `BASE_GENERAL.sh` diga que sí:
    está desactivada (`SINCRONIZAR_EN_FASE2`, línea ~2179) para no pisar lo escrito tras el corte.
    La guía lo dice. Comprobado por el arquitecto al escribirla.
24. **Un paquete viejo miente y no se nota**: el coder leyó un informe de un paquete construido
    antes de su propio arreglo. Se sella el paquete con la versión de la que sale (`#138`).

25. **Un cron SUSPENDIDO en el origen se crea ACTIVO en el destino** (`BASE_MIGRAR_CRON.sh:410-428`):
    la herramienta solo lo anota. Lo vio el coder leyendo la guía contra el código. Decisión del
    arquitecto para el lunes: **no migrarlo** y decirlo en el plan, sin añadir ninguna orden del
    panel nueva. Suspender en vez de omitir, después del lunes y verificado.
26. **`IP_DESTINO` solo se valida como no vacía**: el centinela de texto habría pasado. Las propuestas
    la dejan vacía, como `php`.
27. **La guía mandaba borrar el directorio de la corrida sin decir dónde está ni que guarda
    `deshacer.sh`.** Está en `/home/<cuenta>/migraciones/<fecha>/`. Corregido.

28. **La herramienta NO migra el DNS**: ni zonas ni registros (no hay ninguna orden de registros
    en su código). El servidor del lunes **sí sirve el DNS** (PO, 2026-10-17). El PO recrea zonas con
    órdenes de alta de registro una a una; su ejemplo real (con datos reales, no se copia aquí)
    muestra un dominio cuyo **correo vive en Microsoft 365**: un dominio de correo local en el
    destino entregaría en local lo que el servidor envíe a ese dominio. SIN VERIFICAR. Subagente
    `hestia-verifier` en curso: firma de las órdenes DNS, plantillas por defecto, copia fiel del
    `.conf` con regeneración, y cómo decide Exim si un dominio es local.
29. **También faltan en la guía**: cuentas FTP (no se migran) y la clave DKIM nueva.

30. **El arquitecto escribió en la guía «y lo dice en el plan» sin comprobarlo.** El plan solo cuenta
    los cron por usuario. Lo vio el coder en su lectura en frío. Es el error que la lección de
    `abrir-jornada` §7 describe: una afirmación plausible que nadie midió, en el documento que el PO
    va a seguir. Corregido.
31. **Queda `IP_ORIGEN="REVISAR_IP_ORIGEN"`** cuando el analizador no lee ninguna IP: mismo agujero
    que `IP_DESTINO`. Para la próxima ronda.
32. **Plan de DNS del PO** (2026-10-17): migrar A→B, cambiar NS a B, y en A apuntar todo a B mientras
    propaga; A vence el 29. Requiere que B tenga las zonas completas: la herramienta no las copia.
33. **Regla del PO (2026-10-17): la herramienta nunca toca el servidor viejo.** Solo escribe en B;
    los cambios en A los hace él. Medido: hoy solo lee en A, salvo un temporal con la contraseña de
    MySQL en modo "user" (`BASE_PRIVILEGIOS.sh:811-826`), borrado por `trap EXIT` (949). Se retira la
    propuesta de generar un script para A.

34. **Verificación de DNS en la fuente** (subagente, depositada en `50-hestiacp.md`): el alta del
    dominio crea zona desde plantilla; añadir registros duplica; la copia fiel es reemplazar el
    `.conf` y regenerar; Exim trata como local todo dominio con dominio de correo y no consulta el
    MX. El ejemplo de DNS del PO, aplicado sobre esa zona, dejaba dos MX.
35. **Tercera afirmación absoluta del arquitecto en la guía, el mismo día**: «nunca modifica el
    servidor viejo», contradicha por su propio ADR 0019. La cazó el coder en la ronda de cierre.

36. **Segundo tramo (18:30-19:45): zonas DNS.** El PO preguntó si estaba listo; respuesta NO por el
    DNS. PO: «Sí, los DNS entran» (A-033). Verificación en la fuente: `v-insert-dns-records` da
    falso éxito si el archivo no existe (por eso el script compara con `cmp`); el rebuild ignora
    el reinicio. Depositado en `50-hestiacp.md`.
37. **Revisión del código del coder** (`#151`): las pruebas de restauración no la ejercitaban;
    órdenes del panel sin ruta (fallarían con `sudo`); salida 0 con fallo de respaldo. Arreglado en
    `#152→#153`; el coder halló además un aviso muerto suyo (variable dentro de `$(...)`).
38. **Fallo propio, otra vez**: citar `#149` en el tramo sin subir `AHORA.md`; bloqueó el PASO 0
    del coder. Mismo error que con `#133` esta mañana.
39. **Guarda, defecto A otra vez**: bloqueó un heredoc del coder con `rm` dentro, y dos órdenes
    del arquitecto por palabras de un texto (órdenes del panel; el posesivo «su»).

## Decisiones

- ADR 0018: copia intacta primero, analizador de solo lectura, tipo CodeIgniter 3, y la
  unificación con `backupctl` después del lunes.
- ADR 0019: la herramienta solo escribe en el destino (regla del PO); los cron suspendidos no se
  migran; las propuestas dejan vacío lo que no saben.
- ADR 0020: las claves de los respaldos fuera del repositorio (mandato del PO), sin implementar.
- La fase 2 de la 2.1 queda aparcada.
- PO, 2026-10-17 (A-033): las zonas DNS entran para el lunes. Diseño: el analizador exporta, el
  destino recrea (ADR 0019: nada en el viejo). Sin ADR propio: cabe en 0018/0019.

## Cerrado

- **Duración:** de 16:30 (apertura de la jornada) a 18:00 del 2026-10-17. Rondas `#124`–`#147`,
  doce pares con el coder.
- **Segundo tramo:** de 18:30 a 19:45. Rondas `#148`–`#158` (más su reporte). Zonas DNS: código `164f7cf`
  `18b9792` `0e79e79`, guía `b338228` `9a39d74`.
- **Sin bitácora todavía**: el mandato no está cerrado; su primer uso real es el lunes. La entrada
  se escribe cuando el PO lo haya usado.
- **Fallos propios del arquitecto, hoy**: escribir en la guía que el plan anuncia los cron
  suspendidos sin comprobarlo (hallazgo 30); dictar el ejemplo de migración sin revisar su
  secuencia de fases, que se saltaba `sincronizar` (hallazgo 5, cazado una ronda después); y citar
  `#133` en el tramo antes de recibirlo, que hizo fallar `verificar.sh`.

## Pendiente del PO

En `estado/AHORA.md`, «Espera al PO», puntos 1 a 9. Lo más urgente: la migración del lunes con
`docs/migracion/caliente.md` (zonas incluidas), el `git push` de la rama, y rotar las
credenciales que estuvieron versionadas.
