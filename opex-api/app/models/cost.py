from pydantic import BaseModel
from typing import Optional
from datetime import datetime


class CostBase(BaseModel):
    visit_id: Optional[str] = None
    service_cost: Optional[float] = None
    material_cost: Optional[float] = None
    transport_cost: Optional[float] = None
    other_cost: Optional[float] = None
    status: Optional[str] = None
    contractor_id: Optional[str] = None
    is_bia: Optional[bool] = None
    comments: Optional[str] = None


class CostCreate(CostBase):
    id: int


class CostUpdate(CostBase):
    pass


class CostResponse(CostBase):
    id: int
    total_cost: Optional[float] = None
    ingested_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None

    class Config:
        from_attributes = True
