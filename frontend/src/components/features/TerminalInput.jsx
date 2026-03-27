import { useState, useEffect } from 'react'; // Añadimos useEffect
import { api } from '../../services/api';
import { usePolling } from '../../hooks/usePolling';

const TerminalInput = ({ onSummaryReady }) => {
  const [url, setUrl] = useState('');
  const { status, setStatus, startPolling, error, result } = usePolling();

  // SOLUCIÓN AL ERROR 1: Usamos useEffect para detectar cuando 'result' cambia
  useEffect(() => {
    if (status === 'DONE' && result) {
      onSummaryReady(result); // Ahora sí usamos la prop onSummaryReady
    }
  }, [status, result, onSummaryReady]);

  const handleSummarize = async () => {
    if (!url) return;
    try {
      setStatus('PENDING');
      const { job_id } = await api.analyzeVideo(url);
      startPolling(job_id);
    } catch (err) {
      // SOLUCIÓN AL ERROR 2: Logueamos el error para que 'err' sea usado
      console.error("NEURAL_LINK_ERROR:", err);
      setStatus('ERROR');
    }
  };

  return (
    <section className="w-full max-w-4xl mt-20">
      <div className="flex items-center gap-4 mb-2">
        <span className={`h-1 w-1 ${status === 'ERROR' ? 'bg-error' : 'bg-primary'} animate-pulse`}></span>
        <label className="text-secondary text-[10px] font-bold tracking-widest uppercase opacity-60">
          {status === 'IDLE' && 'ENTRADA_STREAM // YOUTUBE_URL_REQUERIDA'}
          {(status === 'PENDING' || status === 'PROCESSING') && 'RAZONANDO_ESPERE...'}
          {status === 'DONE' && 'NEURAL_LINK_STABLE // ANALISIS_COMPLETADO'}
          {status === 'ERROR' && `SYSTEM_FAILURE // ${error || 'UNKNOWN_ERROR'}`}
        </label>
      </div>

      <div className="flex flex-col md:flex-row items-stretch gap-0 relative">
        <input
          type="text"
          disabled={status === 'PENDING' || status === 'PROCESSING'}
          placeholder="PEGAR_URL_YOUTUBE_AQUI..."
          value={url}
          onChange={(e) => setUrl(e.target.value)}
          className="flex-grow bg-surface-high text-white px-6 py-4 text-sm font-medium
                     disabled:opacity-50 transition-all duration-300
                     focus:bg-surface-low focus:border-b-2 focus:border-primary"
        />

        <button
          onClick={handleSummarize}
          disabled={status === 'PENDING' || status === 'PROCESSING'}
          className="bg-liquid-light text-void font-bold text-xs px-10 py-4 uppercase tracking-widest
                     disabled:grayscale transition-all duration-500 hover:shadow-neon-primary"
        >
          {status === 'PENDING' || status === 'PROCESSING' ? 'PROCESANDO...' : 'ANALIZAR'}
        </button>

        {(status === 'PENDING' || status === 'PROCESSING') && (
          <div className="absolute -bottom-1 left-0 w-full h-[2px] overflow-hidden">
            <div className="h-full bg-primary animate-[glitch-bar_2s_infinite] shadow-neon-primary"></div>
          </div>
        )}
      </div>
    </section>
  );
};

export default TerminalInput;
