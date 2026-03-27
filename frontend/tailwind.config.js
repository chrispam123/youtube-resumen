/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        // Paleta "Chromatic Distortion"
        void: "#000000",
        surface: "#0e0e0e",
        "surface-low": "#131313",
        "surface-high": "#1f1f1f",
        primary: "#ff7cf5", // Neon Fuse
        secondary: "#ba84ff", // Atmospheric Purple
        tertiary: "#c1fffe", // High-voltage Cyan
        error: "#ff6e84",
        "outline-variant": "rgba(72, 72, 72, 0.15)", // Ghost Border
      },

      animation: {
        'fade-in': 'fade-in 1s ease-out forwards',
        },
     keyframes: {
       'fade-in': {
        '0%': { opacity: '0', transform: 'translateY(10px)' },
        '100%': { opacity: '1', transform: 'translateY(0)' },
      },
     },
      fontFamily: {
        sans: ['"Space Grotesk"', 'sans-serif'],
      },
      letterSpacing: {
        tightest: '-0.05em', // Para Display-LG
        widest: '0.1em',    // Para Label-SM
      },
      borderRadius: {
        none: '0px', // Regla estricta: Sharp edges
      },
      backgroundImage: {
        'liquid-light': 'linear-gradient(to right, #ff7cf5, #8300f2)',
      },
      boxShadow: {
        'neon-primary': '0 0 40px rgba(255, 124, 245, 0.1)', // Ambient Shadow
      }
    },
  },
  plugins: [],
}
