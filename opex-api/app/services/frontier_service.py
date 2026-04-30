from fastapi import HTTPException
from app.repositories.frontier_repo import FrontierRepository
from app.models.frontier import FrontierCreate, FrontierUpdate


class FrontierService:
    def __init__(self, repo: FrontierRepository):
        self.repo = repo

    def list(self, limit: int, offset: int) -> list[dict]:
        return self.repo.get_all(limit=limit, offset=offset)

    def get(self, bia_code: str) -> dict:
        record = self.repo.get_by_id(bia_code)
        if not record:
            raise HTTPException(status_code=404, detail=f"Frontera '{bia_code}' no encontrada")
        return record

    def create(self, payload: FrontierCreate) -> dict:
        return self.repo.create(payload)

    def update(self, bia_code: str, payload: FrontierUpdate) -> dict:
        self.get(bia_code)
        return self.repo.update(bia_code, payload)

    def delete(self, bia_code: str) -> dict:
        self.get(bia_code)
        self.repo.delete(bia_code)
        return {"message": f"Frontera '{bia_code}' eliminada correctamente"}
