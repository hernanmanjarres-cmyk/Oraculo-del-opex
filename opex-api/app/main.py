from fastapi import FastAPI
from app.routers import health, fronteras, visits, costs, alerts

app = FastAPI(
    title="Oráculo del OPEX API",
    description="Microservicio REST para gestión de costos OPEX · BIA Energy",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
)

app.include_router(health.router)
app.include_router(fronteras.router, prefix="/api/v1")
app.include_router(visits.router, prefix="/api/v1")
app.include_router(costs.router, prefix="/api/v1")
app.include_router(alerts.router, prefix="/api/v1")
