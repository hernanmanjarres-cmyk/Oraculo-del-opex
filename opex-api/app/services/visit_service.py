from typing import Optional
from fastapi import HTTPException
from app.repositories.visit_repo import VisitRepository
from app.models.visit import VisitCreate, VisitUpdate


class VisitService:
    def __init__(self, repo: VisitRepository):
        self.repo = repo

    def list(self, limit: int, offset: int, bia_code: Optional[str] = None) -> list[dict]:
        if bia_code:
            return self.repo.get_by_bia_code(bia_code)
        return self.repo.get_all(limit=limit, offset=offset)

    def get(self, visit_id: str) -> dict:
        record = self.repo.get_by_id(visit_id)
        if not record:
            raise HTTPException(status_code=404, detail=f"Visita '{visit_id}' no encontrada")
        return record

    def create(self, payload: VisitCreate) -> dict:
        return self.repo.create(payload)

    def update(self, visit_id: str, payload: VisitUpdate) -> dict:
        self.get(visit_id)
        return self.repo.update(visit_id, payload)

    def delete(self, visit_id: str) -> dict:
        self.get(visit_id)
        self.repo.delete(visit_id)
        return {"message": f"Visita '{visit_id}' eliminada correctamente"}
