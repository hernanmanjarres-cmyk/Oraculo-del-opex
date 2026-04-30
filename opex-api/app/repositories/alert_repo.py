from typing import Optional
from supabase import Client
from app.models.alert import AlertCreate, AlertUpdate

TABLE = "opex_alerts"


class AlertRepository:
    def __init__(self, db: Client):
        self.db = db

    def get_all(self, limit: int = 50, offset: int = 0) -> list[dict]:
        res = self.db.table(TABLE).select("*").range(offset, offset + limit - 1).execute()
        return res.data

    def get_by_id(self, alert_id: int) -> Optional[dict]:
        res = self.db.table(TABLE).select("*").eq("id", alert_id).single().execute()
        return res.data

    def create(self, payload: AlertCreate) -> dict:
        res = self.db.table(TABLE).insert(payload.model_dump()).execute()
        return res.data[0]

    def update(self, alert_id: int, payload: AlertUpdate) -> dict:
        data = {k: v for k, v in payload.model_dump().items() if v is not None}
        res = self.db.table(TABLE).update(data).eq("id", alert_id).execute()
        return res.data[0]
