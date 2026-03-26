"""
Tests para el handler analyze.

Usamos moto para simular DynamoDB y ECS sin llamadas reales a AWS.
La variable de entorno AWS_DEFAULT_REGION es necesaria para moto.
"""

import json
import os
from unittest.mock import patch

import boto3
from moto import mock_aws

# Configura las variables de entorno antes de importar el handler
os.environ.update(
    {
        "DYNAMODB_TABLE": "test-jobs",
        "ECS_CLUSTER": "test-cluster",
        "ECS_TASK_DEFINITION": "test-processor",
        "FARGATE_ROLE_ARN": "arn:aws:iam::123456789012:role/test-role",
        "AWS_ACCOUNT_ID": "123456789012",
        "ENVIRONMENT": "test",
        "AWS_DEFAULT_REGION": "eu-west-1",
        "AWS_ACCESS_KEY_ID": "testing",
        "AWS_SECRET_ACCESS_KEY": "testing",
    }
)

from backend.handlers.src.analyze import extract_video_id, handler


class TestExtractVideoId:
    """Tests unitarios puros — no necesitan moto."""

    def test_url_estandar(self):
        url = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        assert extract_video_id(url) == "dQw4w9WgXcQ"

    def test_url_corta(self):
        url = "https://youtu.be/dQw4w9WgXcQ"
        assert extract_video_id(url) == "dQw4w9WgXcQ"

    def test_url_con_parametros_extra(self):
        url = "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=120s&list=PL123"
        assert extract_video_id(url) == "dQw4w9WgXcQ"

    def test_url_invalida(self):
        assert extract_video_id("https://vimeo.com/123456") is None

    def test_url_vacia(self):
        assert extract_video_id("") is None

    def test_url_sin_id(self):
        assert extract_video_id("https://www.youtube.com/") is None


@mock_aws
class TestHandler:
    """Tests de integración con servicios AWS simulados por moto."""

    def setup_method(self, method):
        """Crea los recursos AWS necesarios antes de cada test."""
        self.dynamodb = boto3.resource("dynamodb", region_name="eu-west-1")
        self.dynamodb.create_table(
            TableName="test-jobs",
            KeySchema=[{"AttributeName": "job_id", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "job_id", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST",
        )

    def _make_event(self, url: str) -> dict:
        return {"body": json.dumps({"url": url})}

    @patch("backend.handlers.src.analyze.launch_fargate_task")
    def test_url_valida_devuelve_202(self, mock_fargate):
        mock_fargate.return_value = "arn:aws:ecs:eu-west-1:123:task/abc"
        event = self._make_event("https://www.youtube.com/watch?v=dQw4w9WgXcQ")

        response = handler(event, None)

        assert response["statusCode"] == 202
        body = json.loads(response["body"])
        assert body["status"] == "PENDING"
        assert "job_id" in body

    def test_url_invalida_devuelve_400(self):
        event = self._make_event("https://vimeo.com/123456")
        response = handler(event, None)

        assert response["statusCode"] == 400
        body = json.loads(response["body"])
        assert "error" in body

    def test_sin_url_devuelve_400(self):
        event = {"body": json.dumps({})}
        response = handler(event, None)

        assert response["statusCode"] == 400

    def test_body_invalido_devuelve_400(self):
        event = {"body": "esto no es json"}
        response = handler(event, None)

        assert response["statusCode"] == 400
