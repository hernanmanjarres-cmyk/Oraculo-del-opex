from fastapi import APIRouter, Depends, Query
from app.database import get_client
from app.repositories.frontier_repo import FrontierRepository
from app.services.frontier_service import FrontierService
from app.models.frontier import FrontierCreate, FrontierUpdate, FrontierResponse

router = APIRouter(prefix="/fronteras", tags=["Fronteras"])


def get_service() -> FrontierService:
    return FrontierService(FrontierRepository(get_client()))


@router.get("/", response_model=list[FrontierResponse])
def list_fronteras(
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    service: FrontierService = Depends(get_service),
):
    return service.list(limit=limit, offset=offset)


@router.get("/{bia_code}", response_model=FrontierResponse)
def get_frontera(bia_code: str, service: FrontierService = Depends(get_service)):
    return service.get(bia_code)


@router.post("/", response_model=FrontierResponse, status_code=201)
def create_frontera(payload: FrontierCreate, service: FrontierService = Depends(get_service)):
    return service.create(payload)


@router.put("/{bia_code}", response_model=FrontierResponse)
def update_frontera(
    bia_code: str, payload: FrontierUpdate, service: FrontierService = Depends(get_service)
):
    return service.update(bia_code, payload)


@router.delete("/{bia_code}")
def delete_frontera(bia_code: str, service: FrontierService = Depends(get_service)):
    return service.delete(bia_code)
