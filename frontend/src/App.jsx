import { useState } from 'react';
import TerminalInput from './components/features/TerminalInput';
import SummaryDisplay from './components/features/SummaryDisplay';

function App() {
  // Estado para guardar el resumen cuando llegue de la API
  const [summaryData, setSummaryData] = useState(null);

  // Función que se ejecuta cuando el TerminalInput termina el polling
  const handleSummaryReady = (data) => {
    console.log("DATOS_RECIBIDOS_EN_NUCLEO:", data);
    setSummaryData(data);
  };

  return (
    <main className="min-h-screen w-full bg-void flex flex-col p-12 md:p-24 transition-all duration-1000">

      {/* CABECERA: Se vuelve más pequeña si ya hay un resumen (asimetría dinámica) */}
      <header className={`w-full max-w-6xl transition-all duration-700 ${summaryData ? 'opacity-40 scale-95 origin-left' : 'opacity-100'}`}>
        <h1 className="text-primary text-5xl md:text-7xl font-bold tracking-tightest uppercase glitch-shadow">
          Neural_Resumen
        </h1>
        <div className="mt-2 flex gap-8">
          <span className="text-secondary text-[10px] font-bold tracking-widest uppercase opacity-50">
            v2.0.99 // Deep_Space_Gemini_Edición
          </span>
        </div>
      </header>

      {/* INPUT: Siempre visible para nuevas consultas */}
      <TerminalInput onSummaryReady={handleSummaryReady} />

      {/* VISUALIZADOR: Solo aparece cuando summaryData tiene contenido */}
      {summaryData && <SummaryDisplay data={summaryData} />}

      {/* DECORACIÓN DE FONDO */}
      <div className="fixed bottom-0 right-0 w-[500px] h-[500px] bg-secondary/5 blur-[150px] -z-10 pointer-events-none"></div>
    </main>
  );
}

export default App;
