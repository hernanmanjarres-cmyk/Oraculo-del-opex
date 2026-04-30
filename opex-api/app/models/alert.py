from pydantic import BaseModel
from typing import Optional
from datetime import datetime


class AlertBase(BaseModel):
    bia_code: Optional[str] = None
    alert_type: Optional[str] = None
    estado: Optional[str] = None
    valor_detectado: Optional[float] = None
    descripcion: Optional[str] = None


class AlertCreate(AlertBase):
    pass


class AlertUpdate(BaseModel):
    estado: Optional[str] = None
    descripcion: Optional[str] = None


class AlertResponse(AlertBase):
    id: int
    created_at: Optional[datetime] = None

    class Config:
        from_attributes = True
