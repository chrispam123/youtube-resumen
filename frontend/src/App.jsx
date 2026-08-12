import { useState, useMemo, useCallback, useRef, useEffect } from 'react';
import { api } from './services/api';
import { usePolling } from './hooks/usePolling';
import BrandHeader from './components/features/BrandHeader';
import HeroInput from './components/features/HeroInput';
import ResultsView from './components/features/ResultsView';
import Footer from './components/features/Footer';
import FiberCanvas from './components/features/FiberCanvas';

// =============================================================================
// App — Yuyay v0.3
// Orquesta el flujo: reposo → disparo → sincronía / error.
// =============================================================================

function App() {
  const [url, setUrl] = useState('');
  const [errorMessage, setErrorMessage] = useState('');
  const [inputError, setInputError] = useState(false);
  const localErrorTimer = useRef(null);
  const fiberRef = useRef(null);

  const { status, result, error, setStatus, startPolling } = usePolling();

  // ---------------------------------------------------------------------------
  // systemState: derivado puro de status
  // ---------------------------------------------------------------------------

  const systemState = useMemo(() => {
    if (inputError) return 'error';
    if (status === 'PENDING' || status === 'PROCESSING') return 'firing';
    if (status === 'DONE') return 'sync';
    if (status === 'ERROR') return 'error';
    return 'idle';
  }, [status, inputError]);

  // ---------------------------------------------------------------------------
  // Sincronizar systemState → fibras
  // ---------------------------------------------------------------------------

  useEffect(() => {
    const canvas = fiberRef.current;
    if (canvas && canvas._fiberSetState) {
      canvas._fiberSetState(systemState);

      // Tras sincronía, las fibras vuelven a idle como celebración que se apaga
      if (systemState === 'sync') {
        const t = setTimeout(() => canvas._fiberSetState('idle'), 2200);
        return () => clearTimeout(t);
      }
    }
  }, [systemState]);

  // ---------------------------------------------------------------------------
  // Handler
  // ---------------------------------------------------------------------------

  const handleAnalyze = useCallback(async () => {
    clearTimeout(localErrorTimer.current);

    if (!url.trim()) {
      setInputError(true);
      setErrorMessage('URL vacía. Pega un enlace de YouTube.');
      localErrorTimer.current = setTimeout(() => setInputError(false), 1300);
      return;
    }

    setInputError(false);
    setErrorMessage('');

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
  // Derivados
  // ---------------------------------------------------------------------------

  const isProcessing = systemState === 'firing';
  const isError = systemState === 'error';
  const showResults = systemState === 'sync' && result;
  const displayError = error || errorMessage;

  // ---------------------------------------------------------------------------
  // Render
  // ---------------------------------------------------------------------------

  return (
    <>
      <FiberCanvas ref={fiberRef} />

      <div className="page">
        <BrandHeader systemState={systemState} />

        <HeroInput
          url={url}
          onUrlChange={setUrl}
          onAnalyze={handleAnalyze}
          isProcessing={isProcessing}
          isError={isError}
          errorMessage={displayError}
        />

        <ResultsView result={result} visible={showResults} />

        <Footer />
      </div>
    </>
  );
}

export default App;
