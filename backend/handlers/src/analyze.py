# Lambda handler: POST /api/analyze
"""
Responsabilidades:
  1. Validar la URL de YouTube
  2. Extraer el video_id
  3. Crear el job en DynamoDB con estado PENDING job_id
  4. Lanzar la tarea Fargate
  5. Responder 202 con el job_id

Este handler debe ser rápido. No hace trabajo pesado.
Todo el procesamiento ocurre en Fargate de forma asíncrona.
"""

import json
import logging
import os
import re
import time
import uuid

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Clientes AWS inicializados fuera del handler para reutilizar
# la conexión entre invocaciones calientes de Lambda.
dynamodb = boto3.resource("dynamodb")
ecs_client = boto3.client("ecs")

# Variables de entorno — definidas en la task definition de Terraform
DYNAMODB_TABLE = os.environ["DYNAMODB_TABLE"]
ECS_CLUSTER = os.environ["ECS_CLUSTER"]
ECS_TASK_DEFINITION = os.environ["ECS_TASK_DEFINITION"]
FARGATE_ROLE_ARN = os.environ["FARGATE_ROLE_ARN"]
AWS_ACCOUNT_ID = os.environ["AWS_ACCOUNT_ID"]
ENVIRONMENT = os.environ.get("ENVIRONMENT", "dev")
SUBNET_IDS = os.environ["SUBNET_IDS"].split(",")  # "subnet-xxx,subnet-yyy"


# Patrón para validar y extraer el video_id de URLs de YouTube.
# Cubre los formatos más comunes:
#   https://www.youtube.com/watch?v=VIDEO_ID
#   https://youtu.be/VIDEO_ID
#   https://youtube.com/watch?v=VIDEO_ID&otros_params=valor
YOUTUBE_URL_PATTERN = re.compile(
    r"(?:https?://)?(?:www\.)?(?:youtube\.com/watch\?v=|youtu\.be/)([a-zA-Z0-9_-]{11})"
)


def extract_video_id(url: str) -> str | None:
    """Extrae el video_id de una URL de YouTube. Devuelve None si no es válida."""
    match = YOUTUBE_URL_PATTERN.search(url)
    return match.group(1) if match else None


def create_job(job_id: str, video_id: str) -> None:
    """Crea el registro del job en DynamoDB con estado PENDING."""
    table = dynamodb.Table(DYNAMODB_TABLE)
    now = int(time.time())

    table.put_item(
        Item={
            "job_id": job_id,
            "status": "PENDING",
            "video_id": video_id,
            "created_at": now,
            # TTL: DynamoDB borrará este item automáticamente después de 24h
            "ttl": now + 86400,
        }
    )
    logger.info("Job creado en DynamoDB: job_id=%s video_id=%s", job_id, video_id)


def launch_fargate_task(job_id: str, video_id: str) -> str:
    """
    Lanza una tarea Fargate para procesar el job.
    Devuelve el ARN de la tarea lanzada.

    La tarea recibe job_id y video_id como variables de entorno,
    que es el mecanismo estándar para pasar parámetros a contenedores ECS.
    """
    response = ecs_client.run_task(
        cluster=ECS_CLUSTER,
        taskDefinition=ECS_TASK_DEFINITION,
        launchType="FARGATE",
        networkConfiguration={
            # Fargate necesita configuración de red explícita.
            # assignPublicIp=ENABLED es necesario para que el contenedor
            # pueda hacer llamadas salientes a YouTube API y Bedrock
            # sin un NAT Gateway (que sería más caro).
            "awsvpcConfiguration": {
                "subnets": SUBNET_IDS,  # viene de variable de entorno
                "assignPublicIp": "ENABLED",
            }
        },
        overrides={
            "containerOverrides": [
                {
                    "name": "processor",
                    "environment": [
                        {"name": "JOB_ID", "value": job_id},
                        {"name": "VIDEO_ID", "value": video_id},
                    ],
                }
            ]
        },
    )

    if response["failures"]:
        failure = response["failures"][0]
        raise RuntimeError(f"Fargate no pudo lanzar la tarea: {failure['reason']}")

    task_arn = response["tasks"][0]["taskArn"]
    logger.info("Tarea Fargate lanzada: task_arn=%s job_id=%s", task_arn, job_id)
    return task_arn


def _response(status_code: int, body: dict) -> dict:
    """Construye la respuesta HTTP con headers CORS."""
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps(body),
    }


def handler(event: dict, context) -> dict:
    """
    Punto de entrada del Lambda.
    API Gateway v2 con payload_format_version 2.0 pasa el body
    directamente como string en event["body"].
    """
    logger.info("Evento recibido: %s", json.dumps(event))

    # Parsear el body
    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return _response(400, {"error": "El body debe ser JSON válido"})

    url = body.get("url", "").strip()
    if not url:
        return _response(400, {"error": "El campo 'url' es requerido"})

    # Validar y extraer video_id
    video_id = extract_video_id(url)
    if not video_id:
        return _response(
            400,
            {
                "error": "URL de YouTube no válida. Formatos aceptados: youtube.com/watch?v=ID o youtu.be/ID"
            },
        )

    # Crear job y lanzar tarea
    job_id = str(uuid.uuid4())

    try:
        create_job(job_id, video_id)
        launch_fargate_task(job_id, video_id)
    except ClientError as e:
        logger.error("Error AWS: %s", e)
        return _response(500, {"error": "Error interno al crear el job"})
    except RuntimeError as e:
        logger.error("Error al lanzar Fargate: %s", e)
        return _response(500, {"error": "Error interno al procesar la solicitud"})

    return _response(202, {"job_id": job_id, "status": "PENDING"})
