import pytest
from unittest.mock import MagicMock
from fastapi import HTTPException
from app.services.cost_service import CostService
from app.models.cost import CostCreate, CostUpdate

SAMPLE = {
    "id": 1001,
    "visit_id": "uuid-001",
    "service_cost": 450000.0,
    "material_cost": 120000.0,
    "total_cost": 570000.0,
    "status": "accepted",
    "contractor_id": "GMAS",
}


def make_service(found=True):
    repo = MagicMock()
    repo.get_all.return_value = [SAMPLE]
    repo.get_by_id.return_value = SAMPLE if found else None
    repo.get_by_visit_id.return_value = [SAMPLE]
    repo.create.return_value = SAMPLE
    repo.update.return_value = {**SAMPLE, "status": "rejected"}
    repo.delete.return_value = True
    return CostService(repo)


class TestListCosts:
    def test_returns_list(self):
        service = make_service()
        result = service.list(limit=50, offset=0)
        assert isinstance(result, list)

    def test_filters_by_visit_id(self):
        service = make_service()
        service.list(limit=50, offset=0, visit_id="uuid-001")
        service.repo.get_by_visit_id.assert_called_once_with("uuid-001")

    def test_no_filter_calls_get_all(self):
        service = make_service()
        service.list(limit=50, offset=0)
        service.repo.get_all.assert_called_once()


class TestGetCost:
    def test_returns_record(self):
        service = make_service()
        result = service.get(1001)
        assert result["id"] == 1001

    def test_raises_404(self):
        service = make_service(found=False)
        with pytest.raises(HTTPException) as exc:
            service.get(9999)
        assert exc.value.status_code == 404


class TestCreateCost:
    def test_creates_and_returns(self):
        service = make_service()
        payload = CostCreate(id=1001, visit_id="uuid-001", service_cost=450000.0)
        result = service.create(payload)
        assert result["id"] == 1001


class TestUpdateCost:
    def test_updates_status(self):
        service = make_service()
        result = service.update(1001, CostUpdate(status="rejected"))
        assert result["status"] == "rejected"

    def test_raises_404(self):
        service = make_service(found=False)
        with pytest.raises(HTTPException) as exc:
            service.update(9999, CostUpdate())
        assert exc.value.status_code == 404


class TestDeleteCost:
    def test_returns_message(self):
        service = make_service()
        result = service.delete(1001)
        assert "eliminado" in result["message"]

    def test_raises_404(self):
        service = make_service(found=False)
        with pytest.raises(HTTPException) as exc:
            service.delete(9999)
        assert exc.value.status_code == 404
