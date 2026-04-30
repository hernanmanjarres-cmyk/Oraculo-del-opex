from fastapi import APIRouter, Depends, Query
from typing import Optional
from app.database import get_client
from app.repositories.cost_repo import CostRepository
from app.services.cost_service import CostService
from app.models.cost import CostCreate, CostUpdate, CostResponse

router = APIRouter(prefix="/costs", tags=["Costs"])


def get_service() -> CostService:
    return CostService(CostRepository(get_client()))


@router.get("/", response_model=list[CostResponse])
def list_costs(
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    visit_id: Optional[str] = Query(None),
    service: CostService = Depends(get_service),
):
    return service.list(limit=limit, offset=offset, visit_id=visit_id)


@router.get("/{cost_id}", response_model=CostResponse)
def get_cost(cost_id: int, service: CostService = Depends(get_service)):
    return service.get(cost_id)


@router.post("/", response_model=CostResponse, status_code=201)
def create_cost(payload: CostCreate, service: CostService = Depends(get_service)):
    return service.create(payload)


@router.put("/{cost_id}", response_model=CostResponse)
def update_cost(
    cost_id: int, payload: CostUpdate, service: CostService = Depends(get_service)
):
    return service.update(cost_id, payload)


@router.delete("/{cost_id}")
def delete_cost(cost_id: int, service: CostService = Depends(get_service)):
    return service.delete(cost_id)
