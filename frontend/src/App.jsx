
import TerminalInput from './components/features/TerminalInput';

function App() {
  return (
    // EL VACÍO: Fondo negro absoluto y scrollbar neón (vía index.css)
    <main className="min-h-screen w-full bg-void flex flex-col p-12 md:p-24">

      {/* CABECERA: Alineación asimétrica (izquierda) */}
      <header className="w-full max-w-6xl">
        <h1 className="text-primary text-5xl md:text-7xl font-bold tracking-tightest uppercase glitch-shadow">
          Neural_Sum
        </h1>
        <div className="mt-2 flex gap-8">
          <span className="text-secondary text-[10px] font-bold tracking-widest uppercase opacity-50">
            v2.0.99 // Deep_Space_Edition
          </span>
          <span className="text-tertiary text-[10px] font-bold tracking-widest uppercase opacity-50">
            Status: Online
          </span>
        </div>
      </header>

      {/* COMPONENTE DE ENTRADA */}
      <TerminalInput />

      {/* DECORACIÓN DE FONDO: Un gradiente muy sutil que "sangra" en la oscuridad */}
      <div className="fixed bottom-0 right-0 w-[500px] h-[500px] bg-secondary/5 blur-[150px] -z-10 pointer-events-none"></div>
    </main>
  );
}

export default App;
