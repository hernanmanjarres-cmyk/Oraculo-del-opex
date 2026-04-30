from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    supabase_url: str = ""
    supabase_key: str = ""
    api_version: str = "1.0.0"
    environment: str = "development"

    class Config:
        env_file = ".env"


settings = Settings()
