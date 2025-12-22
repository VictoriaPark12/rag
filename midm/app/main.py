"""FastAPI server for RAG with a local HF model (Mi:dm by default) and pgvector."""

import logging
import os
import sys
import time
import uuid

# Add current directory to Python path
sys.path.insert(0, os.path.dirname(__file__))

# Monorepo dev convenience:
# If langchain packages aren't installed in the current environment, fall back to local sources.
_REPO_ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
_LOCAL_LIB_PATHS = [
    os.path.join(_REPO_ROOT, "libs", "core"),  # langchain_core
    os.path.join(_REPO_ROOT, "libs", "partners", "huggingface"),  # langchain_huggingface
]
for _p in _LOCAL_LIB_PATHS:
    if os.path.isdir(_p) and _p not in sys.path:
        sys.path.insert(0, _p)

try:
    from api.routers import chat, rag, search  # type: ignore
    from core.rag_chain import create_rag_chain, init_llm  # type: ignore
    from core.vectorstore import init_vector_store  # type: ignore
    from service.chat_service import warmup_qlora_from_env  # type: ignore
    from dotenv import find_dotenv, load_dotenv  # type: ignore
    from fastapi import FastAPI  # type: ignore
    from fastapi.middleware.cors import CORSMiddleware  # type: ignore
    import uvicorn  # type: ignore
except (ModuleNotFoundError, ImportError) as e:  # pragma: no cover
    msg = (
        "필수 의존성이 설치되지 않아 `app/main.py`를 시작할 수 없습니다.\n\n"
        "의존성 설치:\n"
        "  pip install -r app/requirements.txt\n\n"
        f"원본 에러: {e}"
    )
    raise RuntimeError(msg) from e

# Load environment variables from root directory
env_path = os.path.join(os.path.dirname(__file__), "..", ".env")
# 1) Prefer repo-root .env (app/../.env)
load_dotenv(env_path, override=False)
# 2) Also load the closest .env from current working directory (helps when user runs from a different folder)
_cwd_env = find_dotenv(usecwd=True)
if _cwd_env:
    load_dotenv(_cwd_env, override=False)

app = FastAPI(title="RAG API Server", version="1.0.0")

# Basic structured logging to stdout
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)
logger = logging.getLogger("rag-api")


def _truncate(text: str, max_len: int = 160) -> str:
    """Truncate log text to keep logs readable."""
    if len(text) <= max_len:
        return text
    return text[: max_len - 3] + "..."


@app.middleware("http")
async def request_logging_middleware(request, call_next):
    """Log request/response with a correlation id."""
    request_id = request.headers.get("x-request-id") or uuid.uuid4().hex[:12]
    request.state.request_id = request_id
    start = time.perf_counter()

    logger.info(
        "[REQ] id=%s method=%s path=%s client=%s",
        request_id,
        request.method,
        request.url.path,
        getattr(request.client, "host", None),
    )

    try:
        response = await call_next(request)
    except Exception as e:  # pragma: no cover
        duration_ms = int((time.perf_counter() - start) * 1000)
        logger.exception(
            "[ERR] id=%s method=%s path=%s duration_ms=%s error=%s",
            request_id,
            request.method,
            request.url.path,
            duration_ms,
            str(e),
        )
        raise

    duration_ms = int((time.perf_counter() - start) * 1000)
    response.headers["x-request-id"] = request_id
    logger.info(
        "[RES] id=%s status=%s duration_ms=%s path=%s",
        request_id,
        response.status_code,
        duration_ms,
        request.url.path,
    )
    return response

# CORS 설정
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
async def startup_event():
    """Initialize vector store and RAG chain on startup."""
    try:
        print("Initializing vector store...")
        vector_store = await init_vector_store()
        print("[OK] Vector store initialized!")

        # Check LLM provider mode
        llm_provider = os.getenv("LLM_PROVIDER", "openai").lower()
        use_qlora = os.getenv("USE_QLORA", "0").lower() in {"1", "true", "yes"}
        qlora_base = os.getenv("QLORA_BASE_MODEL_PATH")

        logger.info(
            "[BOOT] env loaded llm_provider=%s use_qlora=%s qlora_base_set=%s env_path=%s cwd_env=%s",
            llm_provider,
            use_qlora,
            bool(qlora_base),
            env_path,
            _cwd_env or None,
        )

        # If OpenAI is selected, initialize OpenAI LLM (uses openai folder)
        if llm_provider == "openai":
            print("[OPENAI] Initializing OpenAI LLM...")
            # PYTHONPATH에 openai 폴더가 이미 추가되어 있음 (systemd service 설정 참조)
            # rag_chain.py의 init_llm()에서 openai 모듈을 import함

            llm = init_llm()
            rag_chain_instance = create_rag_chain(vector_store, llm)

            # Set dependencies for routers
            rag.set_dependencies(vector_store, rag_chain_instance)
            search.set_dependencies(vector_store)
            chat.set_dependencies(llm)

            print("✅ API server is ready! (OpenAI mode)")
        # If QLoRA mode is enabled, use QLoRA (deprecated, midm 모델 사용 안 함)
        elif use_qlora and qlora_base:
            print("[QLORA] Enabled: skipping HF LLM init + rag_chain creation")
            llm = None
            rag_chain_instance = None

            # Set dependencies for routers
            rag.set_dependencies(vector_store, rag_chain_instance)
            search.set_dependencies(vector_store)
            # In QLoRA mode, chat router uses chat_service directly.
            chat.set_dependencies(None)

            print("API server is ready! (QLoRA mode)")

            # Optional: warm up QLoRA model so first request doesn't pay load cost.
            # If model path is not available, continue without QLoRA.
            warmup_qlora_from_env()
        else:
            # Default: Initialize standard LLM (HuggingFace or Ollama)
            print("[STANDARD] Initializing standard LLM...")
            llm = init_llm()
            rag_chain_instance = create_rag_chain(vector_store, llm)

            # Set dependencies for routers
            rag.set_dependencies(vector_store, rag_chain_instance)
            search.set_dependencies(vector_store)
            chat.set_dependencies(llm)

            print("API server is ready! (Standard LLM mode)")

    except Exception as e:
        print(f"[ERROR] Startup error: {e}")
        import traceback

        traceback.print_exc()
        raise


# Include routers
app.include_router(rag.router)
app.include_router(search.router)
app.include_router(chat.router)


@app.get("/")
async def root():
    """Root endpoint."""
    return {
        "message": "RAG API Server",
        "version": "1.0.0",
        "endpoints": {
            "rag": "POST /rag - RAG (Retrieval + Generation)",
            "chat": "POST /chat - General chat (no retrieval)",
            "retrieve": "POST /retrieve - Retrieve similar documents",
            "add_document": "POST /documents - Add a document",
            "add_documents": "POST /documents/batch - Add multiple documents",
            "health": "GET /health - Health check",
        },
    }


@app.get("/health")
async def health():
    """Health check endpoint."""
    return {
        "status": "healthy",
        "vector_store": "initialized" if search.vector_store else "not initialized",
        "rag_chain": "initialized" if rag.rag_chain else "not initialized",
    }


if __name__ == "__main__":
    port = int(os.getenv("PORT", "8000"))
    uvicorn.run(app, host="0.0.0.0", port=port, reload=False)

