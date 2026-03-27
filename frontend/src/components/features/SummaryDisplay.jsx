const SummaryDisplay = ({ data }) => {
  // Verificación de seguridad: ¿Tenemos lo que necesitamos?
  if (!data || !data.summary) {
    console.error("ESTRUCTURA_DE_DATOS_INVALIDA:", data);
    return null;
  }

  // Extraemos para facilitar la lectura
  const { summary, title } = data;

  return (
    <article className="w-full max-w-6xl mt-24 animate-fade-in pb-24">
      <header className="mb-16">
        <div className="flex items-center gap-4 mb-4 opacity-50">
          <span className="h-[1px] w-12 bg-tertiary"></span>
          <span className="text-[10px] font-bold tracking-widest uppercase text-tertiary">
            RESUMEN_EJECUTIVO // FUENTE_VERIFICADA
          </span>
        </div>

        <h2 className="text-white text-4xl md:text-6xl font-bold tracking-tightest leading-none uppercase max-w-4xl">
          {title || "ANALISIS_COMPLETADO"}
        </h2>
      </header>

      <div className="grid grid-cols-1 lg:grid-cols-12 gap-12">
        <section className="lg:col-span-5">
          <h3 className="text-primary text-xs font-bold tracking-widest uppercase mb-6 opacity-80">
            // NUCLEO_CONCEPTOS
          </h3>
          <p className="text-secondary text-xl md:text-2xl font-medium leading-relaxed glitch-shadow">
            {summary.main_idea}
          </p>
        </section>

        <section className="lg:col-span-7 space-y-12">
          <div>
            <h3 className="text-tertiary text-xs font-bold tracking-widest uppercase mb-8 opacity-80">
              // CONCLUSIONES_CLAVE
            </h3>
            <ul className="space-y-8">
              {summary.key_points?.map((point, index) => (
                <li key={index} className="relative pl-8 group">
                  <div className="absolute left-0 top-0 w-[2px] h-full bg-gradient-to-b from-primary to-secondary opacity-40 group-hover:opacity-100 transition-opacity"></div>
                  <p className="text-white/80 text-lg leading-snug group-hover:text-white transition-colors">
                    {point}
                  </p>
                </li>
              ))}
            </ul>
          </div>

          <div className="bg-surface-high/40 backdrop-blur-md p-8 shadow-neon-primary">
            <h3 className="text-primary text-[10px] font-bold tracking-widest uppercase mb-4">
              // RESUMEN_FINAL
            </h3>
            <p className="text-white/70 italic leading-relaxed">
              {summary.conclusion}
            </p>
          </div>
        </section>
      </div>
    </article>
  );
};

export default SummaryDisplay;
