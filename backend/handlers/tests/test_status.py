"""Tests para el handler status."""

import json
import os

import boto3
from moto import mock_aws

os.environ.update(
    {
        "DYNAMODB_TABLE": "test-jobs",
        "RESULTS_BUCKET": "test-results",
        "AWS_DEFAULT_REGION": "eu-west-1",
        "AWS_ACCESS_KEY_ID": "testing",
        "AWS_SECRET_ACCESS_KEY": "testing",
    }
)

from backend.handlers.src.status import handler


@mock_aws
class TestStatusHandler:
    def setup_method(self, method):
        # DynamoDB
        self.dynamodb = boto3.resource("dynamodb", region_name="eu-west-1")
        self.table = self.dynamodb.create_table(
            TableName="test-jobs",
            KeySchema=[{"AttributeName": "job_id", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "job_id", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST",
        )
        # S3
        self.s3 = boto3.client("s3", region_name="eu-west-1")
        self.s3.create_bucket(
            Bucket="test-results",
            CreateBucketConfiguration={"LocationConstraint": "eu-west-1"},
        )

    def _make_event(self, job_id: str) -> dict:
        return {"pathParameters": {"job_id": job_id}}

    def test_job_no_encontrado_devuelve_404(self):
        response = handler(self._make_event("uuid-inexistente"), None)
        assert response["statusCode"] == 404

    def test_job_pending_devuelve_200_processing(self):
        self.table.put_item(Item={"job_id": "test-123", "status": "PENDING"})
        response = handler(self._make_event("test-123"), None)

        assert response["statusCode"] == 200
        body = json.loads(response["body"])
        assert body["status"] == "PENDING"

    def test_job_done_devuelve_resumen(self):
        # Escribe el resultado en S3
        result = {
            "summary": {
                "main_idea": "Test idea principal",
                "key_points": ["punto 1", "punto 2"],
                "conclusion": "Test conclusión",
            }
        }
        self.s3.put_object(
            Bucket="test-results",
            Key="results/test-456.json",
            Body=json.dumps(result),
        )
        # Crea el job en DynamoDB con estado DONE
        self.table.put_item(
            Item={
                "job_id": "test-456",
                "status": "DONE",
                "result_s3_key": "results/test-456.json",
            }
        )

        response = handler(self._make_event("test-456"), None)

        assert response["statusCode"] == 200
        body = json.loads(response["body"])
        assert body["status"] == "DONE"
        assert "summary" in body
        assert body["summary"]["main_idea"] == "Test idea principal"

    def test_job_error_devuelve_mensaje(self):
        self.table.put_item(
            Item={
                "job_id": "test-789",
                "status": "ERROR",
                "error_message": "Transcripción no disponible para este vídeo",
            }
        )

        response = handler(self._make_event("test-789"), None)

        assert response["statusCode"] == 200
        body = json.loads(response["body"])
        assert body["status"] == "ERROR"
        assert "message" in body

    def test_sin_job_id_devuelve_400(self):
        response = handler({"pathParameters": {}}, None)
        assert response["statusCode"] == 400
