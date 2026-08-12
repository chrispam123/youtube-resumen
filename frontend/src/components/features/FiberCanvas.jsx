import { useRef, useEffect, useCallback, forwardRef } from 'react';

// =============================================================================
// FiberCanvas — Sistema de fibras neuronales de fondo
//
// 40 hebras que reaccionan a 4 estados del sistema:
//   idle   → vaivén sinusoidal suave, cian apagado
//   firing → lanzamiento con easing easeOutBack + chispeo, naranja ember
//   sync   → convergencia de fases, dorado
//   error  → disparo corto (lenScale 0.35), rojo alerta
//
// API imperativa: canvasElement._fiberSetState('firing')
// =============================================================================

// Colores por estado { r, g, b }
const COLORS = {
  idle:   { r: 15,  g: 74,  b: 66  },
  firing: { r: 242, g: 84,  b: 45  },
  sync:   { r: 244, g: 228, b: 184 },
  error:  { r: 226, g: 87,  b: 74  },
};

const FIBER_COUNT = 80;
const LAUNCH_MS = 260;

// ---------------------------------------------------------------------------
// Helpers (puras, fuera del componente)
// ---------------------------------------------------------------------------

function lerp(a, b, t) { return a + (b - a) * t; }

function lerpColor(c1, c2, t) {
  return {
    r: lerp(c1.r, c2.r, t),
    g: lerp(c1.g, c2.g, t),
    b: lerp(c1.b, c2.b, t),
  };
}

function easeOutBack(p) {
  const c1 = 1.7;
  const c3 = c1 + 1;
  return 1 + c3 * Math.pow(p - 1, 3) + c1 * Math.pow(p - 1, 2);
}

function createFibers() {
  return Array.from({ length: FIBER_COUNT }, () => ({
    xRatio:   0.5 + (Math.random() - 0.5) * 0.9 * (0.4 + Math.random() * 0.6),
    phase:    Math.random() * Math.PI * 2,
    speed:    0.4 + Math.random() * 0.5,
    baseLen:  (0.15 + Math.random() * 0.15) * 1.25,
    driftAmt: 6 + Math.random() * 10,
    width:    1.2 + Math.random() * 1.3,
    stagger:  Math.random() * 140,
    lean:     (Math.random() - 0.5) * 30,
    jitterSeed: Math.random() * 1000,
    nextJitterAt: 0,
    jitterX: 0,
  }));
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

const FiberCanvas = forwardRef(function FiberCanvas(_props, ref) {
  const canvasRef = useRef(null);
  const animId = useRef(0);
  const fibers = useRef(null);

  // Estado de la animación (mutable, sin triggers de render)
  const s = useRef({
    state: 'idle',
    stateT: 0,
    colorFrom: COLORS.idle,
    colorTo: COLORS.idle,
    energy: 0.22,
    energyTarget: 0.22,
    convergence: 0,
    convergenceTarget: 0,
    lenScale: 1,
    lenScaleTarget: 1,
    fireStartAt: 0,
    flashAt: -9999,
    flashStrength: 0.5,
  });

  // ---------------------------------------------------------------------------
  // Inicialización única: generación de hebras + loop + resize
  // ---------------------------------------------------------------------------

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    fibers.current = createFibers();

    const resize = () => {
      const dpr = window.devicePixelRatio || 1;
      canvas.width = window.innerWidth * dpr;
      canvas.height = window.innerHeight * dpr;
      const ctx = canvas.getContext('2d');
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    };

    resize();
    window.addEventListener('resize', resize);

    // Loop de animación como función local (evita referencia circular)
    let last = performance.now();

    function loop(now) {
      const dt = Math.min((now - last) / 1000, 0.05);
      last = now;

      // Interpolar variables de estado
      s.current.stateT = Math.min(s.current.stateT + dt * 1.2, 1);
      s.current.energy = lerp(s.current.energy, s.current.energyTarget, dt * 1.5);
      s.current.convergence = lerp(s.current.convergence, s.current.convergenceTarget, dt * 1.2);
      s.current.lenScale = lerp(s.current.lenScale, s.current.lenScaleTarget, dt * 2);

      const ctx = canvas.getContext('2d');
      const w = window.innerWidth;
      const h = window.innerHeight;

      ctx.clearRect(0, 0, w, h);
      ctx.globalCompositeOperation = 'lighter';

      const col = lerpColor(s.current.colorFrom, s.current.colorTo, Math.min(s.current.stateT, 1));
      const t = now / 1000;

      for (let i = 0; i < fibers.current.length; i++) {
        const f = fibers.current[i];
        const baseX = w * f.xRatio;
        const baseY = h + 20;
        const targetLen = h * f.baseLen * (0.6 + s.current.energy * 1.6) * s.current.lenScale;

        let len, topX, alphaBoost = 0;

        if (s.current.state === 'firing' || s.current.state === 'error') {
          const elapsed = now - s.current.fireStartAt - f.stagger;

          if (elapsed < 0) {
            len = 4;
            topX = baseX;
          } else if (elapsed < LAUNCH_MS) {
            const p = easeOutBack(Math.min(elapsed / LAUNCH_MS, 1));
            len = Math.max(4, targetLen * p);
            topX = baseX + f.lean * Math.min(elapsed / LAUNCH_MS, 1);
            alphaBoost = 0.4;
          } else {
            if (now > f.nextJitterAt) {
              f.jitterX = (Math.random() - 0.5) * f.driftAmt;
              f.nextJitterAt = now + 70 + Math.random() * 90;
            }
            len = targetLen + Math.sin(elapsed * 0.02 + f.jitterSeed) * targetLen * 0.03;
            topX = baseX + f.lean + f.jitterX;
            alphaBoost = 0.25 + Math.random() * 0.15;
          }
        } else {
          const sharedPhase = t * 0.6;
          const phase = lerp(f.phase, sharedPhase, s.current.convergence);
          const wobble = Math.sin(t * f.speed * 2 + phase) * f.driftAmt * (0.5 + s.current.energy * 0.8);
          len = targetLen;
          topX = baseX + wobble * (1 - s.current.convergence * 0.6);
        }

        const topY = baseY - len;
        const midX = baseX + (topX - baseX) * 0.5;
        const midY = baseY - len * 0.55;

        const flick = 0.55 + Math.sin(t * f.speed * 3 + f.phase * 1.3) * 0.2 * (0.4 + s.current.energy);
        const alpha = Math.max(0, Math.min(1, flick + alphaBoost)) * (0.35 + s.current.energy * 0.55);

        ctx.strokeStyle = `rgba(${col.r | 0},${col.g | 0},${col.b | 0},${alpha.toFixed(3)})`;
        ctx.lineWidth = f.width * (0.7 + s.current.energy * 0.6);
        ctx.lineCap = 'round';
        ctx.beginPath();
        ctx.moveTo(baseX, baseY);
        ctx.quadraticCurveTo(midX, midY, topX, topY);
        ctx.stroke();
      }

      // Flash de impacto
      const flashElapsed = now - s.current.flashAt;
      if (flashElapsed >= 0 && flashElapsed < 800) {
        const fp = flashElapsed / 800;
        const radius = (20 + fp * 160 * s.current.lenScale) * 1.5;
        const flashAlpha = (1 - fp) * s.current.flashStrength;
        const cx = w * 0.5;
        const cy = h + 10;
        const c = s.current.state === 'error' ? COLORS.error : COLORS.firing;
        const grad = ctx.createRadialGradient(cx, cy, 0, cx, cy, radius);
        grad.addColorStop(0, `rgba(${c.r},${c.g},${c.b},${flashAlpha})`);
        grad.addColorStop(1, `rgba(${c.r},${c.g},${c.b},0)`);
        ctx.fillStyle = grad;
        ctx.beginPath();
        ctx.arc(cx, cy, radius, 0, Math.PI * 2);
        ctx.fill();
      }

      ctx.globalCompositeOperation = 'source-over';
      animId.current = requestAnimationFrame(loop);
    }

    animId.current = requestAnimationFrame(loop);

    return () => {
      window.removeEventListener('resize', resize);
      cancelAnimationFrame(animId.current);
    };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // ---------------------------------------------------------------------------
  // Sincronizar ref externa
  // ---------------------------------------------------------------------------

  useEffect(() => {
    if (typeof ref === 'function') {
      ref(canvasRef.current);
    } else if (ref) {
      ref.current = canvasRef.current;
    }
  }, [ref]);

  // ---------------------------------------------------------------------------
  // API imperativa
  // ---------------------------------------------------------------------------

  const setState = useCallback((next) => {
    if (s.current.state === next) return;

    s.current.colorFrom = lerpColor(s.current.colorFrom, s.current.colorTo, Math.min(s.current.stateT, 1));
    s.current.colorTo = COLORS[next];
    s.current.stateT = 0;
    s.current.state = next;

    switch (next) {
      case 'idle':
        s.current.energyTarget = 0.22;
        s.current.convergenceTarget = 0;
        s.current.lenScaleTarget = 1;
        break;
      case 'firing':
        s.current.energyTarget = 1;
        s.current.convergenceTarget = 0;
        s.current.lenScaleTarget = 1;
        s.current.fireStartAt = performance.now();
        s.current.flashAt = s.current.fireStartAt;
        s.current.flashStrength = 0.5;
        break;
      case 'sync':
        s.current.energyTarget = 0.7;
        s.current.convergenceTarget = 1;
        s.current.lenScaleTarget = 1;
        break;
      case 'error':
        s.current.energyTarget = 0.6;
        s.current.convergenceTarget = 0;
        s.current.lenScaleTarget = 0.35;
        s.current.fireStartAt = performance.now();
        s.current.flashAt = s.current.fireStartAt;
        s.current.flashStrength = 0.3;
        break;
    }
  }, []);

  useEffect(() => {
    if (canvasRef.current) {
      canvasRef.current._fiberSetState = setState;
    }
  }, [setState]);

  return (
    <canvas
      ref={canvasRef}
      className="fiber-canvas"
      aria-hidden="true"
    />
  );
});

export default FiberCanvas;
