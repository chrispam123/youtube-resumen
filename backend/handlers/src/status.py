"""
Lambda handler: GET /api/status/{job_id}

Responsabilidades:
  1. Leer el estado del job en DynamoDB
  2. Si está DONE, leer el resultado desde S3
  3. Devolver el estado al cliente para el polling

Este handler es invocado cada 3 segundos por el browser
hasta que el estado sea DONE o ERROR.
"""

import json
import logging
import os

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")
s3_client = boto3.client("s3")

DYNAMODB_TABLE = os.environ["DYNAMODB_TABLE"]
RESULTS_BUCKET = os.environ["RESULTS_BUCKET"]


def get_job(job_id: str) -> dict | None:
    """Lee el item del job desde DynamoDB. Devuelve None si no existe."""
    table = dynamodb.Table(DYNAMODB_TABLE)

    try:
        response = table.get_item(Key={"job_id": job_id})
        return response.get("Item")
    except ClientError as e:
        logger.error("Error leyendo DynamoDB: %s", e)
        raise


def get_result_from_s3(s3_key: str) -> dict:
    """Lee el resultado del resumen desde S3."""
    try:
        response = s3_client.get_object(Bucket=RESULTS_BUCKET, Key=s3_key)
        content = response["Body"].read().decode("utf-8")
        return json.loads(content)
    except ClientError as e:
        logger.error("Error leyendo S3: %s", e)
        raise


def _response(status_code: int, body: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps(body, ensure_ascii=False),
    }


def handler(event: dict, context) -> dict:
    logger.info("Evento recibido: %s", json.dumps(event))

    # API Gateway v2 pone los path parameters en pathParameters
    job_id = (event.get("pathParameters") or {}).get("job_id", "").strip()
    if not job_id:
        return _response(400, {"error": "job_id es requerido"})

    # Leer estado del job
    try:
        job = get_job(job_id)
    except ClientError:
        return _response(500, {"error": "Error interno al consultar el estado"})

    if not job:
        return _response(404, {"error": f"Job '{job_id}' no encontrado"})

    status = job["status"]
    logger.info("Estado del job %s: %s", job_id, status)

    # Job todavía en proceso — el browser seguirá haciendo polling
    if status in ("PENDING", "PROCESSING"):
        return _response(200, {"status": status})

    # Job completado — leer resultado desde S3
    if status == "DONE":
        s3_key = job.get("result_s3_key")
        if not s3_key:
            logger.error("Job DONE pero sin result_s3_key: %s", job_id)
            return _response(500, {"error": "Error interno: resultado no disponible"})

        try:
            result = get_result_from_s3(s3_key)
        except ClientError:
            return _response(500, {"error": "Error interno al leer el resultado"})

        return _response(200, {"status": "DONE", "summary": result["summary"]})

    # Job con error — devuelve el mensaje de error guardado por Fargate
    if status == "ERROR":
        return _response(
            200,
            {
                "status": "ERROR",
                "message": job.get(
                    "error_message", "Error desconocido durante el procesamiento"
                ),
            },
        )

    # Estado desconocido — no debería ocurrir pero lo manejamos
    logger.error("Estado desconocido para job %s: %s", job_id, status)
    return _response(500, {"error": "Estado del job desconocido"})
