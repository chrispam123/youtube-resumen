# YUYAY — Project Spec

**Versión**: 1.0.0
**Estado**: actualizado tras revisión completa del código
**Última revisión**: 2026-08
**Autor**:Christian Gohring

> Este documento es la fuente de verdad del proyecto. Antes de modificar cualquier componente, lee la sección correspondiente para entender la intención original de la decisión. Si cambias una decisión arquitectónica, actualiza este Spec en el mismo PR.

---

## 1. Propósito del sistema

Una aplicación web que recibe la URL de un vídeo de YouTube y devuelve un resumen estructurado en español. El resumen incluye la idea principal, los puntos clave y una conclusión. Si la transcripción está en otro idioma, el modelo de IA la traduce dentro del mismo paso de generación.

El sistema está diseñado para un volumen de ~5.000 usuarios/mes con ~2 análisis por usuario (10.000 análisis/mes). No está diseñado para escalar a millones de usuarios, y las decisiones de COSTES  reflejan esa premisa.

---

## 2. Decisiones arquitectónicas clave

### Arquitectura general: API Gateway → Lambda → SQS → Lambda Consumer → Fargate

El flujo completo es:

```
Cliente (browser)
  │  POST /api/analyze { url }
  ▼
CloudFront → API Gateway v2 → Lambda analyze
  │  Valida URL, extrae video_id, crea job en DynamoDB (PENDING),
  │  publica mensaje en SQS, responde 202 { job_id }
  ▼
SQS (cola principal)
  │  Desacopla el Lambda analyze del trabajo pesado.
  │  Si el consumer falla, el mensaje reaparece (visibility timeout).
  │  Tras 3 fallos → DLQ.
  ▼
Lambda consumer (trigger: SQS event source mapping)
  │  Lee un mensaje de SQS (batch_size=1).
  │  Lanza tarea Fargate con job_id y video_id como variables de entorno.
  │  Si éxito → retorna OK → SQS borra el mensaje.
  │  Si fallo → lanza excepción → SQS reintenta.
  ▼
Fargate (contenedor Docker)
  │  1. Obtiene API keys de Secrets Manager (YouTube, Supadata, Gemini)
  │  2. Marca job como PROCESSING en DynamoDB
  │  3. Obtiene título del vídeo (YouTube Data API v3)
  │  4. Obtiene transcripción (Supadata API)
  │  5. Genera resumen con Gemini 2.5 Flash
  │  6. Guarda resultado en S3
  │  7. Marca job como DONE en DynamoDB
  │  Si falla → marca ERROR en DynamoDB
  ▼
Cliente (polling cada 3s)
  │  GET /api/status/{job_id}
  ▼
Lambda status
  │  Lee DynamoDB. Si DONE, lee S3 y devuelve el resumen.
```

### Por qué SQS en lugar de Lambda → Fargate directo

El patrón original (Lambda → Fargate directo) tiene un punto de fallo: si `ecs.run_task` falla, el job se pierde. Con SQS:
- **Desacoplamiento**: La Lambda `analyze` termina en milisegundos tras publicar en SQS.
- **Reintentos automáticos**: Si el consumer falla al lanzar Fargate, el mensaje reaparece y se reintenta hasta 3 veces.
- **DLQ**: Tras 3 fallos, el mensaje va a una Dead Letter Queue para inspección manual.
- **Control de concurrencia**: `batch_size=1` en el event source mapping evita saturar Fargate.

### Supadata API para transcripciones

Las IPs de AWS están bloqueadas por Google para extracción directa de transcripciones. En lugar de YouTube Data API v3 (que no expone transcripciones), usamos **Supadata API**, un servicio especializado en obtener transcripciones de YouTube de forma fiable y rápida. La YouTube Data API v3 se usa únicamente para obtener metadatos del vídeo (título).

### Google Gemini 2.5 Flash como LLM

Gemini 2.5 Flash ofrece un balance óptimo entre velocidad, calidad de resumen y coste. La API key se almacena en AWS Secrets Manager y se obtiene en tiempo de ejecución. El modelo se invoca a través de la librería oficial `google-generativeai`.

### API Gateway v2 (HTTP API) + CloudFront

La API Gateway v2 es un 60% más barata que la v1 y tiene menor latencia. CloudFront actúa como punto de entrada único con dos orígenes:
- **S3** para el frontend estático (React + Vite), accedido mediante Origin Access Control (OAC).
- **API Gateway** para las rutas `/api/*`, sin caché.

### DynamoDB para estado de jobs, S3 para resultados

DynamoDB tiene lectura de baja latencia (~1-5ms) ideal para el polling del cliente. S3 es más barato para almacenar los JSON con el resumen completo. El campo `result_s3_key` en DynamoDB actúa de puntero hacia S3. Ambos tienen TTL/políticas de expiración para controlar costes automáticamente.

### Estado de Terraform en S3 con lockfile nativo

El estado remoto permite que CI/CD trabaje sin conflictos. El bloqueo se implementa mediante `use_lockfile = true`, el mecanismo nativo de S3 que reemplaza a DynamoDB para state locking, simplificando la infraestructura de bootstrap.

---

## 3. Stack tecnológico

**Frontend**: React 19 + Vite 6. Desplegado como ficheros estáticos en S3, servido por CloudFront con OAC. Estilo con Tailwind CSS 3.4. Diseño visual "Chromatic Distortion" (tema cyberpunk/neón) con fuente Space Grotesk.

**Backend Lambda (handlers)**: Python 3.12. Tres funciones: `analyze`, `status`, `consumer`. Gestión de dependencias con `pip-tools` (`.in` → `.txt`). Empaquetado como ZIP para despliegue.

**Backend Fargate (processor)**: Python 3.12. Empaquetado como imagen Docker multi-stage. Dependencias: `boto3`, `google-generativeai`, `google-api-python-client`, `requests`. Registro en Amazon ECR.

**Infraestructura como código**: Terraform >= 1.7, provider AWS ~> 5.0. Estado en S3 con lockfile nativo. Módulos separados por dominio: `iam`, `storage`, `compute`, `networking`, `mensajes`.

**Calidad de código**:
- Python: `ruff` (lint + format)
- JavaScript: `eslint` + `prettier`
- Terraform: `terraform fmt` + `terraform validate`
- Todos ejecutados como pre-commit hooks y en CI

**CI/CD**: GitHub Actions.
- **CI**: `ci.yml` — ruff, eslint, terraform validate en cada PR y push a `main`/`develop`.
- **CD**: `cd.yml` — terraform apply + deploy Lambdas + build frontend + sync S3 + invalidación CloudFront. Se ejecuta en push a `main` con aprobación manual mediante GitHub Environments (`environment: production`).

**Secretos**: AWS Secrets Manager. Tres secretos: `/app/youtube-api-key`, `/app/supadata-api-key`, `/app/gemini-api-key`. Ninguna credencial en variables de entorno ni en el repositorio.

---

## 4. Estructura del repositorio

```
youtube-resumen/
├── Makefile                              # Interfaz única de operación del proyecto
├── pyproject.toml                        # Configuración de ruff y pytest
├── .pre-commit-config.yaml               # Hooks: ruff, eslint, terraform, generales
├── requirements-dev.in                   # Dependencias de desarrollo (ruff, pytest, moto...)
├── requirements-dev.txt                  # Compilado, no editar manualmente
├── .github/
│   └── workflows/
│       ├── ci.yml                        # Lint + test + terraform validate (PR y push)
│       └── cd.yml                        # Deploy completo (push a main, aprobación manual)
├── infra/
│   ├── bootstrap/
│   │   └── main.tf                       # Crea bucket S3 para tfstate (se ejecuta una vez)
│   ├── modules/
│   │   ├── iam/                          # Usuario dev, roles Lambda y Fargate
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── storage/                      # S3 (resultados + frontend) + DynamoDB (jobs)
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── compute/                      # ECR + ECS/Fargate + Lambdas + API Gateway routes
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── networking/                   # API Gateway v2 + CloudFront + OAC
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   └── mensajes/                     # SQS cola principal + DLQ
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       └── outputs.tf
│   └── environments/
│       ├── dev/                          # Entorno de desarrollo
│       │   ├── main.tf                   # Orquesta todos los módulos
│       │   ├── variables.tf
│       │   ├── outputs.tf
│       │   └── terraform.tfvars.example
│       └── prod/                         # Entorno de producción (pendiente de implementar)
│           └── .gitkeep
├── backend/
│   ├── handlers/                         # Lambdas (analyze, status, consumer)
│   │   ├── requirements.in               # Solo boto3 (disponible en runtime AWS)
│   │   ├── requirements.txt
│   │   ├── src/
│   │   │   ├── analyze.py                # POST /api/analyze — valida URL, crea job, publica en SQS
│   │   │   ├── status.py                 # GET /api/status/{job_id} — consulta estado y resultados
│   │   │   └── consumer.py               # Trigger SQS — lanza tarea Fargate
│   │   └── tests/
│   │       ├── test_analyze.py
│   │       └── test_status.py
│   └── fargate/                          # Contenedor de procesamiento pesado
│       ├── requirements.in               # boto3, google-generativeai, google-api-python-client, requests
│       ├── requirements.txt
│       ├── Dockerfile                    # Multi-stage build, usuario no-root
│       └── src/
│           └── main.py                   # Orquesta: Secrets → YouTube API → Supadata → Gemini → S3
└── frontend/
    ├── package.json                      # React 19, Vite 6, Tailwind CSS 3.4
    ├── vite.config.js                    # Proxy /api → CloudFront en desarrollo
    ├── tailwind.config.js                # Tema "Chromatic Distortion"
    ├── index.html                        # Fuente Space Grotesk
    └── src/
        ├── main.jsx                      # Entry point
        ├── App.jsx                       # Layout principal, estado del resumen
        ├── components/
        │   └── features/
        │       ├── TerminalInput.jsx     # Input de URL + botón analizar + barra de progreso
        │       └── SummaryDisplay.jsx     # Visualización del resumen estructurado
        ├── hooks/
        │   └── usePolling.js             # Lógica de polling cada 3s, estados IDLE→PENDING→PROCESSING→DONE/ERROR
        └── services/
            └── api.js                    # Cliente HTTP: analyzeVideo(), getJobStatus()
```

---

## 5. Modelo de datos

### DynamoDB — tabla `jobs`

| Campo | Tipo | Descripción |
|---|---|---|
| `job_id` | String (PK) | UUID v4 generado por Lambda analyze |
| `status` | String | `PENDING` → `PROCESSING` → `DONE` o `ERROR` |
| `video_id` | String | ID de 11 caracteres extraído de la URL de YouTube |
| `result_s3_key` | String | Clave S3 donde está el JSON del resumen (ej: `results/{job_id}.json`). Vacío hasta `DONE`. |
| `error_message` | String | Mensaje de error si `status = ERROR` |
| `created_at` | Number | Unix timestamp de creación |
| `updated_at` | Number | Unix timestamp de la última actualización de estado |
| `ttl` | Number | Unix timestamp de expiración (creación + 24h). DynamoDB borra el item automáticamente. |

### S3 — bucket de resultados

Cada objeto sigue la clave `results/{job_id}.json` y contiene:

```json
{
  "job_id": "uuid",
  "video_title": "Título del vídeo en YouTube",
  "summary": {
    "main_idea": "Idea principal en español",
    "key_points": ["Punto clave 1", "Punto clave 2", "Punto clave 3"],
    "conclusion": "Conclusión o mensaje final"
  },
  "processed_at": 1234567890
}
```

Los objetos expiran automáticamente a los 7 días mediante lifecycle policy en S3. Las versiones no actuales se limpian a 1 día.

### SQS — cola de jobs

| Propiedad | Valor |
|---|---|
| Nombre | `{project_name}-jobs-{environment}` |
| Visibility timeout | 300s (5 minutos) |
| Message retention | 86.400s (24 horas) |
| Max receives (DLQ) | 3 intentos |
| DLQ retention | 1.209.600s (14 días) |

Mensaje publicado por Lambda analyze:
```json
{ "job_id": "uuid", "video_id": "dQw4w9WgXcQ" }
```

---

## 6. Contrato de la API

Todas las rutas pasan por `https://{cloudfront-domain}/api/*`. CloudFront reenvía sin caché las peticiones a API Gateway v2.

### POST /api/analyze

```
Request:  { "url": "https://youtube.com/watch?v=VIDEO_ID" }
Response 202: { "job_id": "uuid", "status": "PENDING" }
Response 400: { "error": "URL de YouTube no válida. Formatos aceptados: ..." }
Response 400: { "error": "El campo 'url' es requerido" }
Response 400: { "error": "El body debe ser JSON válido" }
Response 500: { "error": "Error interno al crear el job" }
```

Formatos de URL aceptados:
- `https://www.youtube.com/watch?v=VIDEO_ID`
- `https://youtube.com/watch?v=VIDEO_ID&otros_params=valor`
- `https://youtu.be/VIDEO_ID`

### GET /api/status/{job_id}

```
Response 200 (en progreso):  { "status": "PENDING" } o { "status": "PROCESSING" }
Response 200 (completado):   { "status": "DONE", "summary": { "main_idea": "...", "key_points": [...], "conclusion": "..." } }
Response 200 (error):        { "status": "ERROR", "message": "..." }
Response 400:                { "error": "job_id es requerido" }
Response 404:                { "error": "Job 'uuid' no encontrado" }
Response 500:                { "error": "Error interno al consultar el estado" }
```

El cliente hace polling a `/status` cada 3 segundos. Si tras 120 segundos el estado no es `DONE`, el cliente para el polling y muestra un error de timeout.

---

## 7. Flujo de procesamiento Fargate

El contenedor `main.py` ejecuta el siguiente pipeline secuencial:

```
1. Secrets Manager → Obtiene 3 API keys:
   - /app/youtube-api-key    → YouTube Data API v3 (metadatos)
   - /app/supadata-api-key   → Supadata (transcripción)
   - /app/gemini-api-key     → Google Gemini (resumen)

2. DynamoDB → Marca job como PROCESSING

3. YouTube Data API v3 → Obtiene título del vídeo
   Endpoint: youtube.videos().list(part="snippet", id=VIDEO_ID)

4. Supadata API → Obtiene transcripción completa y código de idioma
   Endpoint: GET https://api.supadata.ai/v1/youtube/transcript?url=...

5. Gemini 2.5 Flash → Genera resumen estructurado
   - Prompt incluye la transcripción (truncada a 15.000 caracteres)
   - Instrucción condicional: "Traduce y resume en ESPAÑOL" si el idioma no es español
   - Se extrae el JSON de la respuesta con regex

6. S3 → Guarda resultado JSON en results/{job_id}.json

7. DynamoDB → Marca job como DONE con result_s3_key
```

En caso de error en cualquier paso, el job se marca como `ERROR` con el mensaje de excepción y el contenedor sale con código 1.

---

## 8. IAM — roles y políticas

### Usuario de desarrollo (`{project_name}-dev-{environment}`)

- **ReadOnlyAccess** (AWS managed): permite ver todos los recursos para que Terraform refresh no falle.
- **Política de escritura del proyecto**: permisos sobre recursos con prefijo `{project_name}-*` en S3, DynamoDB, ECS, ECR, SQS, API Gateway, CloudFront, Secrets Manager (`/app/*`), Lambda, Logs. Incluye `iam:*` para crear/gestionar roles.

### Rol Lambda Execution

Asumido por las funciones Lambda (`analyze`, `status`, `consumer`). Permisos:
- `logs:*` — escritura en CloudWatch
- `dynamodb:PutItem`, `dynamodb:GetItem`, `dynamodb:UpdateItem` — tabla de jobs
- `s3:GetObject` — lectura de resultados
- `ecs:RunTask` — lanzar tareas Fargate
- `iam:PassRole` — pasar el rol a la tarea Fargate
- `sqs:*` — publicar y consumir mensajes

### Rol Fargate Execution

Asumido por las tareas ECS Fargate. Permisos:
- `logs:*` — escritura en CloudWatch
- `s3:PutObject` — guardar resultados
- `dynamodb:UpdateItem` — actualizar estado del job
- `secretsmanager:GetSecretValue` — obtener API keys de `/app/*`
- `bedrock:InvokeModel` — heredado, no usado actualmente (se usa Gemini vía API key)
- `AmazonECSTaskExecutionRolePolicy` (AWS managed) — permisos base para ECS

---

## 9. Infraestructura como código

### Bootstrap (se ejecuta UNA vez)

Crea el bucket S3 con versionado, cifrado y bloqueo público para almacenar el estado de Terraform. El estado del bootstrap se guarda localmente (no en remoto).

### Módulo `iam`

- Crea usuario IAM de desarrollo con access keys y políticas.
- Crea roles de servicio para Lambda y Fargate con políticas de mínimo privilegio.

### Módulo `storage`

- **S3 results**: bucket con versionado, cifrado SSE-S3, bloqueo público, lifecycle policy (expira resultados a los 7 días, versiones no actuales a 1 día).
- **S3 frontend**: bucket con versionado, cifrado, bloqueo público. NO es público — solo CloudFront accede vía OAC.
- **DynamoDB jobs**: tabla con clave `job_id`, billing PAY_PER_REQUEST, TTL habilitado sobre campo `ttl`, point-in-time recovery habilitado.

### Módulo `compute`

- **ECR**: repositorio para la imagen Docker con escaneo al push y lifecycle (últimas 5 imágenes).
- **ECS Fargate**: cluster con Container Insights, task definition (0.5 vCPU, 1 GB RAM), log group CloudWatch.
- **Lambda analyze**: Python 3.12, 256 MB, timeout 29s. Variables de entorno para DynamoDB, S3, ECS, SQS.
- **Lambda status**: Python 3.12, 128 MB, timeout 10s. Variables de entorno para DynamoDB y S3.
- **Lambda consumer**: Python 3.12, 256 MB, timeout 120s. Variables de entorno para ECS y subnets.
- **API Gateway integrations**: rutas `POST /api/analyze` y `GET /api/status/{job_id}`.
- **SQS event source mapping**: conecta la cola SQS con el Lambda consumer, `batch_size=1`.

### Módulo `networking`

- **API Gateway v2**: HTTP API con stage `$default`, auto-deploy, logging CloudWatch, CORS configurado.
- **CloudFront**: distribución con dos orígenes (S3 + API Gateway), OAC para S3, sin caché en rutas `/api/*`, SPA routing (404/403 → index.html), PriceClass_100, certificado por defecto de CloudFront.
- **Política S3 OAC**: permite acceso al bucket del frontend solo desde CloudFront.

### Módulo `mensajes`

- **SQS cola principal**: visibility timeout 300s, retention 24h, redrive policy a DLQ tras 3 intentos.
- **SQS DLQ**: retention 14 días para inspección manual de fallos.
- **Política SQS**: permite a Lambda publicar y consumir mensajes.

---

## 10. Flujo de trabajo con Git

- `main` — producción. Solo recibe merges vía PR con CI verde + aprobación.
- `develop` — integración. Donde confluyen las ramas de trabajo.
- `feature/nombre-descriptivo` — nueva funcionalidad.
- `fix/nombre-descriptivo` — corrección de bug.
- `chore/nombre-descriptivo` — tareas de mantenimiento (deps, docs, config).

Ningún commit va directamente a `main` ni a `develop`. Todo pasa por PR. El CI debe estar en verde antes de que un PR pueda mergearse.

---

## 11. CI/CD

### CI (`ci.yml`)

Se ejecuta en:
- `pull_request` a `main` o `develop`
- `push` a `main` o `develop`

Jobs:
1. **Python**: `ruff check` + `ruff format --check` sobre `backend/`
2. **Frontend**: `npm ci` + `npm run lint` (eslint)
3. **Terraform**: `terraform init -backend=false` + `terraform fmt -check` + `terraform validate` en `infra/environments/dev`

### CD (`cd.yml`)

Se ejecuta en push a `main`. Requiere aprobación manual (GitHub Environment `production`).

Jobs:
1. **Configurar credenciales AWS** desde GitHub Secrets
2. **Terraform Apply**: inicializa y aplica infraestructura en `infra/environments/dev`
3. **Deploy Lambdas**: `make lambda-deploy` sin perfil AWS (usa credenciales del paso 1)
4. **Build Frontend**: `npm ci` + `npm run build` con `VITE_API_URL` apuntando a CloudFront
5. **Deploy Frontend**: `aws s3 sync` al bucket del frontend
6. **Invalidación CloudFront**: `aws cloudfront create-invalidation --paths "/*"`

---

## 12. Comandos del Makefile

| Comando | Qué hace |
|---|---|
| `make setup` | Instala venv, pip-tools, compila dependencias, configura pre-commit hooks |
| `make compile-deps` | Regenera todos los `requirements.txt` desde los `.in` |
| `make sync-deps` | Instala las dependencias compiladas en el venv |
| `make lint` | Ejecuta ruff check + ruff format sobre `backend/` |
| `make lint-fix` | Corrige automáticamente errores de ruff |
| `make test` | Ejecuta pytest con cobertura |
| `make tf-bootstrap` | Crea bucket S3 para estado de Terraform (solo una vez) |
| `make tf-init ENV=dev` | Inicializa Terraform con backend remoto |
| `make tf-plan ENV=dev` | Muestra cambios planificados |
| `make tf-apply ENV=dev` | Aplica cambios (solo dev, prod bloqueado) |
| `make tf-destroy ENV=dev` | Destruye infraestructura (solo dev) |
| `make docker-build` | Construye imagen Docker del procesador Fargate |
| `make docker-push` | Guía para subir imagen a ECR |
| `make lambda-package` | Empaqueta código Lambda en ZIP |
| `make lambda-deploy` | Empaqueta y despliega las 3 Lambdas a AWS |
| `make clean` | Elimina `__pycache__/`, `.terraform/`, `dist/`, `.pytest_cache/` |

---

## 13. Diseño del frontend

### Tema visual: "Chromatic Distortion"

- **Tipografía**: Space Grotesk (Google Fonts), pesos 300–700
- **Paleta de colores**:
  - Fondo: `#000000` (void), superficies: `#0e0e0e` a `#1f1f1f`
  - Primary (Neon Fuse): `#ff7cf5`
  - Secondary (Atmospheric Purple): `#ba84ff`
  - Tertiary (High-voltage Cyan): `#c1fffe`
  - Error: `#ff6e84`
- **Estética**: Bordes rectos (sin border-radius), sombras de neón, animaciones glitch, gradientes líquidos, barras de progreso animadas.
- **Componentes**:
  - `TerminalInput`: input de URL + botón "ANALIZAR" con estados visuales para cada fase del proceso.
  - `SummaryDisplay`: layout asimétrico de 2 columnas (5+7) mostrando idea principal, puntos clave con barras de gradiente, y conclusión en panel destacado.
- **Responsive**: diseño mobile-first con breakpoints en `md` y `lg`.

### Flujo de usuario

1. Usuario pega URL de YouTube → pulsa ANALIZAR
2. El botón se deshabilita, aparece barra de progreso animada
3. El hook `usePolling` consulta `/api/status/{job_id}` cada 3 segundos
4. Al recibir `DONE`, el resumen se renderiza con animación fade-in
5. El input permanece visible para nuevas consultas

---

## 14. Estimación de costes (10.000 análisis/mes)

| Servicio | Coste estimado/mes | Notas |
|---|---|---|
| Google Gemini 2.5 Flash | ~$15–25 | Truncado a 15K chars de entrada. Más barato que Bedrock Claude. |
| Supadata API | ~$5–10 | Depende del plan de precios de Supadata |
| ECS Fargate | ~$10 | Tareas de ~60s con 0.5 vCPU / 1 GB |
| CloudFront | ~$1.20 | PriceClass_100 (Europa + Norteamérica) |
| S3 | ~$0.50 | Resultados + frontend, con expiración automática |
| API Gateway v2 | ~$0.10 | HTTP API es la opción más barata |
| Secrets Manager | ~$1.20 | 3 secretos × $0.40/por secreto |
| DynamoDB | $0.00 | Free tier cubre el volumen proyectado |
| Lambda | $0.00 | Free tier cubre las 3 funciones |
| **Total** | **~$30–50/mes** | El LLM sigue siendo el coste dominante |

---

## 15. Registro de cambios del Spec

| Versión | Fecha | Cambio |
|---|---|---|
| 0.1.0 | 2025-03 | Documento inicial. Arquitectura base: Lambda → Fargate directo, Bedrock/Claude Haiku, YouTube API para transcripción. |
| 1.0.0 | 2026-08 | Reescritura completa tras revisión del código real. Cambios mayores: (1) Arquitectura Lambda → SQS → Lambda Consumer → Fargate con DLQ. (2) LLM migrado de Bedrock/Claude Haiku a Google Gemini 2.5 Flash. (3) Transcripciones vía Supadata API en lugar de YouTube API. (4) Terraform state locking con S3 lockfile nativo en lugar de DynamoDB. (5) Nuevo módulo infra `mensajes` para SQS. (6) Frontend rediseñado con tema "Chromatic Distortion" (neón/cyberpunk). (7) Fargate processor obtiene 3 API keys de Secrets Manager. (8) Actualizados modelo de datos, costes, y estructura del repositorio. |
