import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      // Redirigimos las llamadas de /api a tu CloudFront real
      '/api': {
        target: 'https://d1kl02zr5h2zli.cloudfront.net',
        changeOrigin: true,
        // No reescribimos el path porque tu API Gateway ya espera /api/analyze
        secure: true,
      }
    }
  }
})
