# 0008 — Los perfiles guardan sus credenciales en el repositorio

- **Estado:** Aceptada (retrospectiva: formaliza lo que ya se hacía)
- **Fecha:** 2026-09-14
- **Decide:** Product Owner
- **Estructural:** sí (dónde viven las credenciales)

## En cristiano

Cada servidor tiene su carpeta en el repositorio, y en ella viven su configuración con
contraseñas y las claves que se rescatan de HestiaCP. El PO lo quiere así: es un repositorio de
uso propio y es donde las guarda. Los agentes nunca leen ni muestran esos archivos. Nadie
propone sacarlas de ahí salvo que el PO cambie de idea.

## Contexto

- `<Perfil>/env.sh` lleva la contraseña de MySQL; `<Perfil>/output/HestiaCP/` lleva claves de
  Restic y de almacenamiento S3 (`.agents/context/30-trampas.md` T1). Están versionados y
  subidos a GitHub. La URL del remoto lleva un token.
- `docs/desarrollo/repositorio.md` («Qué se versiona») ya presentaba versionar `env.sh` y
  `output/HestiaCP/` como deliberado.
- El arquitecto recomendó rotarlas y sacarlas del árbol. El PO, el 2026-09-14: «No, este
  repositorio es de uso propio; acá las guardo».
- Si el repositorio de GitHub es privado: **sin verificar** (comprobarlo exigiría usar la
  credencial).

## Decisión

Las credenciales de los perfiles se quedan versionadas. Los agentes no las leen, no las
imprimen, no las copian ni las editan (regla 40 §6, forzado por la guarda, ADR 0003).

## Alternativas descartadas

| Alternativa | Por qué no |
| --- | --- |
| Sacarlas a archivos ignorados por git | Decisión del PO: el repositorio es donde las guarda |
| Cifrarlas en el repositorio (git-crypt, sops) | Una dependencia nueva y una clave más que guardar; el PO no lo pidió |
| Rotarlas | Decisión del PO; no hay indicio de filtración |

## Consecuencias

- Quien tenga acceso al repositorio (un clon, la cuenta de GitHub) tiene las credenciales de
  producción.
- La guarda es la única barrera entre esos archivos y la transcripción de un agente; lo que no
  ve (`git show` de un commit antiguo que tocó un perfil) lo cubre solo la regla.
- La documentación agnóstica (regla 40 §1) sigue valiendo fuera de los perfiles.

## Reversión

**Parcial**: sacarlas del árbol es fácil (`git rm --cached`, `.gitignore`), pero siguen en la
historia y en GitHub. Borrarlas de la historia exige reescribirla y es destructivo. Por eso,
si se revierte, se rotan primero.

## Verificación

`probar_guardia.py` bloquea leer, copiar y editar `env.sh`, `output/HestiaCP/` y `ESTADO.md`.
