"""
Fargate processor — Versión Final con Google Gemini 1.5 Flash.

Flujo:
  1. Obtiene secretos (YouTube, Supadata, Gemini) de AWS Secrets Manager.
  2. Obtiene metadatos del vídeo (YouTube API).
  3. Obtiene transcripción (Supadata API).
  4. Genera resumen estructurado (Google Gemini 1.5 Flash).
  5. Persiste en S3 y actualiza estado en DynamoDB.
"""

import json
import logging
import os
import re
import sys
import time

import boto3
import google.generativeai as genai
import requests
from googleapiclient.discovery import build

# Configuración de Logging Profesional
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger(__name__)

# =============================================================================
# Variables de Entorno (Inyectadas por Terraform)
# =============================================================================
JOB_ID = os.environ.get("JOB_ID")
VIDEO_ID = os.environ.get("VIDEO_ID")
DYNAMODB_TABLE = os.environ.get("DYNAMODB_TABLE")
RESULTS_BUCKET = os.environ.get("RESULTS_BUCKET")
AWS_REGION = os.environ.get("AWS_REGION", "eu-west-1")

# Nombres de los Secretos
YOUTUBE_SECRET_NAME = os.environ.get("YOUTUBE_SECRET_NAME", "/app/youtube-api-key")
SUPADATA_SECRET_NAME = os.environ.get("SUPADATA_SECRET_NAME", "/app/supadata-api-key")
GEMINI_SECRET_NAME = os.environ.get("GEMINI_SECRET_NAME", "/app/gemini-api-key")
GEMINI_MODEL_ID = os.environ.get("GEMINI_MODEL_ID", "gemini-1.5-flash")

# =============================================================================
# Clientes AWS
# =============================================================================
dynamodb = boto3.resource("dynamodb", region_name=AWS_REGION)
s3_client = boto3.client("s3", region_name=AWS_REGION)
secrets_client = boto3.client("secretsmanager", region_name=AWS_REGION)

# =============================================================================
# Funciones de Soporte (Helpers)
# =============================================================================


def get_secret(secret_name: str) -> str:
    """Recupera una API Key desde AWS Secrets Manager."""
    try:
        response = secrets_client.get_secret_value(SecretId=secret_name)
        secret_dict = json.loads(response["SecretString"])
        return secret_dict["api_key"]
    except Exception as e:
        logger.error("Error crítico obteniendo secreto %s: %s", secret_name, str(e))
        raise


def update_job_status(status: str, **kwargs) -> None:
    """Actualiza el estado del job en la tabla DynamoDB."""
    table = dynamodb.Table(DYNAMODB_TABLE)
    update_expr = "SET #s = :status, updated_at = :ts"
    expr_names = {"#s": "status"}
    expr_values = {":status": status, ":ts": int(time.time())}

    for key, value in kwargs.items():
        update_expr += f", {key} = :{key}"
        expr_values[f":{key}"] = value

    table.update_item(
        Key={"job_id": JOB_ID},
        UpdateExpression=update_expr,
        ExpressionAttributeNames=expr_names,
        ExpressionAttributeValues=expr_values,
    )
    logger.info("Estado del Job %s actualizado a: %s", JOB_ID, status)


def get_video_metadata(video_id: str, api_key: str) -> dict:
    """Obtiene el título del vídeo usando la API oficial de YouTube."""
    youtube = build("youtube", "v3", developerKey=api_key)
    response = youtube.videos().list(part="snippet", id=video_id).execute()

    if not response.get("items"):
        raise ValueError(f"Vídeo {video_id} no encontrado.")

    return {"title": response["items"][0]["snippet"]["title"]}


def get_transcript_from_supadata(video_id: str, api_key: str) -> tuple[str, str]:
    """Obtiene la transcripción vía Supadata API."""
    url = f"https://api.supadata.ai/v1/youtube/transcript?url=https://www.youtube.com/watch?v={video_id}"
    headers = {"x-api-key": api_key}

    logger.info("Solicitando transcripción a Supadata...")
    response = requests.get(url, headers=headers, timeout=30)
    response.raise_for_status()

    data = response.json()
    return data.get("content", ""), data.get("lang", "es")


def generate_summary_gemini(transcript: str, language: str, api_key: str) -> dict:
    """Genera el resumen usando Gemini 2.5 Flash."""
    genai.configure(api_key=api_key)

    # Usamos el ID de la 2.5 que es la que tu cuenta tiene activa
    model_id = os.environ.get("GEMINI_MODEL_ID", "gemini-2.5-flash")
    model = genai.GenerativeModel(model_id)

    logger.info("Invocando el modelo de última generación: %s", model_id)

    instruction = (
        "Traduce y resume en ESPAÑOL."
        if not language.startswith("es")
        else "Resume en ESPAÑOL."
    )

    prompt = f"""
    {instruction}
    Analiza esta transcripción y responde con este JSON:
    {{
      "main_idea": "Idea principal",
      "key_points": ["punto 1", "punto 2", "punto 3"],
      "conclusion": "Mensaje final"
    }}
    Transcripción: {transcript[:15000]}
    """

    # En la 2.5, la respuesta es muy rápida
    response = model.generate_content(prompt)

    if not response.text:
        raise ValueError("La IA no devolvió texto.")

    # Extraemos el JSON con Regex por seguridad
    json_match = re.search(r"\{.*\}", response.text, re.DOTALL)
    if json_match:
        return json.loads(json_match.group())

    raise ValueError("No se encontró un JSON válido en la respuesta de la IA.")


# =============================================================================
# Lógica Principal (Main)
# =============================================================================


def main():
    logger.info("Iniciando procesamiento del Job: %s", JOB_ID)
    try:
        # 0. Marcar inicio
        update_job_status("PROCESSING")

        # 1. Recuperar todas las API Keys
        yt_key = get_secret(YOUTUBE_SECRET_NAME)
        sd_key = get_secret(SUPADATA_SECRET_NAME)
        gm_key = get_secret(GEMINI_SECRET_NAME)

        # 2. Obtener Datos del Vídeo
        metadata = get_video_metadata(VIDEO_ID, yt_key)
        transcript, lang = get_transcript_from_supadata(VIDEO_ID, sd_key)

        # 3. Generar Resumen con Gemini
        summary = generate_summary_gemini(transcript, lang, gm_key)

        # 4. Persistir Resultado en S3
        s3_key = f"results/{JOB_ID}.json"
        result_data = {
            "job_id": JOB_ID,
            "video_title": metadata["title"],
            "summary": summary,
            "processed_at": int(time.time()),
        }

        s3_client.put_object(
            Bucket=RESULTS_BUCKET,
            Key=s3_key,
            Body=json.dumps(result_data, ensure_ascii=False),
            ContentType="application/json",
        )

        # 5. Éxito Total
        update_job_status("DONE", result_s3_key=s3_key)
        logger.info("¡Procesamiento completado con éxito para el Job %s!", JOB_ID)

    except Exception as e:
        logger.error("Fallo en el procesamiento del Job %s: %s", JOB_ID, str(e))
        update_job_status("ERROR", error_message=str(e))
        sys.exit(1)


if __name__ == "__main__":
    main()
