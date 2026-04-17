# Instrucciones de administración

- Administración de servidor HestiaCP de TejidoTesting.

## Generales

- Como se enfoca en el respaldo de información es recomendable que el usuario donde se cargaran los scripts tenga configurado un paquete con respaldos y respaldos incrementales si es posible.

## Scripts base

- `env.sh`: Script para configurar las variables de entorno.
    - Cargado en: /home/[USER_NAME]/scripts/env.sh
- `RunBackupDB.sh`: Script para respaldar las bases de datos.
    - Cargado en: /home/[USER_NAME]/scripts/RunBackupDB.sh

### Ajustes de implementación

```bash
export USER_NAME=admin
# 1. Dar permisos de ejecución a todos los scripts:
find /home/$USER_NAME/scripts/ -name "*.sh" -exec chmod +x {} \;
# 2. Preparar directorio de logs:
mkdir -p /home/$USER_NAME/scripts/logs
# 3. Preparar directorio de salida:
mkdir -p /home/$USER_NAME/scripts/output
# 4. Ajustar permisos del usuario al que pertenece el script para que pueda ejecutarlo:
chown -R $USER_NAME:$USER_NAME /home/$USER_NAME/scripts/
chmod -R 755 /home/$USER_NAME/scripts/
```
    
## Crontab

```bash
# RunBackupDB.sh, se recomienda a alguna hora de la madrugada, una vez por día
/home/[USER_NAME]/scripts/RunBackupDB.sh >> /home/[USER_NAME]/scripts/logs/RunBackupDB_$(date +%Y%m%d_%H%M%S).log 2>&1
```


