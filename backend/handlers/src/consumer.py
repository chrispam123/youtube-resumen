"""
Lambda handler: SQS Consumer — lanza Fargate desde la cola de jobs.

Trigger: SQS (event source mapping configurado en Terraform).
Flujo:
  1. Recibe lote de mensajes desde SQS
  2. Por cada mensaje, extrae job_id y video_id
  3. Lanza tarea Fargate con esos parámetros
  4. Si éxito → Lambda retorna OK → SQS borra el mensaje
  5. Si fallo → Lambda lanza excepción → SQS reintenta (hasta 3, luego DLQ)
"""

import json
import logging
import os

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ecs_client = boto3.client("ecs")

ECS_CLUSTER = os.environ["ECS_CLUSTER"]
ECS_TASK_DEFINITION = os.environ["ECS_TASK_DEFINITION"]
SUBNET_IDS = os.environ["SUBNET_IDS"].split(",")
SECURITY_GROUP_IDS = os.environ.get("SECURITY_GROUP_IDS", "").split(",")


def launch_fargate_task(job_id: str, video_id: str) -> str:
    """
    Lanza una tarea Fargate para procesar el job.
    Devuelve el ARN de la tarea lanzada.
    """
    response = ecs_client.run_task(
        cluster=ECS_CLUSTER,
        taskDefinition=ECS_TASK_DEFINITION,
        launchType="FARGATE",
        networkConfiguration={
            "awsvpcConfiguration": {
                "subnets": SUBNET_IDS,
                "assignPublicIp": "ENABLED",
                # Security group SIN inbound: la IP pública permite salida
                # barata (sin NAT Gateway) pero nadie puede entrar a la tarea.
                "securityGroups": [sg for sg in SECURITY_GROUP_IDS if sg],
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


def handler(event: dict, context) -> None:
    """
    Punto de entrada del Lambda consumer.
    AWS Lambda invoca esta función cuando hay mensajes en SQS.
    Si la función termina sin error, SQS borra los mensajes automáticamente.
    Si lanza excepción, los mensajes quedan visibles tras el visibility timeout.
    """
    logger.info("Evento SQS recibido: %s", json.dumps(event))

    for record in event.get("Records", []):
        try:
            body = json.loads(record["body"])
            job_id = body["job_id"]
            video_id = body["video_id"]
        except (KeyError, json.JSONDecodeError) as e:
            logger.error("Mensaje SQS malformado: %s", e)
            raise

        try:
            launch_fargate_task(job_id, video_id)
        except (ClientError, RuntimeError) as e:
            logger.error("Error al lanzar Fargate para job %s: %s", job_id, e)
            raise
