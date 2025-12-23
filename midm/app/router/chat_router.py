"""RAG router moved from `app/api/routes/rag.py`.

NOTE:
- The user requested moving the router implementation here.
- We keep `app/api/routes/rag.py` as a thin re-export wrapper for backward compatibility.
"""

from __future__ import annotations

import importlib
import logging
import os
from typing import TYPE_CHECKING

from api.models import QueryRequest, RAGResponse  # type: ignore

if TYPE_CHECKING:  # pragma: no cover
    from fastapi import APIRouter, HTTPException, Request
else:
    fastapi_mod = importlib.import_module("fastapi")
    APIRouter = getattr(fastapi_mod, "APIRouter")  # type: ignore[assignment]
    HTTPException = getattr(fastapi_mod, "HTTPException")  # type: ignore[assignment]
    Request = getattr(fastapi_mod, "Request")  # type: ignore[assignment]

router = APIRouter(prefix="/rag", tags=["RAG"])
logger = logging.getLogger("rag-api")

# Global references (will be set by main app)
vector_store = None
rag_chain = None


def set_dependencies(vs, chain) -> None:
    """Set vector store and RAG chain dependencies."""
    global vector_store, rag_chain
    vector_store = vs
    rag_chain = chain


@router.post("", response_model=RAGResponse)
async def rag_query(request: QueryRequest, raw_request: Request) -> RAGResponse:
    """RAG (Retrieval-Augmented Generation) - 검색 + 답변 생성.

    Args:
        request: Query request with question and k.

    Returns:
        RAG response with answer and retrieved documents.
    """
    request_id = getattr(getattr(raw_request, "state", None), "request_id", "-")
    
    try:
        if not vector_store:
            raise HTTPException(status_code=500, detail="Vector store not initialized")
        
        # Check if rag_chain is available (OpenAI or standard LLM mode)
        # If rag_chain exists, use it; otherwise fall back to QLoRA
        use_rag_chain = rag_chain is not None
        use_qlora = False
        base_model_path = None
        
        if not use_rag_chain:
            # Fall back to QLoRA mode if rag_chain is not available
            base_model_path = os.getenv("QLORA_BASE_MODEL_PATH")
            use_qlora = os.getenv("USE_QLORA", "0").lower() in {"1", "true", "yes"}
            if not (use_qlora and base_model_path):
                raise HTTPException(
                    status_code=500,
                    detail="Neither RAG chain nor QLoRA is configured. Please set LLM_PROVIDER=openai or configure QLoRA."
                )

        print(
            "[ROUTER] /rag received",
            {
                "request_id": request_id,
                "question_preview": (request.question or "")[:200],
                "k": request.k,
            },
        )
        logger.info(
            "[RAG] id=%s q=%r k=%s history_len=%s",
            request_id,
            (request.question or "")[:160],
            request.k,
            len(request.conversation_history or []),
        )

        # Retrieve documents with similarity scores (async)
        retrieved_docs_with_scores = await vector_store.asimilarity_search_with_score(
            request.question, k=request.k
        )

        # PGVector returns list of (Document, score) tuples
        # Filter documents by relevance threshold
        relevance_threshold = 0.8
        retrieved_docs = [
            doc
            for doc, score in retrieved_docs_with_scores
            if score < relevance_threshold  # Lower score = more similar in pgvector
        ]

        print(
            f"[RAG] Retrieved {len(retrieved_docs)} relevant documents (threshold: {relevance_threshold})"
        )

        # Generate answer with conversation history
        print("[RAG] Generating answer...")
        history = request.conversation_history or []
        print(f"[RAG] Conversation history: {len(history)} messages")

        # Format context from retrieved documents
        context = "\n\n".join(doc.page_content for doc in retrieved_docs)

        # Generate answer using rag_chain (OpenAI/standard LLM) or QLoRA
        if use_rag_chain:
            # Use rag_chain (OpenAI or standard LLM mode)
            print("[RAG] Using rag_chain for answer generation")
            
            # Build input for rag_chain
            # rag_chain expects: {"question": str, "context": str, "history": list}
            chain_input = {
                "question": request.question,
                "context": context,
                "history": history,
            }
            
            # Invoke rag_chain (supports both sync and async)
            if hasattr(rag_chain, "ainvoke"):
                chain_result = await rag_chain.ainvoke(chain_input)
            elif hasattr(rag_chain, "invoke"):
                chain_result = rag_chain.invoke(chain_input)
            else:
                chain_result = rag_chain(chain_input)
            
            # Extract answer from chain result
            answer = str(getattr(chain_result, "content", chain_result)).strip()
            logger.info(
                "[RAG] id=%s backend=rag_chain answer_preview=%r", request_id, answer[:120]
            )
        else:
            # Use QLoRA mode
            print("[RAG] Using QLoRA for answer generation")
            adapter_path = os.getenv("QLORA_ADAPTER_PATH") or None
            from service.chat_service import rag_chat_with_qlora  # type: ignore

            answer = rag_chat_with_qlora(
                base_model_path=base_model_path,
                adapter_path=adapter_path,
                question=request.question,
                context=context,
                conversation_history=history,
                max_new_tokens=int(os.getenv("QLORA_MAX_NEW_TOKENS", "256")),
                request_id=request_id,
            )
            logger.info(
                "[RAG] id=%s backend=qlora answer_preview=%r", request_id, answer[:120]
            )

        # 답변 정제: 불필요한 텍스트 제거
        answer = answer.strip()

        # 일부 추론형/지시형 모델이 출력에 포함하는 <think>...</think> 제거
        if "<think>" in answer:
            if "</think>" in answer:
                answer = answer.split("</think>")[-1].strip()
            else:
                answer = answer.split("<think>")[0].strip()

        # 모델/프롬프트 잔여 특수 토큰 제거
        special_tokens_to_strip = [
            "<|start_header_id|>",
            "<|end_header_id|>",
            "<|eot_id|>",
            "<|begin_of_text|>",
            "system<|end_header_id|>",
            "user<|end_header_id|>",
            "assistant<|end_header_id|>",
            "[SYSTEM]",
            "[HISTORY]",
            "[CONTEXT]",
            "[USER]",
            "[ASSISTANT]",
        ]
        for token in special_tokens_to_strip:
            answer = answer.replace(token, "")

        # Stop sequences로 생성 중단
        stop_sequences = [
            "질문:",
            "참고 정보:",
            "규칙:",
            "\n\n참고",
            "\n\n질문",
            "<|start_header_id|>",
        ]
        for stop_seq in stop_sequences:
            if stop_seq in answer:
                answer = answer.split(stop_seq)[0].strip()

        # 프롬프트 잔여물 제거
        if "답변:" in answer and not answer.startswith("답변:"):
            answer = answer.split("답변:")[-1].strip()

        # 연속된 줄바꿈 정리
        while "\n\n\n" in answer:
            answer = answer.replace("\n\n\n", "\n\n")

        # 너무 긴 답변 자르기 (300자 제한)
        if len(answer) > 300:
            answer_prefix: str = answer[:300]
            last_period: int = answer_prefix.rfind(".")
            if last_period > 200:
                answer = answer[: last_period + 1]
            else:
                answer = answer_prefix + "..."

        answer_preview: str = answer[:100] if len(answer) > 100 else answer
        print(f"[RAG] Answer generated: {answer_preview}...")

        return RAGResponse(
            question=request.question,
            answer=answer,
            retrieved_documents=[
                {"content": doc.page_content, "metadata": doc.metadata}
                for doc in retrieved_docs
            ],
            retrieved_count=len(retrieved_docs),
        )
    except Exception as e:
        print(f"[RAG] Error: {str(e)}")
        import traceback

        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))
