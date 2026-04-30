from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)


def test_health_returns_200():
    res = client.get("/health")
    assert res.status_code == 200


def test_health_status_ok():
    res = client.get("/health")
    assert res.json()["status"] == "ok"


def test_health_has_timestamp():
    res = client.get("/health")
    assert "timestamp" in res.json()


def test_health_has_version():
    res = client.get("/health")
    assert "version" in res.json()


def test_health_service_name():
    res = client.get("/health")
    assert res.json()["service"] == "opex-api"
