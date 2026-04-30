from fastapi import APIRouter, Depends, Query
from app.database import get_client
from app.repositories.alert_repo import AlertRepository
from app.services.alert_service import AlertService
from app.models.alert import AlertCreate, AlertUpdate, AlertResponse

router = APIRouter(prefix="/alerts", tags=["Alerts"])


def get_service() -> AlertService:
    return AlertService(AlertRepository(get_client()))


@router.get("/", response_model=list[AlertResponse])
def list_alerts(
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    service: AlertService = Depends(get_service),
):
    return service.list(limit=limit, offset=offset)


@router.get("/{alert_id}", response_model=AlertResponse)
def get_alert(alert_id: int, service: AlertService = Depends(get_service)):
    return service.get(alert_id)


@router.post("/", response_model=AlertResponse, status_code=201)
def create_alert(payload: AlertCreate, service: AlertService = Depends(get_service)):
    return service.create(payload)


@router.put("/{alert_id}", response_model=AlertResponse)
def update_alert(
    alert_id: int, payload: AlertUpdate, service: AlertService = Depends(get_service)
):
    return service.update(alert_id, payload)
