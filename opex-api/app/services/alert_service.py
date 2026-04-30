from fastapi import HTTPException
from app.repositories.alert_repo import AlertRepository
from app.models.alert import AlertCreate, AlertUpdate


class AlertService:
    def __init__(self, repo: AlertRepository):
        self.repo = repo

    def list(self, limit: int, offset: int) -> list[dict]:
        return self.repo.get_all(limit=limit, offset=offset)

    def get(self, alert_id: int) -> dict:
        record = self.repo.get_by_id(alert_id)
        if not record:
            raise HTTPException(status_code=404, detail=f"Alerta '{alert_id}' no encontrada")
        return record

    def create(self, payload: AlertCreate) -> dict:
        return self.repo.create(payload)

    def update(self, alert_id: int, payload: AlertUpdate) -> dict:
        self.get(alert_id)
        return self.repo.update(alert_id, payload)
