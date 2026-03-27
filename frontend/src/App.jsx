import './App.css'

function App() {
  return (
    // Contenedor principal con el fondo "Void" y fuente Space Grotesk
    <main className="min-h-screen w-full bg-void flex flex-col items-center justify-center p-8">

      {/* TÍTULO DE PRUEBA: Usando Display-LG y Asimetría */}
      <h1 className="text-primary text-6xl font-bold tracking-tightest uppercase glitch-shadow mb-4">
        Neural_Sum
      </h1>

      {/* SUBTÍTULO: Usando Label-SM y espaciado amplio */}
      <p className="text-secondary text-xs font-bold tracking-widest uppercase opacity-70">
        System_Ready // Neural_Link_Established
      </p>

      {/* CAJA DE PRUEBA: Tonal Layering (Sin bordes, solo cambio de fondo) */}
      <div className="mt-12 w-full max-w-2xl h-32 bg-surface-low flex items-center justify-center shadow-neon-primary">
        <span className="text-tertiary text-sm font-medium">
          Esperando entrada de datos...
        </span>
      </div>

    </main>
  )
}

export default App
