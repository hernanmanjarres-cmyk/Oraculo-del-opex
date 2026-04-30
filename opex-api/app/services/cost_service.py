from typing import Optional
from fastapi import HTTPException
from app.repositories.cost_repo import CostRepository
from app.models.cost import CostCreate, CostUpdate


class CostService:
    def __init__(self, repo: CostRepository):
        self.repo = repo

    def list(self, limit: int, offset: int, visit_id: Optional[str] = None) -> list[dict]:
        if visit_id:
            return self.repo.get_by_visit_id(visit_id)
        return self.repo.get_all(limit=limit, offset=offset)

    def get(self, cost_id: int) -> dict:
        record = self.repo.get_by_id(cost_id)
        if not record:
            raise HTTPException(status_code=404, detail=f"Costo '{cost_id}' no encontrado")
        return record

    def create(self, payload: CostCreate) -> dict:
        return self.repo.create(payload)

    def update(self, cost_id: int, payload: CostUpdate) -> dict:
        self.get(cost_id)
        return self.repo.update(cost_id, payload)

    def delete(self, cost_id: int) -> dict:
        self.get(cost_id)
        self.repo.delete(cost_id)
        return {"message": f"Costo '{cost_id}' eliminado correctamente"}
