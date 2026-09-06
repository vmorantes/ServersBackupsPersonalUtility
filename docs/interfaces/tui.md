# TUI interactiva

```bash
backupctl
```

Sin argumentos y con terminal, se abre el menú. Es la compuerta pensada para
**cuando no recuerdas la orden exacta**.

## El menú principal

```
backupctl 2.0.0 — perfil 'MiVPS'
Ecosistema de respaldo y migración.
Servidor: servidor.example

   1) Estado actual del sistema de respaldo
   2) Diagnóstico completo del entorno
   3) Respaldar las bases de datos ahora
   4) Verificar un respaldo
   5) Restaurar una base de datos
   6) Migrar a otro servidor
   7) Respaldos guardados
   8) Claves Restic de HestiaCP
   9) Programación automática
  10) Configuración del perfil
  11) Registros
  12) Cambiar de perfil / servidor

   0) Volver / Salir
```

Con `whiptail` o `dialog` instalados se dibuja como menú gráfico de terminal.
Sin ellos, el menú numerado de arriba, que funciona en cualquier sesión SSH.

```bash
backupctl --plain     # forzar el modo texto
```

## Lo que aporta sobre la CLI

**Elegir en lugar de escribir.** Los respaldos y las bases de datos se listan
para seleccionarlas, con su tamaño y antigüedad:

```
   1) all_databases_20260905_033012.zip  [38.3M, 0d]
   2) all_databases_20260904_033010.zip  [38.1M, 1d]
```

**Simular está a la vista.** Cada operación destructiva ofrece su versión de
ensayo en el mismo menú, no escondida tras una opción que hay que recordar.

**Progreso en vivo.** Las operaciones largas salen del diálogo y corren en el
terminal limpio, para que se vea el avance base a base. Una barra de progreso
que oculta el log sería peor que no tener barra.

```
== Respaldo completo ==

[ >>  ] [12/76] tienda
[  OK ]     tienda — 41 tablas, 6 vistas, 160 INSERT

✓ Operación terminada correctamente.

Pulsa Enter para volver al menú...
```

## Submenús

??? example "Respaldar"
    - Todas las bases de datos
    - Solo una (se elige de una lista)
    - Todas, solo estructura (`--no-data`)
    - Simular (`--dry-run`)

??? example "Verificar"
    - Rápida: solo el zip
    - Completa: zip, `.gz`, sumas y contenido
    - Completa, eligiendo qué respaldo
    - Prueba de restauración **real** en una BD desechable

??? example "Restaurar"
    Se elige respaldo y base de datos, y después:

    - Sobre la misma base de datos
    - En otra base de datos con otro nombre (`--into`)
    - Simular

??? example "Migrar"
    - Desplegar `backupctl` en otro servidor
    - Simular una migración
    - Migrar de verdad, con opción de generar un respaldo fresco

??? example "Respaldos guardados"
    - Listar
    - Inspeccionar (metadatos e inventario)
    - Aplicar la retención
    - Simular la retención

??? example "Programación / Configuración / Registros"
    Ver e instalar el crontab, enviar un aviso de prueba, ver y editar `env.sh`,
    listar y seguir los logs.

## Cambiar de servidor

La opción **Cambiar de perfil** recarga la configuración sin salir del menú.
Útil cuando administras varios servidores desde el mismo repositorio.

## Sin terminal

```bash
echo | backupctl
# muestra la ayuda y sale con código 2
```

Si `backupctl` se invoca sin orden y sin terminal —un cron mal configurado—,
enseña la ayuda y sale con error en lugar de quedarse esperando una entrada que
nunca va a llegar.

## No es una capa aparte

!!! info
    La TUI llama a las **mismas funciones** de `lib/` que usa el cron. No hay
    una implementación interactiva y otra automática que puedan divergir: lo
    que pruebas aquí es exactamente lo que se ejecuta de madrugada.
