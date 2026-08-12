// =============================================================================
// HeroInput — Input de URL + botón de análisis
//
// Props:
//   url           string actual del input
//   onUrlChange   (value: string) => void
//   onAnalyze     () => void
//   isProcessing  boolean — deshabilita input y botón
//   isError       boolean — borde rojo
//   errorMessage  string — mensaje inline de error
// =============================================================================

const HeroInput = ({ url, onUrlChange, onAnalyze, isProcessing, isError, errorMessage }) => (
  <section className="hero">
    <div className="hero-eyebrow">// pensamiento sintetizado</div>
    <h1 className="hero-headline">Pega un enlace. Encuentra la idea.</h1>

    <div className={`input-row ${isError ? 'is-error' : ''}`}>
      <input
        type="text"
        placeholder="https://www.youtube.com/watch?v=..."
        value={url}
        onChange={(e) => onUrlChange(e.target.value)}
        disabled={isProcessing}
        onKeyDown={(e) => e.key === 'Enter' && onAnalyze()}
      />
      <button onClick={onAnalyze} disabled={isProcessing}>
        {isProcessing ? 'Analizando…' : 'Analizar'}
      </button>
    </div>

    {isError && (
      <div className="error-msg show">{errorMessage}</div>
    )}
  </section>
);

export default HeroInput;
