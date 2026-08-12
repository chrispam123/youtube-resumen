// =============================================================================
// BrandHeader — Marca Yuyay + status del sistema
//
// Props:
//   systemState  'idle' | 'firing' | 'sync' | 'error'
// =============================================================================

const STATUS_LABEL = {
  idle:   'SYNAPSE_LINK_STABLE',
  firing: 'FIBER_BURST // ANALIZANDO',
  sync:   'FIBER_SYNC // CONCLUSION ESTABILIZADA',
  error:  'FIBER_FAULT',
};

const STATUS_COLOR = {
  idle:   'var(--reposo)',
  firing: 'var(--disparo)',
  sync:   'var(--sincronia)',
  error:  'var(--alert)',
};

const BrandHeader = ({ systemState }) => (
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

    <div className="status" style={{ color: STATUS_COLOR[systemState] }}>
      <span className="status-dot" />
      <span>{STATUS_LABEL[systemState]}</span>
    </div>
  </header>
);

export default BrandHeader;
