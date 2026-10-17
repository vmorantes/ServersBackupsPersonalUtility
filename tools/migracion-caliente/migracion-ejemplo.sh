#!/bin/bash

# ============================================================
# ARCHIVO DE MIGRACIÓN — EJEMPLO
# ============================================================
#
# Todos los nombres, dominios, usuarios, bases e IPs de este
# archivo son FICTICIOS. Las contraseñas son el marcador
# CAMBIAR_ESTA_CLAVE. Se sustituyen todas antes de ejecutar:
# la herramienta no comprueba que sigan siendo el marcador.
#
# Este archivo se copia con otro nombre (migracion-cliente.sh,
# por ejemplo) y se edita. El directorio ignora
# migracion-*.sh salvo este ejemplo, porque un archivo de
# migración real lleva contraseñas en claro.
#
# Se usa así, en este orden:
#
#   bash BASE_GENERAL.sh migracion-cliente.sh plan
#   bash BASE_GENERAL.sh migracion-cliente.sh 1
#   bash BASE_GENERAL.sh migracion-cliente.sh sincronizar
#
#       ─── aquí se apunta el DNS al servidor nuevo ───
#
#   bash BASE_GENERAL.sh migracion-cliente.sh 2
#   bash BASE_GENERAL.sh migracion-cliente.sh verificar
#
# "sincronizar" se puede repetir cuantas veces se quiera
# hasta el momento de apuntar el DNS, y "verificar" solo lee,
# así que se puede lanzar cuando se quiera, antes o después.
#
# Las dos formas de equivocarse con "sincronizar":
#
#   - Saltárselo pierde, sin un solo aviso, todo lo que se
#     haya escrito en el servidor viejo entre la fase 1 y el
#     corte de DNS.
#
#   - Lanzarlo DESPUÉS del corte de DNS puede pisar con datos
#     viejos lo que ya se haya escrito en el servidor nuevo:
#     deja el destino idéntico al origen y borra en el nuevo
#     lo que en el viejo no exista.
#
# La fase que se pasa como segundo argumento manda sobre la
# que diga FASE aquí abajo.
#
# Un archivo describe UNA cuenta del panel: USER_ORIGEN y
# USER_DESTINO son únicos. Para varias cuentas, un archivo
# por cuenta.
#
# ============================================================


# ============================================================
# === LA CORRIDA ===
# ============================================================

FASE="plan";

# Pide escribir "si" antes de ejecutar. No se pone en "false"
# en una migración de verdad.
CONFIRMAR="true";


# ============================================================
# === LOS DOS SERVIDORES ===
# ============================================================
#
# IPs de documentación (RFC 5737). En una migración real van
# las de los dos servidores, y no pueden ser la misma IP con
# el mismo usuario: el origen y el destino serían la misma
# carpeta y la misma base.
#
# ============================================================

USER_ORIGEN="cuentaejemplo";
USER_DESTINO="cuentaejemplo";

IP_ORIGEN="203.0.113.10";
IP_DESTINO="203.0.113.20";

SSH_ORIGEN="root";
SSH_DESTINO="root";


# ============================================================
# === CRONJOBS ===
# ============================================================
#
# "preguntar" muestra los del origen uno por uno y espera
# respuesta. "todos" y "ninguno" no preguntan.
#
# ============================================================

CRONJOBS="preguntar";
CRONJOBS_USUARIOS=();


# ============================================================
# === PREDETERMINADOS ===
# ============================================================
#
# Los heredan los dominios declarados DESPUÉS, y cada dominio
# solo declara lo que cambia.
#
# php se declara SIEMPRE con la plantilla exacta, en los
# predeterminados y en cada dominio. "default" no es la misma
# versión en los dos servidores: en la migración del
# 2026-10-02 era PHP 8.2 en el viejo y 8.5 en el nuevo.
#
# forzar_ssl se queda en "false" en todos los dominios:
# forzar HTTPS no comprueba que el certificado exista, y un
# dominio redirigido a un HTTPS sin certificado deja de
# responder. Se fuerza a mano, dominio por dominio, después
# de comprobar que el certificado está emitido.
#
# Ojo con el vocabulario: cualquier valor distinto de "true"
# cuenta como falso (cfg_si, BASE_CONFIG.sh:547), así que una
# errata desactiva la opción en silencio, sin error.
#
# ============================================================

predeterminados \
  php="PHP-8_1" \
  ssl="true" \
  forzar_ssl="false";


# ============================================================
# === DOMINIOS ===
# ============================================================
#
# El orden de los bloques es el orden de la migración.
#
# ============================================================

# ------------------------------------------------------------
# Un WordPress.
#
# tipo="wordpress" reescribe public_html/wp-config.php con el
# nombre, el usuario y la contraseña nuevos de la base.
#
# bd y bd_user son los nombres CORTOS: HestiaCP les antepone
# el usuario del panel, así que bd="web" con la cuenta
# "cuentaejemplo" produce cuentaejemplo_web.
# ------------------------------------------------------------

dominio "example.org" \
  php="PHP-8_1" \
  tipo="wordpress" \
  forzar_ssl="false" \
  bd="web" \
  bd_user="web" \
  bd_pass="CAMBIAR_ESTA_CLAVE";


# ------------------------------------------------------------
# Un Joomla.
#
# tipo="joomla" reescribe public_html/configuration.php.
#
# origen= porque en el servidor viejo la carpeta del dominio
# se llamaba distinto.
# ------------------------------------------------------------

dominio "sub.example.org" \
  php="PHP-8_1" \
  tipo="joomla" \
  forzar_ssl="false" \
  origen="joomla.example.net" \
  bd="portal" \
  bd_user="portal" \
  bd_pass="CAMBIAR_ESTA_CLAVE";


# ------------------------------------------------------------
# Un CodeIgniter 3.
#
# tipo="codeigniter3" lee y reescribe el grupo 'default' de
# application/config/database.php, en sus dos formas: la de
# array y la de clave a clave. Ya no hay que editar nada a
# mano.
#
# No se usa "piecesphp": ese busca
# $config['database']['default'][...] en
# app/config/database.php, que es otra forma y otra ruta.
#
# bd_origen no se declara: el tipo lee del servidor viejo el
# nombre de la base y el usuario.
#
# DOS COSAS QUE HAY QUE COMPROBAR EN CADA PROYECTO:
#
#   - La ruta por defecto supone que application/ cuelga de
#     public_html/. Si no, se declara con ruta_db.
#
#   - Si el proyecto tiene
#     application/config/<ENTORNO>/database.php, ESE manda
#     sobre el general: hay que apuntar ruta_db a él, o se
#     reescribiría el archivo que la aplicación no usa y la
#     migración parecería correcta.
#
# Y si $active_group no es 'default', la herramienta se niega
# y lo dice: ese proyecto usa otro grupo y se revisa a mano.
# ------------------------------------------------------------

dominio "example.net" \
  php="PHP-7_4" \
  tipo="codeigniter3" \
  forzar_ssl="false" \
  bd="intranet" \
  bd_user="intranet" \
  bd_pass="CAMBIAR_ESTA_CLAVE";


# ============================================================
# === BASES SUELTAS ===
# ============================================================
#
# Bases que no cuelgan de ningún dominio: históricas, de un
# cron o de una aplicación externa. No se reescribe ninguna
# configuración, así que "origen" es obligatorio: sin dominio
# no hay archivo del que deducir el nombre viejo.
#
# ============================================================

base_de_datos "historico" \
  origen="cuentavieja_historico" \
  user="historico" \
  pass="CAMBIAR_ESTA_CLAVE";
