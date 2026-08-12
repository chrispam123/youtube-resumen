import { useState, useEffect, useCallback } from 'react';
import { api } from './services/api';
import { usePolling } from './hooks/usePolling';

// =============================================================================
// App — Yuyay v0.3
// Orquesta el flujo completo: reposo → disparo → sincronía → reposo.
// =============================================================================

function App() {
  const [url, setUrl] = useState('');
  const [showResults, setShowResults] = useState(false);
  const [resultData, setResultData] = useState(null);
  const [systemState, setSystemState] = useState('idle'); // idle | firing | sync | error
  const [errorMessage, setErrorMessage] = useState('');
  const [inputError, setInputError] = useState(false);

  const { status, result, error, setStatus, startPolling } = usePolling();

  // ---------------------------------------------------------------------------
  // Sincronizar hook usePolling → sistema de estados Yuyay
  // ---------------------------------------------------------------------------

  useEffect(() => {
    if (status === 'PENDING' || status === 'PROCESSING') {
      setSystemState('firing');
    } else if (status === 'DONE' && result) {
      setResultData(result);
      setShowResults(true);
      setSystemState('sync');
      const t = setTimeout(() => setSystemState('idle'), 2200);
      return () => clearTimeout(t);
    } else if (status === 'ERROR') {
      setSystemState('error');
      if (error) setErrorMessage(error);
      const t = setTimeout(() => setSystemState('idle'), 1300);
      return () => clearTimeout(t);
    }
  }, [status, result, error]);

  // ---------------------------------------------------------------------------
  // Handler — dispara el análisis
  // ---------------------------------------------------------------------------

  const handleAnalyze = useCallback(async () => {
    if (!url.trim()) {
      setInputError(true);
      setErrorMessage('URL vacía. Pega un enlace de YouTube.');
      setSystemState('error');
      setTimeout(() => {
        setSystemState('idle');
        setInputError(false);
      }, 1300);
      return;
    }

    setShowResults(false);
    setResultData(null);
    setErrorMessage('');
    setInputError(false);

    try {
      setStatus('PENDING');
      const { job_id } = await api.analyzeVideo(url);
      startPolling(job_id);
    } catch (err) {
      console.error('YUYAY_FAULT:', err);
      setErrorMessage(err.message || 'No se pudo conectar. Verifica tu red.');
      setStatus('ERROR');
    }
  }, [url, setStatus, startPolling]);

  // ---------------------------------------------------------------------------
  // Status bar text
  // ---------------------------------------------------------------------------

  const statusLabel = {
    idle:   'SYNAPSE_LINK_STABLE',
    firing: 'FIBER_BURST // ANALIZANDO',
    sync:   'FIBER_SYNC // CONCLUSION ESTABILIZADA',
    error:  'FIBER_FAULT',
  };

  const statusColorVar = {
    idle:   'var(--reposo)',
    firing: 'var(--disparo)',
    sync:   'var(--sincronia)',
    error:  'var(--alert)',
  };

  const isProcessing = systemState === 'firing';

  // ---------------------------------------------------------------------------
  // Render
  // ---------------------------------------------------------------------------

  return (
    <>
      {/* Canvas de fondo — placeholder, Fase 2 */}
      <canvas
        className="fiber-canvas"
        id="fiberCanvas"
        ref={(el) => {
          if (el && !el._init) {
            el._init = true;
            const dpr = window.devicePixelRatio || 1;
            el.width = window.innerWidth * dpr;
            el.height = window.innerHeight * dpr;
            el.getContext('2d').setTransform(dpr, 0, 0, dpr, 0, 0);
            el.style.width = '100%';
            el.style.height = '100%';
          }
        }}
      />

      <div className="page">

        {/* Header: marca + status */}
        <header>
          <div className="brand">
            <svg className="brand-icon" viewBox="0 0 180 200">
              <path d="M 20 20 C 55 60, 75 90, 88 120" stroke="#F2542D" strokeWidth="16" fill="none" strokeLinecap="round"/>
              <path d="M 160 20 C 125 60, 105 90, 92 120" stroke="#F2542D" strokeWidth="16" fill="none" strokeLinecap="round"/>
              <line x1="90" y1="120" x2="90" y2="185" stroke="#F4E4B8" strokeWidth="16" strokeLinecap="round"/>
              <circle cx="90" cy="122" r="18" fill="#F4E4B8"/>
            </svg>
            <div className="brand-word">Yuyay</div>
          </div>

          <div className="status" style={{ color: statusColorVar[systemState] }}>
            <span className="status-dot" />
            <span>{statusLabel[systemState]}</span>
          </div>
        </header>

        {/* Hero: input + CTA */}
        <section className="hero">
          <div className="hero-eyebrow">// pensamiento sintetizado</div>
          <h1 className="hero-headline">Pega un enlace. Encuentra la idea.</h1>

          <div className={`input-row ${inputError || systemState === 'error' ? 'is-error' : ''}`}>
            <input
              type="text"
              placeholder="https://www.youtube.com/watch?v=..."
              value={url}
              onChange={(e) => {
                setUrl(e.target.value);
                if (inputError) setInputError(false);
              }}
              disabled={isProcessing}
              onKeyDown={(e) => e.key === 'Enter' && handleAnalyze()}
            />
            <button onClick={handleAnalyze} disabled={isProcessing}>
              {isProcessing ? 'Analizando…' : 'Analizar'}
            </button>
          </div>

          {systemState === 'error' && (
            <div className="error-msg show">{errorMessage}</div>
          )}
        </section>

        {/* Results: solo visible tras sincronía */}
        <section className={`results ${showResults ? 'show' : ''}`}>
          {resultData && (
            <>
              <div className="results-eyebrow">Resumen_ejecutivo // fuente_verificada</div>
              <h2 className="results-headline">
                {resultData.video_title || 'Análisis completado'}
              </h2>

              <div className="cols">
                <div>
                  <div className="col-label">Núcleo_conceptos</div>
                  <div className="col-a">{resultData.summary?.main_idea}</div>
                </div>
                <div>
                  <div className="col-label">Conclusiones_clave</div>
                  <div className="col-b">
                    {resultData.summary?.key_points?.map((point, i) => (
                      <div key={i} className="item">{point}</div>
                    ))}
                  </div>
                </div>
              </div>

              <div className="final">
                <div className="final-label">// resumen_final</div>
                <div className="final-text">{resultData.summary?.conclusion}</div>
              </div>

              <div className="sync-note show">
                // FIBER_SYNC — conclusión estabilizada, {resultData.summary?.key_points?.length || 3} hebras convergentes
              </div>
            </>
          )}
        </section>

        {/* Footer */}
        <footer>Yuyay v0.3 // synapse_edition</footer>

      </div>
    </>
  );
}

export default App;
