const API_BASE_URL = import.meta.env.VITE_API_URL || '/api';

export const api = {
  // FASE 1: Enviar la URL de YouTube para iniciar el análisis
  async analyzeVideo(videoUrl) {
  // Esto generará: https://d1kl02zr5h2zli.cloudfront.net/api/analyze
    const response = await fetch(`${API_BASE_URL}/analyze`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ url: videoUrl }),
    });
    if (!response.ok) throw new Error('FALLO_EN_CONEXION_NEURAL');
    return response.json(); // Devuelve { job_id, status }
  },

  // FASE 2: Consultar el estado del trabajo (Polling)
  async getJobStatus(jobId) {
    const response = await fetch(`${API_BASE_URL}/status/${jobId}`);
    if (!response.ok) throw new Error('ERROR_DE_SINCRONIZACION');
    return response.json(); // Devuelve { status, summary (si está DONE) }
  }
};
