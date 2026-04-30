from typing import Optional
from supabase import Client
from app.models.visit import VisitCreate, VisitUpdate

TABLE = "visits"


class VisitRepository:
    def __init__(self, db: Client):
        self.db = db

    def get_all(self, limit: int = 50, offset: int = 0) -> list[dict]:
        res = self.db.table(TABLE).select("*").range(offset, offset + limit - 1).execute()
        return res.data

    def get_by_id(self, visit_id: str) -> Optional[dict]:
        res = self.db.table(TABLE).select("*").eq("id", visit_id).single().execute()
        return res.data

    def get_by_bia_code(self, bia_code: str) -> list[dict]:
        res = self.db.table(TABLE).select("*").eq("bia_code", bia_code).execute()
        return res.data

    def create(self, payload: VisitCreate) -> dict:
        res = self.db.table(TABLE).insert(payload.model_dump()).execute()
        return res.data[0]

    def update(self, visit_id: str, payload: VisitUpdate) -> dict:
        data = {k: v for k, v in payload.model_dump().items() if v is not None}
        res = self.db.table(TABLE).update(data).eq("id", visit_id).execute()
        return res.data[0]

    def delete(self, visit_id: str) -> bool:
        res = self.db.table(TABLE).delete().eq("id", visit_id).execute()
        return len(res.data) > 0
