
import { useState } from 'react';

const TerminalInput = () => {
  const [url, setUrl] = useState('');

  return (
    // CONTENEDOR ASIMÉTRICO: No centramos todo, dejamos aire a los lados
    <section className="w-full max-w-4xl mt-20 animate-fade-in">

      {/* ETIQUETA DE ESTADO: Label-SM con tracking amplio */}
      <div className="flex items-center gap-4 mb-2">
        <span className="h-1 w-1 bg-primary animate-pulse"></span>
        <label className="text-secondary text-[10px] font-bold tracking-widest uppercase opacity-60">
          INPUT_STREAM // YOUTUBE_URL_REQUIRED
        </label>
      </div>

      {/* GRUPO DE ENTRADA: Aplicando la regla de "No-Line" */}
      <div className="flex flex-col md:flex-row items-stretch gap-0">

        {/* CAMPO DE TEXTO: Fondo surface-high, sin bordes, solo borde inferior en focus */}
        <input
          type="text"
          placeholder="PASTE_YOUTUBE_URL_HERE..."
          value={url}
          onChange={(e) => setUrl(e.target.value)}
          className="flex-grow bg-surface-high text-white px-6 py-4 text-sm font-medium
                     placeholder-secondary/30 transition-all duration-300
                     focus:bg-surface-low focus:border-b-2 focus:border-primary"
        />

        {/* BOTÓN DE ACCIÓN: Gradiente "Liquid Light" y bordes afilados (0px) */}
        <button className="bg-liquid-light text-void font-bold text-xs px-10 py-4
                           uppercase tracking-widest transition-all duration-500
                           hover:shadow-neon-primary hover:brightness-110 active:scale-95">
          Summarize
        </button>
      </div>

      {/* METADATOS DE TERMINAL: Detalles asimétricos que dan realismo */}
      <div className="mt-4 flex justify-between items-start opacity-40">
        <div className="text-[9px] text-tertiary font-mono">
          STATUS: PARSING_DATA_PACKETS<br />
          NODE: EDGE_01_SYNTHETIC
        </div>
        <div className="text-[9px] text-secondary font-mono text-right">
          ENTROPY_SCORE: 0.88241<br />
          LATENCY: 14MS
        </div>
      </div>

    </section>
  );
};

export default TerminalInput;
