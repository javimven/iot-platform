{{flutter_js}}
{{flutter_build_config}}

// Arranque con fases visibles en la pantalla de carga de index.html
// (BACKLOG.md #50): si algo falla en un móvil, se ve en qué fase se quedó y
// el error, en vez de una página en blanco.
(function () {
  var carga = window.__carga || { fase: function () {}, fallo: function () {} };
  carga.fase('Descargando la aplicación…');
  try {
    _flutter.loader
      .load({
        onEntrypointLoaded: async function (engineInitializer) {
          try {
            carga.fase('Preparando el motor de dibujo…');
            var appRunner = await engineInitializer.initializeEngine();
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
