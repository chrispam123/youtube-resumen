
# =============================================================================
# Variables de configuración
# =============================================================================

# Detecta el sistema operativo para pequeñas diferencias de comportamiento
OS := $(shell uname -s)

# Directorio del entorno virtual de Python
VENV := .venv
PYTHON := $(VENV)/bin/python
PIP := $(VENV)/bin/pip
PIP_COMPILE := $(VENV)/bin/pip-compile
PIP_SYNC := $(VENV)/bin/pip-sync

# Variable de entorno para los targets de Terraform
ENV ?= dev

# =============================================================================
# Target por defecto — se ejecuta si llamas a 'make' sin argumentos
# =============================================================================

.DEFAULT_GOAL := help

help: ## Muestra este mensaje de ayuda
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

# =============================================================================
# Configuración del entorno local
# =============================================================================

$(VENV)/bin/activate: ## Crea el entorno virtual si no existe
	python3 -m venv $(VENV)
	$(PIP) install --upgrade pip pip-tools

setup: $(VENV)/bin/activate ## Instala todas las dependencias y configura pre-commit
	$(PIP_COMPILE) requirements-dev.in -o requirements-dev.txt
	$(PIP_COMPILE) backend/handlers/requirements.in -o backend/handlers/requirements.txt
	$(PIP_COMPILE) backend/fargate/requirements.in -o backend/fargate/requirements.txt
	$(PIP_SYNC) requirements-dev.txt
	$(VENV)/bin/pre-commit install
	@echo ""
	@echo "✓ Entorno listo. Activa el venv con: source .venv/bin/activate"

compile-deps: $(VENV)/bin/activate ## Regenera todos los requirements.txt desde los .in
	$(PIP_COMPILE) requirements-dev.in -o requirements-dev.txt
	$(PIP_COMPILE) backend/handlers/requirements.in -o backend/handlers/requirements.txt
	$(PIP_COMPILE) backend/fargate/requirements.in -o backend/fargate/requirements.txt
	@echo "✓ Dependencias compiladas. Ejecuta 'make sync-deps' para instalarlas."

sync-deps: $(VENV)/bin/activate ## Instala las dependencias compiladas en el venv
	$(PIP_SYNC) requirements-dev.txt

# =============================================================================
# Calidad de código
# =============================================================================

lint: $(VENV)/bin/activate ## Ejecuta ruff (Python) sobre el código backend
	$(VENV)/bin/ruff check backend/
	$(VENV)/bin/ruff format --check backend/
	@echo "✓ Lint Python OK"

lint-fix: $(VENV)/bin/activate ## Corrige automáticamente los errores de ruff
	$(VENV)/bin/ruff check --fix backend/
	$(VENV)/bin/ruff format backend/

test: $(VENV)/bin/activate ## Ejecuta los tests con cobertura
	$(VENV)/bin/pytest backend/ -v --cov=backend --cov-report=term-missing

# =============================================================================
# Terraform
# =============================================================================

tf-bootstrap: ## Crea el bucket S3 y tabla DynamoDB para el estado (solo una vez)
	cd infra/bootstrap && terraform init && terraform apply

tf-init: ## Inicializa Terraform para el entorno especificado (ENV=dev por defecto)
	cd infra/environments/$(ENV) && terraform init

tf-plan: ## Muestra los cambios planificados para el entorno (ENV=dev por defecto)
	cd infra/environments/$(ENV) && terraform plan

tf-apply: ## Aplica los cambios en el entorno (solo dev desde local)
	@if [ "$(ENV)" = "prod" ]; then \
		echo "ERROR: apply a prod solo se hace desde el pipeline de CD, no desde local."; \
		exit 1; \
	fi
	cd infra/environments/$(ENV) && terraform apply

tf-destroy: ## Destruye la infraestructura del entorno (solo dev)
	@if [ "$(ENV)" = "prod" ]; then \
		echo "ERROR: destroy en prod no está permitido desde local."; \
		exit 1; \
	fi
	cd infra/environments/$(ENV) && terraform destroy

# =============================================================================
# Docker / Fargate
# =============================================================================

docker-build: ## Construye la imagen del contenedor Fargate localmente
	docker build -t yt-processor:local backend/fargate/

docker-push: ## Sube la imagen a ECR (requiere credenciales AWS configuradas)
	@echo "Usa el pipeline de CD para push a ECR en producción."
	@echo "Para dev: configura ECR_URI en tu entorno y ejecuta manualmente."

lambda-package: $(VENV)/bin/activate ## Empaqueta el código Lambda en un ZIP para el deploy
	@echo "Empaquetando Lambda..."
	rm -rf backend/handlers/package backend/handlers/lambda.zip
	$(PIP) install -r backend/handlers/requirements.in \
		-t backend/handlers/package/ --quiet
	cp backend/handlers/src/*.py backend/handlers/package/
	cd backend/handlers/package && zip -r ../lambda.zip . \
		-x "*.pyc" -x "*__pycache__*"
	@echo "✓ Lambda empaquetada en backend/handlers/lambda.zip"

lambda-deploy: lambda-package ## Despliega el código Lambda a AWS
	aws lambda update-function-code \
		--function-name yt-summarizer-analyze-dev \
		--zip-file fileb://backend/handlers/lambda.zip \
		--profile dev
	aws lambda update-function-code \
		--function-name yt-summarizer-status-dev \
		--zip-file fileb://backend/handlers/lambda.zip \
		--profile dev
	@echo "✓ Lambda desplegada"

# =============================================================================
# Limpieza
# =============================================================================

clean: ## Elimina artefactos generados: .terraform/, dist/, __pycache__/
	find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name ".pytest_cache" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	find . -name "*.tfplan" -delete 2>/dev/null || true
	rm -rf frontend/dist/
	@echo "✓ Limpieza completada"

.PHONY: help setup compile-deps sync-deps lint lint-fix test \
        tf-bootstrap tf-init tf-plan tf-apply tf-destroy \
        docker-build docker-push clean
