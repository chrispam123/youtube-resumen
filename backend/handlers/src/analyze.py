# Lambda handler: POST /api/analyze
"""
Responsabilidades:
  1. Validar la URL de YouTube
  2. Extraer el video_id
  3. Crear el job en DynamoDB con estado PENDING
  4. Publicar mensaje en SQS para que el consumer lance Fargate
  5. Responder 202 con el job_id

Este handler debe ser rápido. No hace trabajo pesado.
La cola SQS permite reintentos automáticos si Fargate falla.
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

# Clientes AWS inicializados fuera del handler
dynamodb = boto3.resource("dynamodb")
sqs_client = boto3.client("sqs")

# Variables de entorno
DYNAMODB_TABLE = os.environ["DYNAMODB_TABLE"]
SQS_JOBS_QUEUE_URL = os.environ["SQS_JOBS_QUEUE_URL"]


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


def publish_to_sqs(job_id: str, video_id: str) -> None:
    """
    Publica un mensaje en SQS para encolar el procesamiento del job.

    SQS desacopla Lambda de Fargate: si Fargate falla,
    el mensaje reaparece (visibilty timeout) y se reintenta.
    Tras 3 fallos, el mensaje pasa a la DLQ para revisión manual.
    """
    message = json.dumps({"job_id": job_id, "video_id": video_id})

    response = sqs_client.send_message(
        QueueUrl=SQS_JOBS_QUEUE_URL,
        MessageBody=message,
    )

    message_id = response["MessageId"]
    logger.info("Mensaje publicado en SQS: message_id=%s job_id=%s", message_id, job_id)


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

    # Crear job y encolar mensaje en SQS
    job_id = str(uuid.uuid4())

    try:
        create_job(job_id, video_id)
        publish_to_sqs(job_id, video_id)
    except ClientError as e:
        logger.error("Error AWS: %s", e)
        return _response(500, {"error": "Error interno al crear el job"})

    return _response(202, {"job_id": job_id, "status": "PENDING"})
