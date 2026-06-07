from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    supabase_url: str
    supabase_service_role_key: str = ""
    supabase_access_token: str = ""           # Management API (DDL/migraciones)
    supabase_project_ref: str = ""            # ref del proyecto Supabase
    matix_api_key: str = ""
    matix_env: str = "dev"

    # Agente local de la PC (Capa 6 · 6.0a). Secreto compartido DISTINTO de
    # matix_api_key: el agente lo presenta en el header X-Agente-PC-Token al
    # abrir el WebSocket. Si está vacío, el endpoint del agente rechaza toda
    # conexión (no hay agente sin secreto). En Railway va como AGENTE_PC_TOKEN.
    agente_pc_token: str = ""

    # LLM del CHAT — intercambiable por env (default OpenAI). Toda la
    # lógica de proveedor vive en `app/matix/llm.py`; ningún otro módulo
    # sabe del proveedor.
    #   MATIX_LLM_PROVIDER: "openai" | "anthropic" (default "openai").
    #   MATIX_LLM_MODEL: id del modelo del proveedor elegido (default el
    #     gpt-4o-mini actual). Para Claude, p.ej. "claude-3-5-haiku-latest".
    matix_llm_provider: str = "openai"
    matix_llm_model: str = "gpt-4o-mini"
    # Keys (solo de env; NUNCA en el repo). Whisper, TTS y los embeddings
    # del RAG SIEMPRE usan OpenAI, sea cual sea el proveedor del chat.
    openai_api_key: str = ""
    anthropic_api_key: str = ""
    # ElevenLabs (TTS premium, OPCIONAL). Si hay key, es el primer eslabón de la
    # cadena de voz (ElevenLabs → OpenAI → voz del dispositivo). Si está vacío,
    # se salta limpio a OpenAI. `elevenlabs_voice_id` elige la voz.
    elevenlabs_api_key: str = ""
    elevenlabs_voice_id: str = ""
    # CORS: lista separada por coma. Vacío = deny-all browser (la app
    # Android no es navegador y no la necesita). Se pone solo si en
    # el futuro hay un cliente web.
    matix_cors_origins: str = ""

    # OAuth Google (Capa 4 Paso 1). Si vacíos, los endpoints de
    # /google/oauth devuelven 503 con mensaje claro — la app sabe que
    # la integración no está habilitada y oculta la UI de conexión.
    google_client_id: str = ""
    google_client_secret: str = ""
    google_redirect_uri: str = ""

    # Push (FCM · Push Capa 1). El JSON COMPLETO del service account de
    # Firebase (Project settings → Service accounts → Generate new private
    # key), pegado tal cual como variable de entorno en Railway. Si está
    # vacío, los endpoints de /push devuelven 503 con mensaje claro.
    firebase_service_account_json: str = ""

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
