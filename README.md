# YouTube Resumido

Aplicación web que recibe una URL de YouTube y devuelve un resumen estructurado en español.

## Documentación

Antes de tocar cualquier fichero, lee el [SPEC.md](./SPEC.md).

## Requisitos previos

- AWS CLI configurado con perfil `dev`
- Terraform >= 1.7
- Python >= 3.12
- Node >= 20
- Docker

## Inicio rápido
```bash
# 1. Clona el repositorio
git clone git@github.com:tu-usuario/youtube-summarizer.git
cd youtube-summarizer

# 2. Configura el entorno local completo
make setup

# 3. Lee el SPEC antes de continuar
```

## Bloques de infraestructura

El proyecto se despliega en bloques independientes. Consulta el SPEC para el orden correcto.

## Estado del proyecto

En desarrollo activo. Ver [SPEC.md](./SPEC.md) para decisiones arquitectónicas.
