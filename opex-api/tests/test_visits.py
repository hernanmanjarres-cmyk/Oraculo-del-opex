import pytest
from unittest.mock import MagicMock
from fastapi import HTTPException
from app.services.visit_service import VisitService
from app.models.visit import VisitCreate, VisitUpdate

SAMPLE = {
    "id": "uuid-001",
    "bia_code": "BIA-001",
    "service_type_id": "INST",
    "service_name": "Instalación",
    "electrician_status_id": "CLOSURE_SUCCESSFUL",
    "contractor_name": "GMAS",
    "city": "Bogotá",
}


def make_service(found=True):
    repo = MagicMock()
    repo.get_all.return_value = [SAMPLE]
    repo.get_by_id.return_value = SAMPLE if found else None
    repo.get_by_bia_code.return_value = [SAMPLE]
    repo.create.return_value = SAMPLE
    repo.update.return_value = {**SAMPLE, "city": "Cali"}
    repo.delete.return_value = True
    return VisitService(repo)


class TestListVisits:
    def test_returns_list(self):
        service = make_service()
        result = service.list(limit=50, offset=0)
        assert isinstance(result, list)

    def test_filters_by_bia_code(self):
        service = make_service()
        service.list(limit=50, offset=0, bia_code="BIA-001")
        service.repo.get_by_bia_code.assert_called_once_with("BIA-001")

    def test_no_filter_calls_get_all(self):
        service = make_service()
        service.list(limit=50, offset=0)
        service.repo.get_all.assert_called_once()


class TestGetVisit:
    def test_returns_record(self):
        service = make_service()
        result = service.get("uuid-001")
        assert result["id"] == "uuid-001"

    def test_raises_404(self):
        service = make_service(found=False)
        with pytest.raises(HTTPException) as exc:
            service.get("uuid-999")
        assert exc.value.status_code == 404


class TestCreateVisit:
    def test_creates_and_returns(self):
        service = make_service()
        payload = VisitCreate(id="uuid-001", bia_code="BIA-001")
        result = service.create(payload)
        assert result["id"] == "uuid-001"


class TestUpdateVisit:
    def test_updates_city(self):
        service = make_service()
        result = service.update("uuid-001", VisitUpdate(city="Cali"))
        assert result["city"] == "Cali"

    def test_raises_404_when_not_found(self):
        service = make_service(found=False)
        with pytest.raises(HTTPException) as exc:
            service.update("uuid-999", VisitUpdate())
        assert exc.value.status_code == 404


class TestDeleteVisit:
    def test_returns_message(self):
        service = make_service()
        result = service.delete("uuid-001")
        assert "eliminada" in result["message"]

    def test_raises_404(self):
        service = make_service(found=False)
        with pytest.raises(HTTPException) as exc:
            service.delete("uuid-999")
        assert exc.value.status_code == 404
