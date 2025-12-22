"""RAG chain initialization with a local Hugging Face chat model (Mi:dm by default) or Ollama."""

import os
from typing import Any, List, Optional, Union

from langchain_core.documents import Document
from langchain_core.output_parsers import StrOutputParser
from langchain_core.prompts import PromptTemplate
from langchain_core.runnables import Runnable, RunnablePassthrough
from langchain_huggingface import HuggingFacePipeline
from langchain_postgres import PGVector
try:
    import torch
except ModuleNotFoundError:  # pragma: no cover
    torch = None  # type: ignore[assignment]

try:
    from transformers import (
        AutoModelForCausalLM,
        AutoTokenizer,
        BitsAndBytesConfig,
        pipeline,
    )
except ModuleNotFoundError:  # pragma: no cover
    AutoModelForCausalLM = None  # type: ignore[assignment]
    AutoTokenizer = None  # type: ignore[assignment]
    BitsAndBytesConfig = None  # type: ignore[assignment]
    pipeline = None  # type: ignore[assignment]

_DEFAULT_LOCAL_MODEL_DIR = os.path.join("app", "model", "midm")


def _resolve_local_model_path(local_model_dir: Optional[str]) -> str:
    """Resolve a local model directory to an absolute path.

    Args:
        local_model_dir: Optional directory path from env var. Can be absolute or relative.

    Returns:
        Absolute normalized path to the model directory.
    """
    if local_model_dir:
        if os.path.isabs(local_model_dir):
            model_path = local_model_dir
        else:
            # 상대 경로인 경우 repo 루트 기준으로 변환
            root_dir = os.path.dirname(os.path.dirname(os.path.dirname(__file__)))
            model_path = os.path.join(root_dir, local_model_dir.lstrip("./"))
    else:
        # 기본값: app/model/midm (repo 루트 기준)
        root_dir = os.path.dirname(os.path.dirname(os.path.dirname(__file__)))
        model_path = os.path.join(root_dir, _DEFAULT_LOCAL_MODEL_DIR)

    return os.path.normpath(os.path.abspath(model_path))


def _build_rag_prompt() -> PromptTemplate:
    """Build a model-agnostic RAG prompt template.

    Mi:dm uses a chat template via `tokenizer.apply_chat_template(...)` in its docs,
    but we keep this prompt string-based so it works with the HF text-generation pipeline.
    """
    template = """[SYSTEM]
당신은 한국어로 답변하는 AI 어시스턴트입니다.
아래 '참고 정보'에 있는 내용만 사용해서 답변하세요.
참고 정보에 없는 내용은 "정보가 없습니다"라고 답변하세요.
답변은 간결하고 명확하게 작성하세요.

[HISTORY]
{history}

[CONTEXT]
{context}

[USER]
{question}

[ASSISTANT]
"""
    return PromptTemplate.from_template(template)


def init_llm() -> Union[HuggingFacePipeline, Any]:
    """Initialize LLM based on LLM_PROVIDER environment variable.

    Supports:
    - "openai": OpenAI API (requires OPENAI_API_KEY, uses openai folder)
    - "ollama": Fast local inference with Ollama
    - "midm" or other: HuggingFace transformers (slow on CPU)

    Returns:
        LLM instance (ChatOpenAI, HuggingFacePipeline, or ChatOllama).
    """
    llm_provider = os.getenv("LLM_PROVIDER", "openai").lower()

    # Try OpenAI first if specified (uses openai folder)
    if llm_provider == "openai":
        print("[OPENAI] Using OpenAI for LLM...")
        try:
            # PYTHONPATH에 openai 폴더가 이미 추가되어 있을 수 있음
            # 먼저 직접 import 시도
            import sys
            from pathlib import Path

            # 디버깅: 현재 PYTHONPATH 확인
            print(f"[OPENAI] Current PYTHONPATH: {os.environ.get('PYTHONPATH', 'Not set')}")
            print(f"[OPENAI] sys.path: {sys.path[:5]}...")  # 처음 5개만 출력

            try:
                from app.core.llm.openai import init_openai_llm  # type: ignore
                print("[OPENAI] Successfully imported init_openai_llm from PYTHONPATH")
            except ImportError as import_error:
                print(f"[OPENAI] Import failed: {import_error}")
                print("[OPENAI] Attempting to find and add openai folder to sys.path...")

                # 여러 방법으로 repo root 찾기
                repo_root = None
                
                # 방법 1: 현재 파일 위치에서 계산
                current_file = Path(__file__).resolve()
                # midm/app/core/rag_chain.py -> ../../.. -> repo root
                potential_root = current_file.parent.parent.parent.parent
                if (potential_root / "openai").exists():
                    repo_root = potential_root
                    print(f"[OPENAI] Found repo root via file path: {repo_root}")
                
                # 방법 2: 현재 작업 디렉토리에서 찾기
                if repo_root is None:
                    cwd = Path(os.getcwd()).resolve()
                    # WorkingDirectory가 midm/app이므로, ../../ -> repo root
                    potential_root = cwd.parent.parent
                    if (potential_root / "openai").exists():
                        repo_root = potential_root
                        print(f"[OPENAI] Found repo root via CWD: {repo_root}")
                
                # 방법 3: 환경 변수에서 찾기
                if repo_root is None:
                    deploy_path = os.environ.get("DEPLOY_PATH", "/opt/langchain")
                    potential_root = Path(deploy_path)
                    if (potential_root / "openai").exists():
                        repo_root = potential_root
                        print(f"[OPENAI] Found repo root via DEPLOY_PATH: {repo_root}")
                
                if repo_root is None:
                    raise FileNotFoundError(
                        f"Could not find repo root. Tried:\n"
                        f"  - {current_file.parent.parent.parent.parent}\n"
                        f"  - {Path(os.getcwd()).parent.parent}\n"
                        f"  - {os.environ.get('DEPLOY_PATH', '/opt/langchain')}"
                    )

                openai_path = repo_root / "openai"
                print(f"[OPENAI] Looking for openai folder at: {openai_path}")
                print(f"[OPENAI] openai_path exists: {openai_path.exists()}")
                
                if not openai_path.exists():
                    raise FileNotFoundError(f"openai folder not found at {openai_path}")

                # openai 폴더를 sys.path에 추가
                openai_path_str = str(openai_path.resolve())
                if openai_path_str not in sys.path:
                    sys.path.insert(0, openai_path_str)
                    print(f"[OPENAI] Added to Python path: {openai_path_str}")
                
                # openai/app/__init__.py 확인
                app_init = openai_path / "app" / "__init__.py"
                print(f"[OPENAI] Checking app/__init__.py: {app_init.exists()}")
                
                # 다시 import 시도
                try:
                    from app.core.llm.openai import init_openai_llm  # type: ignore
                    print("[OPENAI] Successfully imported init_openai_llm after adding to path")
                except ImportError as retry_error:
                    print(f"[OPENAI] Import still failed after adding path: {retry_error}")
                    print(f"[OPENAI] sys.path now: {sys.path[:5]}...")
                    raise

            # OpenAI LLM 초기화
            print("[OPENAI] Initializing OpenAI LLM...")
            return init_openai_llm()
        except Exception as e:
            print(f"[ERROR] Failed to initialize OpenAI: {e}")
            import traceback
            traceback.print_exc()
            raise RuntimeError(f"OpenAI initialization failed: {e}. Please check OPENAI_API_KEY and openai folder.") from e

    # Try Ollama if specified
    if llm_provider == "ollama":
        print("Using Ollama for LLM...")
        try:
            from core.llm.ollama import init_ollama_llm  # type: ignore
            return init_ollama_llm()
        except (ModuleNotFoundError, RuntimeError) as e:
            print(f"[WARNING] Failed to initialize Ollama: {e}")
            print("[INFO] Falling back to HuggingFace transformers...")
            # Fall through to HuggingFace

    # Use HuggingFace transformers (midm 모델 - 더 이상 사용 안 함)
    print("[WARNING] HuggingFace/midm model is deprecated. Please use LLM_PROVIDER=openai")
    return _init_huggingface_llm()


def _init_huggingface_llm() -> HuggingFacePipeline:
    """Initialize a local HF causal LM (Mi:dm by default).

    Returns:
        HuggingFacePipeline instance backed by a transformers text-generation pipeline.
    """
    if torch is None or AutoTokenizer is None or AutoModelForCausalLM is None or pipeline is None:  # pragma: no cover
        msg = (
            "Missing required dependencies for local model inference. "
            "Please install `torch` and `transformers` (and optionally `accelerate`, `bitsandbytes`)."
        )
        raise ModuleNotFoundError(msg)

    # 환경 변수에서 모델 경로 읽기
    local_model_dir = os.getenv("LOCAL_MODEL_DIR")
    llm_provider = os.getenv("LLM_PROVIDER", "midm")
    model_path = _resolve_local_model_path(local_model_dir)

    print(f"LLM Provider: {llm_provider} (local transformers)")
    print(f"Loading local model from: {model_path}")

    # 모델 경로 존재 확인
    if not os.path.exists(model_path):
        raise FileNotFoundError(
            f"Model directory not found: {model_path}\n"
            f"Please set LOCAL_MODEL_DIR in .env file or ensure model exists."
        )

    # GPU 확인
    if torch.cuda.is_available():
        print(f"GPU detected: {torch.cuda.get_device_name(0)}")
        print(
            f"GPU memory: {torch.cuda.get_device_properties(0).total_memory / 1024**3:.2f} GB"
        )
    else:
        print("WARNING: No GPU detected. Using CPU (will be VERY slow)")

    # 4bit 양자화는 일반적으로 CUDA 환경에서만 안정적으로 동작.
    # CPU 환경에서는 quantization_config 없이 로드해서 크래시를 피한다.
    bnb_config: Optional[BitsAndBytesConfig]
    if BitsAndBytesConfig is not None and torch.cuda.is_available():
        print("Using 4bit quantization (bitsandbytes)...")
        bnb_config = BitsAndBytesConfig(
            load_in_4bit=True,
            bnb_4bit_compute_dtype=torch.bfloat16,
            bnb_4bit_quant_type="nf4",
            bnb_4bit_use_double_quant=True,
        )
    else:
        bnb_config = None

    # 토크나이저 & 모델 로딩
    print("Loading tokenizer...")
    # Mi:dm 문서에서 trust_remote_code=True 사용. 로컬 스냅샷에서도 안전하게 따라간다.
    tokenizer = AutoTokenizer.from_pretrained(
        model_path, use_fast=True, trust_remote_code=True
    )

    # 일부 모델은 pad_token이 없을 수 있으므로 안전하게 세팅
    if tokenizer.pad_token_id is None and tokenizer.eos_token_id is not None:
        tokenizer.pad_token = tokenizer.eos_token

    print(f"Tokenizer vocab size: {len(tokenizer)}")
    print(f"BOS token: {tokenizer.bos_token} (ID: {tokenizer.bos_token_id})")
    print(f"EOS token: {tokenizer.eos_token} (ID: {tokenizer.eos_token_id})")
    print(f"PAD token: {tokenizer.pad_token} (ID: {tokenizer.pad_token_id})")

    print("Loading model (this may take a while)...")
    model_kwargs = {
        "device_map": "auto" if torch.cuda.is_available() else None,
        "torch_dtype": torch.bfloat16 if torch.cuda.is_available() else torch.float32,
        "trust_remote_code": True,
        "low_cpu_mem_usage": True,  # Reduce memory usage during loading
    }
    if bnb_config is not None:
        model_kwargs["quantization_config"] = bnb_config

    model = AutoModelForCausalLM.from_pretrained(model_path, **model_kwargs)

    print("Creating text-generation pipeline...")
    pipe = pipeline(
        "text-generation",
        model=model,
        tokenizer=tokenizer,
        max_new_tokens=256,
        do_sample=False,
        return_full_text=False,
        pad_token_id=tokenizer.pad_token_id,
        eos_token_id=tokenizer.eos_token_id,
    )

    # LangChain LLM 객체로 래핑
    llm = HuggingFacePipeline(pipeline=pipe)

    print("[OK] Local HF LLM initialized!")
    return llm


def create_rag_chain(vector_store: PGVector, llm: Union[HuggingFacePipeline, Any]) -> Runnable:
    """Create RAG chain with retriever and LLM.

    Args:
        vector_store: PGVector instance for document retrieval.
        llm: HuggingFacePipeline instance for generation.

    Returns:
        RAG chain (runnable).
    """
    prompt = _build_rag_prompt()

    def format_docs(docs: List[Document]) -> str:
        return "\n\n".join(doc.page_content for doc in docs)

    def format_history(history: Optional[List[dict]]) -> str:
        """Format conversation history for the prompt."""
        if not history or len(history) == 0:
            return ""

        # 최근 10개 대화만 포함 (토큰 제한 고려)
        recent_history = history[-10:] if len(history) > 10 else history

        history_text = "이전 대화:\n"
        for msg in recent_history:
            role = msg.get("role", "")
            content = msg.get("content", "")
            if role == "user":
                history_text += f"사용자: {content}\n"
            elif role == "assistant":
                history_text += f"어시스턴트: {content}\n"

        return history_text + "\n"

    def create_rag_input(input_data: dict) -> dict:
        """Create input for RAG chain with history.

        Note: Retriever is called separately in the router to support async_mode.
        """
        question = input_data.get("question", "")
        history = input_data.get("history", None)

        # Documents will be retrieved separately in the router
        # This function just formats the input
        return {
            "context": input_data.get("context", ""),
            "history": format_history(history),
            "question": question,
        }

    rag_chain: Runnable = (
        create_rag_input
        | prompt
        | llm
        | StrOutputParser()
    )

    return rag_chain
