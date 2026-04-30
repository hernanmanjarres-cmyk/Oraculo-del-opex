import pytest
from unittest.mock import MagicMock
from fastapi import HTTPException
from app.services.frontier_service import FrontierService
from app.models.frontier import FrontierCreate, FrontierUpdate

SAMPLE = {
    "bia_code": "BIA-001",
    "frontier_title": "Frontera Test",
    "current_phase": "Visita previa",
    "grid_operator": "ENEL CUNDINAMARCA",
    "city": "Bogotá",
    "department": "Cundinamarca",
}


def make_service(data=None, found=True):
    repo = MagicMock()
    repo.get_all.return_value = [SAMPLE] if data is None else data
    repo.get_by_id.return_value = SAMPLE if found else None
    repo.create.return_value = SAMPLE
    repo.update.return_value = {**SAMPLE, "city": "Medellín"}
    repo.delete.return_value = True
    return FrontierService(repo)


class TestListFronteras:
    def test_returns_list(self):
        service = make_service()
        result = service.list(limit=50, offset=0)
        assert isinstance(result, list)
        assert len(result) == 1

    def test_calls_repo_with_params(self):
        service = make_service()
        service.list(limit=10, offset=5)
        service.repo.get_all.assert_called_once_with(limit=10, offset=5)


class TestGetFrontera:
    def test_returns_record_when_found(self):
        service = make_service()
        result = service.get("BIA-001")
        assert result["bia_code"] == "BIA-001"

    def test_raises_404_when_not_found(self):
        service = make_service(found=False)
        with pytest.raises(HTTPException) as exc:
            service.get("BIA-999")
        assert exc.value.status_code == 404


class TestCreateFrontera:
    def test_creates_and_returns(self):
        service = make_service()
        payload = FrontierCreate(bia_code="BIA-001", city="Bogotá")
        result = service.create(payload)
        assert result["bia_code"] == "BIA-001"

    def test_calls_repo_create(self):
        service = make_service()
        payload = FrontierCreate(bia_code="BIA-001")
        service.create(payload)
        service.repo.create.assert_called_once()


class TestUpdateFrontera:
    def test_updates_and_returns(self):
        service = make_service()
        payload = FrontierUpdate(city="Medellín")
        result = service.update("BIA-001", payload)
        assert result["city"] == "Medellín"

    def test_raises_404_when_not_found(self):
        service = make_service(found=False)
        with pytest.raises(HTTPException) as exc:
            service.update("BIA-999", FrontierUpdate())
        assert exc.value.status_code == 404


class TestDeleteFrontera:
    def test_delete_returns_message(self):
        service = make_service()
        result = service.delete("BIA-001")
        assert "eliminada" in result["message"]

    def test_raises_404_when_not_found(self):
        service = make_service(found=False)
        with pytest.raises(HTTPException) as exc:
            service.delete("BIA-999")
        assert exc.value.status_code == 404
