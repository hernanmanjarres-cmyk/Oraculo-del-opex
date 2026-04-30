from fastapi import APIRouter, Depends, Query
from typing import Optional
from app.database import get_client
from app.repositories.visit_repo import VisitRepository
from app.services.visit_service import VisitService
from app.models.visit import VisitCreate, VisitUpdate, VisitResponse

router = APIRouter(prefix="/visits", tags=["Visits"])


def get_service() -> VisitService:
    return VisitService(VisitRepository(get_client()))


@router.get("/", response_model=list[VisitResponse])
def list_visits(
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    bia_code: Optional[str] = Query(None),
    service: VisitService = Depends(get_service),
):
    return service.list(limit=limit, offset=offset, bia_code=bia_code)


@router.get("/{visit_id}", response_model=VisitResponse)
def get_visit(visit_id: str, service: VisitService = Depends(get_service)):
    return service.get(visit_id)


@router.post("/", response_model=VisitResponse, status_code=201)
def create_visit(payload: VisitCreate, service: VisitService = Depends(get_service)):
    return service.create(payload)


@router.put("/{visit_id}", response_model=VisitResponse)
def update_visit(
    visit_id: str, payload: VisitUpdate, service: VisitService = Depends(get_service)
):
    return service.update(visit_id, payload)


@router.delete("/{visit_id}")
def delete_visit(visit_id: str, service: VisitService = Depends(get_service)):
    return service.delete(visit_id)
