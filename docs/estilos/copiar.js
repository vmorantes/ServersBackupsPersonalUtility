// docs/estilos/copiar.js — botón "Copiar" en los bloques de código
//
// Sin dependencias: el tema readthedocs no trae esto, y no hace falta ninguna
// librería para algo tan pequeño.
(function () {
  "use strict";

  // Si no hay Clipboard API (página abierta con file://, o sin HTTPS), no se
  // añade ningún botón: uno que no funciona es peor que no tener ninguno.
  if (!navigator.clipboard) {
    return;
  }

  var TEXTO_INICIAL = "Copiar";
  var TEXTO_COPIADO = "Copiado";
  var TEXTO_ERROR = "No se pudo copiar";
  var DURACION_AVISO_MS = 2000;

  // Los bloques de código de Pygments van en div.highlight > pre; algunas
  // páginas (o una construcción sin pymdownx.highlight) pueden dejar el pre
  // suelto dentro de .rst-content, así que ese es el respaldo.
  function encontrarBloques() {
    var bloques = document.querySelectorAll("div.highlight pre");
    if (bloques.length === 0) {
      bloques = document.querySelectorAll(".rst-content pre");
    }
    return bloques;
  }

  // El botón queda FUERA del <pre>, como hermano siguiente dentro de un
  // contenedor propio: así su texto ("Copiar", "Copiado"...) nunca se cuela
  // en lo que se copia, y el <pre> no necesita tocarse.
  function envolverBloque(pre) {
    var contenedor = document.createElement("div");
    contenedor.className = "bc-bloque-codigo";
    pre.parentNode.insertBefore(contenedor, pre);
    contenedor.appendChild(pre);
    return contenedor;
  }

  function crearBoton(pre) {
    var boton = document.createElement("button");
    boton.type = "button";
    boton.className = "bc-boton-copiar";
    boton.setAttribute("aria-label", "Copiar el contenido de este bloque");
    boton.textContent = TEXTO_INICIAL;

    var temporizador = null;

    boton.addEventListener("click", function () {
      var texto = pre.textContent;

      navigator.clipboard.writeText(texto).then(
        function () {
          mostrarAviso(boton, TEXTO_COPIADO);
        },
        function () {
          mostrarAviso(boton, TEXTO_ERROR);
        }
      );
    });

    function mostrarAviso(elBoton, texto) {
      elBoton.textContent = texto;
      if (temporizador !== null) {
        window.clearTimeout(temporizador);
      }
      temporizador = window.setTimeout(function () {
        elBoton.textContent = TEXTO_INICIAL;
        temporizador = null;
      }, DURACION_AVISO_MS);
    }

    return boton;
  }

  function iniciar() {
    var bloques = encontrarBloques();
    for (var i = 0; i < bloques.length; i++) {
      var pre = bloques[i];
      var contenedor = envolverBloque(pre);
      var boton = crearBoton(pre);
      contenedor.appendChild(boton);
    }
  }

  document.addEventListener("DOMContentLoaded", iniciar);
})();
