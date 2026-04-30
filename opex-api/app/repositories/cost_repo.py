from typing import Optional
from supabase import Client
from app.models.cost import CostCreate, CostUpdate

TABLE = "opex_costs"


class CostRepository:
    def __init__(self, db: Client):
        self.db = db

    def get_all(self, limit: int = 50, offset: int = 0) -> list[dict]:
        res = self.db.table(TABLE).select("*").range(offset, offset + limit - 1).execute()
        return res.data

    def get_by_id(self, cost_id: int) -> Optional[dict]:
        res = self.db.table(TABLE).select("*").eq("id", cost_id).single().execute()
        return res.data

    def get_by_visit_id(self, visit_id: str) -> list[dict]:
        res = self.db.table(TABLE).select("*").eq("visit_id", visit_id).execute()
        return res.data

    def create(self, payload: CostCreate) -> dict:
        res = self.db.table(TABLE).insert(payload.model_dump()).execute()
        return res.data[0]

    def update(self, cost_id: int, payload: CostUpdate) -> dict:
        data = {k: v for k, v in payload.model_dump().items() if v is not None}
        res = self.db.table(TABLE).update(data).eq("id", cost_id).execute()
        return res.data[0]

    def delete(self, cost_id: int) -> bool:
        res = self.db.table(TABLE).delete().eq("id", cost_id).execute()
        return len(res.data) > 0
