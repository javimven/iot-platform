{{flutter_js}}
{{flutter_build_config}}

// Arranque con fases visibles en la pantalla de carga de index.html
// (BACKLOG.md #50): si algo falla en un móvil, se ve en qué fase se quedó y
// el error, en vez de una página en blanco.
(function () {
  var carga = window.__carga || { fase: function () {}, fallo: function () {} };
  // La app va incrustada en #app (ver index.html, BACKLOG.md #52) en vez de a
  // página completa. Hay que pasarlo también a initializeEngine: con un
  // onEntrypointLoaded propio, el cargador no se lo pasa solo.
  var config = { hostElement: document.getElementById('app') };
  carga.fase('Descargando la aplicación…');
  try {
    _flutter.loader
      .load({
        config: config,
        onEntrypointLoaded: async function (engineInitializer) {
          try {
            carga.fase('Preparando el motor de dibujo…');
            var appRunner = await engineInitializer.initializeEngine(config);
            carga.fase('Abriendo…');
            await appRunner.runApp();
          } catch (error) {
            carga.fallo('arranque del motor', error);
          }
        },
      })
      .catch(function (error) {
        carga.fallo('carga del código', error);
      });
  } catch (error) {
    carga.fallo('cargador de Flutter', error);
  }
})();
