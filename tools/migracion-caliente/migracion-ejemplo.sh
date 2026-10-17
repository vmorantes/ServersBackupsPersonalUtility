#!/bin/bash

# ============================================================
# ARCHIVO DE MIGRACIÓN — EJEMPLO
# ============================================================
#
# Todos los nombres, dominios, usuarios, bases e IPs de este
# archivo son FICTICIOS. Las contraseñas son el marcador
# CAMBIAR_ESTA_CLAVE: no se ejecuta nada con ellas puestas.
#
# Este archivo se copia con otro nombre (migracion-cliente.sh,
# por ejemplo) y se edita. El directorio ignora
# migracion-*.sh salvo este ejemplo, porque un archivo de
# migración real lleva contraseñas en claro.
#
# Se usa así:
#
#   bash BASE_GENERAL.sh migracion-cliente.sh plan
#   bash BASE_GENERAL.sh migracion-cliente.sh 1
#   bash BASE_GENERAL.sh migracion-cliente.sh verificar
#   bash BASE_GENERAL.sh migracion-cliente.sh 2
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
# predeterminados y en cada dominio. En la migración del
# 2026-10-02, dejar que la versión la eligiera el panel saltó
# versiones de PHP entre el origen y el destino: un sitio que
# venía con 7.4 se levantó con otra y falló al abrir.
#
# forzar_ssl se queda en "no" en todos los dominios: forzar
# HTTPS no comprueba que el certificado exista, y un dominio
# redirigido a un HTTPS sin certificado deja de responder.
# Se fuerza a mano, dominio por dominio, después de comprobar
# que el certificado está emitido.
#
# ============================================================

predeterminados \
  php="PHP-8_1" \
  ssl="true" \
  forzar_ssl="no";


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
  forzar_ssl="no" \
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
  forzar_ssl="no" \
  origen="joomla.example.net" \
  bd="portal" \
  bd_user="portal" \
  bd_pass="CAMBIAR_ESTA_CLAVE";


# ------------------------------------------------------------
# Un CodeIgniter 3.
#
# Va con tipo="ninguno" HASTA QUE EXISTA SU PROPIO TIPO: la
# base se migra, pero la herramienta NO reescribe ninguna
# configuración. Las credenciales nuevas se escriben A MANO,
# después de la fase 1, en:
#
#   application/config/database.php
#
# en las claves $db['default']['database'], ['username'] y
# ['password'].
#
# El tipo "piecesphp" NO sirve para CodeIgniter 3: busca
# $config['database']['default'][...] en
# app/config/database.php, y CodeIgniter 3 declara
# $db['default'] en application/config/database.php. Falla en
# voz alta, sin escribir, pero falla.
#
# Con tipo="ninguno" no hay archivo del que leer el nombre de
# la base en el servidor viejo, así que bd_origen se declara.
# ------------------------------------------------------------

dominio "example.net" \
  php="PHP-7_4" \
  tipo="ninguno" \
  forzar_ssl="no" \
  bd="intranet" \
  bd_user="intranet" \
  bd_pass="CAMBIAR_ESTA_CLAVE" \
  bd_origen="cuentavieja_intranet";


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
