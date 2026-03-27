import { useState, useRef } from 'react';
import { api } from '../services/api';

export const usePolling = () => {
  const [status, setStatus] = useState('IDLE'); // IDLE, PENDING, PROCESSING, DONE, ERROR
  const [result, setResult] = useState(null);
  const [error, setError] = useState(null);
  const timerRef = useRef(null);

  const startPolling = async (jobId) => {
    // Limpiamos cualquier temporizador previo
    if (timerRef.current) clearInterval(timerRef.current);

    // Función que se ejecuta cada 3 segundos
    timerRef.current = setInterval(async () => {
      try {
        const data = await api.getJobStatus(jobId);
        setStatus(data.status);

        if (data.status === 'DONE') {
          setResult(data.summary);
          clearInterval(timerRef.current);
        } else if (data.status === 'ERROR') {
          setError(data.message || 'ERROR_DESCONOCIDO');
          clearInterval(timerRef.current);
        }
      } catch (err) {
        setError(err.message);
        clearInterval(timerRef.current);
      }
    }, 3000); // Intervalo de 3 segundos según tu petición
  };

  return { status, result, error, setStatus, startPolling };
};
