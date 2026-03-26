
# =============================================================================
# Imagen del procesador Fargate
#
# Usamos una imagen slim de Python para reducir el tamaño final.
# El multi-stage build separa las dependencias del código para
# aprovechar el cache de Docker en rebuilds.
# =============================================================================

# Stage 1: instalación de dependencias
FROM python:3.12-slim AS builder

WORKDIR /build

# Copia solo los ficheros de dependencias primero.
# Docker cachea esta capa y no la reconstruye si requirements.txt no cambia,
# lo que hace los rebuilds mucho más rápidos.
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt --target /build/deps

# Stage 2: imagen final
FROM python:3.12-slim

# Usuario no root — nunca ejecutes contenedores de producción como root
RUN useradd --create-home --shell /bin/bash appuser

WORKDIR /app

# Copia las dependencias del stage anterior
COPY --from=builder /build/deps /app/deps

# Copia el código fuente
COPY src/ /app/src/

# Ajusta el PYTHONPATH para que Python encuentre las dependencias y el código
ENV PYTHONPATH="/app/deps:/app/src"

# Cambia al usuario no root
USER appuser

# El entrypoint ejecuta main.py directamente.
# Fargate lanza el contenedor, main.py corre, y cuando termina el contenedor muere.
# AWS deja de cobrar en ese momento.
CMD ["python", "/app/src/main.py"]
