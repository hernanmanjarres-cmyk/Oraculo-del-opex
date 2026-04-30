from pydantic import BaseModel
from typing import Optional
from datetime import datetime


class VisitBase(BaseModel):
    bia_code: Optional[str] = None
    service_type_id: Optional[str] = None
    service_name: Optional[str] = None
    electrician_status_id: Optional[str] = None
    status_label: Optional[str] = None
    contractor_name: Optional[str] = None
    grid_operator: Optional[str] = None
    city: Optional[str] = None
    department: Optional[str] = None
    visit_date: Optional[datetime] = None
    is_bia: Optional[bool] = None


class VisitCreate(VisitBase):
    id: str


class VisitUpdate(VisitBase):
    pass


class VisitResponse(VisitBase):
    id: str
    ingested_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None

    class Config:
        from_attributes = True
