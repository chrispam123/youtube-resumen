# YouTube Summarizer — Project Spec

**Versión**: 0.1.0  
**Estado**: borrador inicial  
**Última revisión**: 2025-03  
**Autor**: equipo de desarrollo  

> Este documento es la fuente de verdad del proyecto. Antes de modificar cualquier componente, lee la sección correspondiente para entender la intención original de la decisión. Si cambias una decisión arquitectónica, actualiza este Spec en el mismo PR.

---

## 1. Propósito del sistema

Una aplicación web que recibe la URL de un vídeo de YouTube y devuelve un resumen estructurado en español. El resumen incluye la idea principal, los puntos clave y una conclusión. Si la transcripción está en otro idioma, el modelo de IA la traduce dentro del mismo paso de generación.

El sistema está diseñado para un volumen de ~5.000 usuarios/mes con ~2 análisis por usuario (10.000 análisis/mes). No está diseñado para escalar a millones de usuarios, y las decisiones de coste reflejan esa premisa.

---

## 2. Decisiones arquitectónicas clave

Esta sección existe para que entiendas el *por qué* antes de cambiar el *qué*.

**Flujo asíncrono (Lambda → Fargate + polling).**  
El procesamiento completo de un vídeo tarda entre 30 y 60 segundos. El timeout máximo de API Gateway v2 es 30 segundos, por lo que una arquitectura síncrona no es viable. La solución es: Lambda responde inmediatamente con un `job_id`, lanza una tarea Fargate en segundo plano, y el browser hace polling cada 3 segundos hasta que el estado cambia a `DONE`. Este patrón se llama *fire-and-forget + polling* y es el estándar cuando el trabajo supera el timeout HTTP.

**Lambda para trabajo ligero, Fargate para trabajo pesado.**  
Lambda es ideal para operaciones cortas (validar, crear job, consultar estado). Fargate es ideal para trabajo intensivo de CPU/memoria de duración variable. Separar ambos respeta el principio de responsabilidad única y optimiza el coste: Lambda cobra por milisegundo, Fargate cobra por tarea completada.

**DynamoDB para estado de jobs, S3 para resultados.**  
DynamoDB tiene lectura de baja latencia (~1-5ms) y es perfecto para consultas de estado frecuentes durante el polling. S3 es más barato para almacenar los objetos JSON con el resumen completo. El campo `result_s3_key` en DynamoDB actúa de puntero hacia S3.

**YouTube Data API v3 en lugar de scraping.**  
Las IPs de AWS están bloqueadas por Google para extracción directa de transcripciones. La API oficial tiene un free tier de 10.000 unidades/día, suficiente para el volumen proyectado. Usar el canal oficial es la decisión correcta en un entorno profesional.

**Amazon Bedrock (Claude Haiku) como LLM.**  
Bedrock elimina la dependencia de una clave API externa y mantiene toda la arquitectura dentro del ecosistema AWS con autenticación por IAM. Claude Haiku tiene un coste de ~$0.00125 por 1.000 tokens de salida, lo que representa el coste dominante del sistema (~60$/mes a pleno rendimiento).

**API Gateway v2 (HTTP API) en lugar de v1 (REST API).**  
60% más barata y con menor latencia para casos de uso simples. La API v1 ofrece características como caché de respuestas y validación de modelos que no necesitamos en este proyecto.

**Estado de Terraform en S3 + bloqueo en DynamoDB.**  
El estado remoto permite que múltiples entornos y pipelines de CI/CD trabajen sobre la misma infraestructura sin conflictos. El bloqueo en DynamoDB evita que dos `terraform apply` corran en paralelo y corrompan el estado. Estos recursos se crean con el script de bootstrap antes de cualquier otra cosa.

---

## 3. Stack tecnológico

**Frontend**: React 18 + Vite. Desplegado como ficheros estáticos en S3, servido por CloudFront.

**Backend Lambda**: Python 3.12. Gestión de dependencias con `pip-tools` (`.in` → `.txt`). Entorno de desarrollo con `venv`.

**Backend Fargate**: Python 3.12. Empaquetado como imagen Docker. Registro en Amazon ECR.

**Infraestructura como código**: Terraform. Estado en S3. Módulos separados por dominio: `iam`, `storage`, `compute`, `networking`.

**Calidad de código**: `ruff` para Python (lint + format). `eslint` + `prettier` para JavaScript. `tflint` para Terraform. Todos ejecutados como pre-commit hooks.

**CI/CD**: GitHub Actions. CI automático en cada PR. CD a producción con aprobación manual mediante GitHub Environments.

**Secretos**: AWS Secrets Manager. Ninguna credencial en variables de entorno ni en el repositorio.

---

## 4. Estructura del repositorio

```
youtube-summarizer/
├── Makefile                        # interfaz única de operación del proyecto
├── .pre-commit-config.yaml
├── .github/
│   └── workflows/
│       ├── ci.yml                  # lint + test + terraform plan (automático en PR)
│       └── cd.yml                  # deploy (aprobación manual requerida)
├── infra/
│   ├── bootstrap/                  # se ejecuta una sola vez para crear el backend de tfstate
│   ├── modules/
│   │   ├── iam/
│   │   ├── storage/                # S3 buckets + DynamoDB tabla jobs
│   │   ├── compute/                # Lambda + ECS Fargate + ECR
│   │   └── networking/             # CloudFront + API Gateway v2
│   └── environments/
│       ├── dev/
│       └── prod/
├── backend/
│   ├── lambda/
│   │   ├── requirements.in
│   │   ├── requirements.txt        # generado, no editar manualmente
│   │   └── src/
│   │       ├── analyze.py          # handler POST /analyze
│   │       └── status.py           # handler GET /status/{job_id}
│   └── fargate/
│       ├── requirements.in
│       ├── requirements.txt
│       ├── Dockerfile
│       └── src/
│           └── main.py
├── frontend/
│   ├── package.json
│   └── src/
│       ├── App.jsx
│       ├── components/
│       │   ├── UrlInput.jsx
│       │   └── SummaryDisplay.jsx
│       └── hooks/
│           └── usePolling.js       # lógica de polling centralizada aquí
└── requirements-dev.in             # ruff, pre-commit, pytest
```

---

## 5. Modelo de datos

**DynamoDB — tabla `jobs`**

| Campo | Tipo | Descripción |
|---|---|---|
| `job_id` | String (PK) | UUID generado por Lambda al recibir la solicitud |
| `status` | String | `PENDING` → `PROCESSING` → `DONE` o `ERROR` |
| `video_id` | String | ID extraído de la URL de YouTube |
| `result_s3_key` | String | Clave S3 donde está el JSON del resumen (vacío hasta `DONE`) |
| `error_message` | String | Mensaje de error si `status = ERROR` |
| `created_at` | Number | Unix timestamp de creación |
| `ttl` | Number | Unix timestamp de expiración (creación + 86.400s = 24h) |

**S3 — bucket `yt-summarizer-results`**

Cada objeto sigue la clave `results/{job_id}.json` y contiene:

```json
{
  "job_id": "uuid",
  "video_id": "ABC123",
  "language_detected": "en",
  "summary": {
    "main_idea": "...",
    "key_points": ["...", "..."],
    "conclusion": "..."
  },
  "created_at": 1234567890
}
```

Los objetos expiran automáticamente a los 7 días mediante una política de lifecycle en S3.

---

## 6. Contrato de la API

Todas las rutas pasan por `https://{cloudfront-domain}/api/*`.

**POST /api/analyze**

```
Request:  { "url": "https://youtube.com/watch?v=VIDEO_ID" }
Response 202: { "job_id": "uuid", "status": "PENDING" }
Response 400: { "error": "URL de YouTube no válida" }
```

**GET /api/status/{job_id}**

```
Response 200 (en progreso): { "status": "PROCESSING" }
Response 200 (completado):  { "status": "DONE", "summary": { ... } }
Response 200 (error):       { "status": "ERROR", "message": "..." }
Response 404:               { "error": "job_id no encontrado" }
```

El cliente hace polling a `/status` cada 3 segundos. Si tras 120 segundos el estado no es `DONE`, el cliente para el polling y muestra un error de timeout al usuario.

---

## 7. IAM — usuarios y roles

**Usuarios humanos** (credenciales de larga duración, en `~/.aws/credentials`):

`iam-admin` tiene política `AdministratorAccess`. Se usa únicamente para crear el usuario de desarrollo y gestionar billing. No se usa para trabajo diario.

`iam-dev` tiene permisos de mínimo privilegio sobre los recursos del proyecto: S3, DynamoDB, Lambda, ECS, ECR, CloudFront, Secrets Manager y Bedrock. No tiene permisos de IAM ni de billing.

**Roles de servicio** (credenciales temporales, gestionadas por AWS):

`role-lambda-execution` es asumido por Lambda. Tiene permisos para escribir en DynamoDB, leer de S3, lanzar tareas ECS y escribir logs en CloudWatch.

`role-fargate-execution` es asumido por el contenedor ECS. Tiene permisos para escribir en S3, actualizar DynamoDB, obtener secretos de Secrets Manager e invocar Bedrock. No tiene permisos para lanzar nuevas tareas ECS, lo que limita el blast radius ante un fallo o compromiso del contenedor.

---

## 8. Flujo de trabajo con Git

Las ramas siguen esta convención:

- `main` — producción. Solo recibe merges desde `develop` vía PR con aprobación.
- `develop` — integración. Donde confluyen las ramas de trabajo.
- `feature/nombre-descriptivo` — nueva funcionalidad.
- `fix/nombre-descriptivo` — corrección de bug.
- `chore/nombre-descriptivo` — tareas de mantenimiento (deps, docs, config).

Ningún commit va directamente a `main` ni a `develop`. Todo pasa por PR. El CI debe estar en verde antes de que un PR pueda mergearse.

---

## 9. Comandos del Makefile

El Makefile es la interfaz de operación del proyecto. Si algo no está en el Makefile, no está automatizado.

| Comando | Qué hace |
|---|---|
| `make setup` | Instala venv, pip-tools, pre-commit hooks y dependencias de Node |
| `make compile-deps` | Regenera todos los `requirements.txt` desde los `.in` |
| `make lint` | Ejecuta ruff y eslint |
| `make test` | Ejecuta pytest |
| `make tf-bootstrap` | Crea S3 + DynamoDB para el estado de Terraform (solo una vez) |
| `make tf-init ENV=dev` | Inicializa Terraform con el backend remoto |
| `make tf-plan ENV=dev` | Muestra los cambios planificados |
| `make tf-apply ENV=dev` | Aplica los cambios (solo para dev desde local) |
| `make docker-build` | Construye la imagen del contenedor Fargate |
| `make docker-push` | Sube la imagen a ECR |
| `make clean` | Elimina artefactos: `.terraform/`, `dist/`, `__pycache__/` |

---

## 10. Estimación de costes (10.000 análisis/mes)

| Servicio | Coste estimado/mes |
|---|---|
| Amazon Bedrock (Claude Haiku) | ~$60 |
| ECS Fargate | ~$10 |
| CloudFront | ~$1.20 |
| S3 (resultados + frontend) | ~$0.50 |
| API Gateway v2 | ~$0.10 |
| Secrets Manager | ~$0.80 |
| DynamoDB | $0.00 (free tier) |
| Lambda | $0.00 (free tier) |
| **Total** | **~$72/mes** |

El LLM representa el 83% del coste total. La palanca de optimización más efectiva es el diseño del prompt (menos tokens de entrada = menos coste), no la infraestructura.

---

## 11. Registro de cambios del Spec

| Versión | Fecha | Cambio |
|---|---|---|
| 0.1.0 | 2025-03 | Documento inicial. Arquitectura base acordada. 

#Cuando modifiques una decisión arquitectónica, añade una entrada aquí explicando qué cambió y por qué. Esto es más valioso que cualquier comentario en el código.
