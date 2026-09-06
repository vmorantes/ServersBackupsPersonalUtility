# Mantener el repositorio

Cosas del repositorio en sí —no del respaldo— que conviene tener escritas para
no volver a investigarlas.

## Qué se versiona y qué no

```
✅ SE VERSIONA
bin/  lib/              el código
config/env.sh.example   plantilla de configuración
docs/  mkdocs.yml       documentación
<Servidor>/env.sh       configuración real de cada servidor
<Servidor>/NOTAS.md     tus apuntes
<Servidor>/ESTADO.md    foto del despliegue, generada por `pull`
<Servidor>/output/HestiaCP/   claves Restic (pequeñas, sirven de registro)

❌ NO SE VERSIONA (.gitignore)
*/output/mysql_backups/   los .zip: ~40 MB diarios, peso muerto en git
*/logs/  *.log            logs de ejecución
site/                     lo genera `mkdocs build`
*.anterior                copias que deja `pull` al traer un env.sh
temp_sql_*                temporales de un respaldo interrumpido
```

!!! note "Por qué `output/HestiaCP/` sí y `output/mysql_backups/` no"
    Es una decisión deliberada, no un descuido. Los volcados de claves Restic
    ocupan menos de un kilobyte y tenerlos versionados sirve de historial. Los
    respaldos de bases de datos pesan 40 MB por ejecución: en un mes serían
    1,2 GB de basura en el historial de git, irrecuperable sin reescribirlo.

## El bit de ejecución

`bin/backupctl` tiene que ser ejecutable. Git guarda eso en el **modo del
árbol** (`100644` frente a `100755`), no en los atributos.

```bash
git ls-files -s bin/backupctl
# 100755 e7870aa... 0    bin/backupctl     ← correcto
```

!!! danger "`.gitattributes` NO puede fijar el bit de ejecución"
    No existe ningún atributo tipo `executable`. Los atributos controlan
    finales de línea, filtros, `diff`, `merge` y `export-ignore` — nada más.

    Si alguna vez vuelve a aparecer como `100644`:

    ```bash
    chmod +x bin/backupctl
    git update-index --chmod=+x bin/backupctl
    ```

    Con el modo `100755` en el árbol, **cualquier clon lo creará ejecutable**,
    tenga la configuración que tenga.

### `core.filemode`

Este repositorio se creó con `core.filemode = false`, que es la razón de que el
problema apareciera: con esa opción git no detecta el bit por su cuenta.

```bash
git config core.filemode        # ver el valor actual
git config core.filemode true   # que git lo detecte solo
```

Activarlo es lo recomendable en Linux. Solo hace falta ponerlo en `false` en
sistemas de archivos que no preservan permisos: montajes de Windows, algunos
NFS y ciertos contenedores.

Antes de cambiarlo, comprueba que no genera ruido:

```bash
git -c core.filemode=true diff --summary | grep mode
# sin salida = activarlo es limpio
```

## Finales de línea

Para lo que `.gitattributes` **sí** sirve, y aquí importa de verdad:

```
* text=auto eol=lf
*.sh        text eol=lf
bin/*       text eol=lf
```

Un solo CRLF en un script de shell rompe el shebang:

```
bash: /home/admin/scripts/bin/backupctl: /usr/bin/env: bad interpreter: No such file or directory
```

El error no menciona el retorno de carro por ninguna parte, así que cuesta
diagnosticarlo. Forzar LF hace que editar desde Windows o desde un editor mal
configurado no pueda romper nada.

Si sospechas que algún archivo lo tiene:

```bash
file bin/backupctl lib/*.sh | grep CRLF || echo "todo con LF"
git add --renormalize .        # reescribe los que hicieran falta
```

## Comprobar el código antes de commitear

```bash
bash -n bin/backupctl lib/*.sh      # sintaxis, sin ejecutar nada
shellcheck bin/backupctl lib/*.sh   # análisis estático (más completo)
mkdocs build --strict               # documentación, falla ante cualquier aviso
```

Y una prueba funcional rápida, que no toca ninguna base de datos:

```bash
backupctl --help >/dev/null && echo "arranca"
backupctl profiles
backupctl -p <perfil> config --check
backupctl -p <perfil> backup --dry-run
```

## Ramas

El repositorio es de una sola persona y `master` es la rama de trabajo. Para un
cambio grande conviene aislarlo:

```bash
git checkout -b cambio-grande
# ... trabajar y commitear ...
git checkout master && git merge --ff-only cambio-grande
git branch -d cambio-grande
```

## Publicar la documentación

```bash
mkdocs serve                   # local, con recarga automática
mkdocs build                   # genera site/ (que no se versiona)
mkdocs gh-deploy               # publica en GitHub Pages, si lo quieres
```

!!! warning "Cuidado con `gh-deploy` en un repositorio privado"
    Publicaría la documentación en `gh-pages`. El sitio no contiene
    credenciales, pero sí nombres de servidores y de bases de datos. Piénsalo
    antes de exponerlo.

## Añadir un servidor

```bash
mkdir MiServidorNuevo
cp config/env.sh.example MiServidorNuevo/env.sh
${EDITOR:-nano} MiServidorNuevo/env.sh
backupctl profiles                      # debería aparecer solo
```

`backupctl` descubre los perfiles buscando directorios con un `env.sh` dentro.
No hay ninguna lista que mantener.

## Retirar un servidor

```bash
backupctl -p ViejoServidor pull root@viejo   # última foto, para el historial
git add ViejoServidor && git commit -m "ViejoServidor: última foto antes de retirarlo"
git rm -r ViejoServidor
```

Guardar la última foto antes de borrarlo deja constancia de cómo estaba el día
que se apagó.
