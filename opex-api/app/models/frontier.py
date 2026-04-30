from pydantic import BaseModel
from typing import Optional
from datetime import datetime


class FrontierBase(BaseModel):
    frontier_title: Optional[str] = None
    current_phase: Optional[str] = None
    grid_operator: Optional[str] = None
    measurement_type: Optional[str] = None
    city: Optional[str] = None
    department: Optional[str] = None
    kam_assigned: Optional[str] = None
    company_name: Optional[str] = None
    market_type: Optional[str] = None


class FrontierCreate(FrontierBase):
    bia_code: str


class FrontierUpdate(FrontierBase):
    pass


class FrontierResponse(FrontierBase):
    bia_code: str
    ingested_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None

    class Config:
        from_attributes = True
