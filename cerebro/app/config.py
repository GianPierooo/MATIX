from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    supabase_url: str
    supabase_service_role_key: str = ""
    supabase_access_token: str = ""           # Management API (DDL/migraciones)
    supabase_project_ref: str = ""            # ref del proyecto Supabase
    matix_api_key: str = ""
    matix_env: str = "dev"
    # LLM provider (Capa 2). Decisión: OpenAI como único proveedor.
    openai_api_key: str = ""
    # CORS: lista separada por coma. Vacío = deny-all browser (la app
    # Android no es navegador y no la necesita). Se pone solo si en
    # el futuro hay un cliente web.
    matix_cors_origins: str = ""

    @property
    def cors_origins_list(self) -> list[str]:
        return [
            o.strip()
            for o in self.matix_cors_origins.split(",")
            if o.strip()
        ]

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )


settings = Settings()
