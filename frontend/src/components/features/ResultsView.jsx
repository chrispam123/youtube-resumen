// =============================================================================
// ResultsView — Resumen estructurado post-análisis
//
// Props:
//   result   { video_title, summary: { main_idea, key_points, conclusion } }
//   visible  boolean — controla animación de entrada
// =============================================================================

const ResultsView = ({ result, visible }) => {
  if (!result) return null;

  return (
    <section className={`results ${visible ? 'show' : ''}`}>
      <div className="results-eyebrow">Resumen_ejecutivo // fuente_verificada</div>
      <h2 className="results-headline">
        {result.video_title || 'Análisis completado'}
      </h2>

      <div className="cols">
        <div>
          <div className="col-label">Núcleo_conceptos</div>
          <div className="col-a">{result.summary?.main_idea}</div>
        </div>
        <div>
          <div className="col-label">Conclusiones_clave</div>
          <div className="col-b">
            {result.summary?.key_points?.map((point, i) => (
              <div key={i} className="item">{point}</div>
            ))}
          </div>
        </div>
      </div>

      <div className="final">
        <div className="final-label">// resumen_final</div>
        <div className="final-text">{result.summary?.conclusion}</div>
      </div>

      <div className="sync-note show">
        // FIBER_SYNC — conclusión estabilizada, {result.summary?.key_points?.length || 3} hebras convergentes
      </div>
    </section>
  );
};

export default ResultsView;
