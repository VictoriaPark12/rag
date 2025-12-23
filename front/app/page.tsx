"use client";

import { useState, useRef, useEffect } from "react";

interface RAGResponse {
  question: string;
  answer: string;
  retrieved_documents: Array<{
    content: string;
    metadata: Record<string, unknown>;
  }>;
  retrieved_count: number;
}

interface ChatResponse {
  message: string;
  answer: string;
}

interface Message {
  role: "user" | "assistant";
  content: string;
}

export default function Home() {
  const [query, setQuery] = useState("");
  const [loading, setLoading] = useState(false);
  const [response, setResponse] = useState<RAGResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [conversationHistory, setConversationHistory] = useState<Message[]>([]);
  const [mode, setMode] = useState<"chat" | "rag">("chat");
  const inputRef = useRef<HTMLInputElement>(null);
  const messagesEndRef = useRef<HTMLDivElement>(null);

  // 입력창 포커스 유지
  useEffect(() => {
    if (!loading && inputRef.current) {
      inputRef.current.focus();
    }
  }, [loading, response]);

  // 대화 히스토리 스크롤 자동 이동
  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [conversationHistory, loading]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!query.trim()) return;

    setLoading(true);
    setError(null);
    setResponse(null);

    try {
      console.log("Sending request:", { mode, query });

      // 타임아웃 설정 (5분) - CPU 모드에서는 오래 걸림
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 300000);

      // Next.js API Route로 요청 (서버에서 백엔드로 프록시)
      const apiEndpoint = mode === "rag" ? "/api/rag" : "/api/chat";
      const requestBody = mode === "rag"
        ? {
            question: query,
            k: 3,
            conversation_history: conversationHistory,
          }
        : {
            message: query,
            conversation_history: conversationHistory,
          };

      console.log(`[CLIENT] Calling API route: ${apiEndpoint}`);

      const res = await fetch(apiEndpoint, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify(requestBody),
        signal: controller.signal,
      });

      clearTimeout(timeoutId);
      console.log("Response status:", res.status);

      if (!res.ok) {
        const errorData = await res.json().catch(() => ({ detail: "Unknown error" }));
        console.error("Error response:", errorData);
        throw new Error(`HTTP error! status: ${res.status} - ${errorData.detail || "Unknown error"}`);
      }

      const data = await res.json();
      console.log("Success response:", data);

      if (mode === "rag") {
        setResponse(data as RAGResponse);
      } else {
        setResponse(null);
      }

      // 대화 히스토리에 추가
      setConversationHistory((prev) => [
        ...prev,
        { role: "user", content: query },
        { role: "assistant", content: (data as RAGResponse | ChatResponse).answer },
      ]);

      // 입력창 초기화
      setQuery("");
    } catch (err) {
      let errorMessage = "알 수 없는 오류가 발생했습니다.";

      if (err instanceof Error) {
        if (err.name === "AbortError") {
          errorMessage = "요청 시간이 초과되었습니다. 서버가 아직 준비 중일 수 있습니다. 잠시 후 다시 시도해주세요.";
        } else if (err.message.includes("Failed to fetch")) {
          errorMessage = "서버에 연결할 수 없습니다. 서버가 실행 중인지 확인해주세요.";
        } else {
          errorMessage = err.message;
        }
      }

      setError(errorMessage);
      console.error("Error details:", err);
    } finally {
      setLoading(false);
    }
  };

  const handleResetHistory = () => {
    setConversationHistory([]);
    setResponse(null);
    setError(null);
    setQuery("");
    if (inputRef.current) {
      inputRef.current.focus();
    }
  };

  return (
    <div className="flex min-h-screen flex-col bg-black font-sans">
      {/* Main Content */}
      <main className="flex-1 flex flex-col items-center px-6 pb-32 pt-6 overflow-y-auto">
        {/* Reset History Button */}
        {conversationHistory.length > 0 && (
          <div className="w-full max-w-3xl mb-4 flex justify-end">
            <div className="mr-auto flex items-center gap-2">
              <button
                type="button"
                onClick={() => setMode("chat")}
                disabled={loading}
                className={`rounded-lg border px-3 py-2 text-sm transition-colors ${
                  mode === "chat"
                    ? "bg-blue-600/30 border-blue-500 text-blue-200"
                    : "bg-gray-800/50 border-gray-700 text-gray-300 hover:bg-gray-700/50 hover:text-white"
                } disabled:opacity-50 disabled:cursor-not-allowed`}
                title="일반 대화 (RAG 없이)"
              >
                일반 대화
              </button>
              <button
                type="button"
                onClick={() => setMode("rag")}
                disabled={loading}
                className={`rounded-lg border px-3 py-2 text-sm transition-colors ${
                  mode === "rag"
                    ? "bg-green-600/30 border-green-500 text-green-200"
                    : "bg-gray-800/50 border-gray-700 text-gray-300 hover:bg-gray-700/50 hover:text-white"
                } disabled:opacity-50 disabled:cursor-not-allowed`}
                title="영화 리뷰 데이터 기반 RAG"
              >
                영화 RAG
              </button>
            </div>
            <button
              onClick={handleResetHistory}
              disabled={loading}
              className="flex items-center gap-2 rounded-lg bg-gray-800/50 border border-gray-700 px-4 py-2 text-sm text-gray-300 transition-colors hover:bg-gray-700/50 hover:text-white disabled:opacity-50 disabled:cursor-not-allowed"
              title="대화 히스토리 초기화"
            >
              <svg
                width="16"
                height="16"
                viewBox="0 0 16 16"
                fill="none"
                xmlns="http://www.w3.org/2000/svg"
              >
                <path
                  d="M8 3V1M8 3L6 1M8 3L10 1M3 8C3 5.79086 4.79086 4 7 4C9.20914 4 11 5.79086 11 8C11 10.2091 9.20914 12 7 12C4.79086 12 3 10.2091 3 8Z"
                  stroke="currentColor"
                  strokeWidth="1.5"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                />
              </svg>
              새 대화 시작
            </button>
          </div>
        )}

        {/* Conversation History Display */}
        <div className="w-full max-w-3xl space-y-4">
          {conversationHistory.length === 0 && !loading && (
            <div className="text-center text-gray-500 mt-20">
              대화를 시작해보세요 (현재 모드: {mode === "chat" ? "일반 대화" : "영화 RAG"})
            </div>
          )}
          {conversationHistory.map((msg, idx) => (
            <div
              key={idx}
              className={`rounded-2xl border p-6 ${
                msg.role === "user"
                  ? "bg-gray-800/50 border-gray-700 ml-auto max-w-[80%]"
                  : "bg-gray-900/50 border-gray-700 mr-auto max-w-[80%]"
              }`}
            >
              <p className="text-gray-200 leading-relaxed whitespace-pre-wrap">
                {msg.content}
              </p>
            </div>
          ))}

          {/* Loading indicator */}
          {loading && (
            <div className="rounded-2xl border bg-gray-900/50 border-gray-700 p-6 mr-auto max-w-[80%]">
              <div className="flex items-center gap-2 text-gray-400">
                <svg
                  className="animate-spin h-5 w-5"
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                >
                  <circle
                    className="opacity-25"
                    cx="12"
                    cy="12"
                    r="10"
                    stroke="currentColor"
                    strokeWidth="4"
                  ></circle>
                  <path
                    className="opacity-75"
                    fill="currentColor"
                    d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                  ></path>
                </svg>
                <span>답변 생성 중...</span>
              </div>
            </div>
          )}
          <div ref={messagesEndRef} />
        </div>

        {/* Error Display */}
        {error && (
          <div className="mb-8 w-full max-w-3xl rounded-2xl bg-red-900/20 border border-red-700 p-4">
            <p className="text-red-300">{error}</p>
          </div>
        )}

        {/* Search Input Container - Fixed at bottom */}
        <div className="fixed bottom-0 left-0 right-0 bg-black px-6 py-6">
          <form onSubmit={handleSubmit} className="mx-auto w-full max-w-3xl">
            <div className="relative w-full rounded-2xl bg-white/5 border border-white/10 p-4">
              {/* Input Field */}
              <div className="flex items-center gap-3">
                <input
                  ref={inputRef}
                  type="text"
                  value={query}
                  onChange={(e) => setQuery(e.target.value)}
                  placeholder={
                    mode === "chat"
                      ? "무엇이든 물어보세요 (일반 대화)"
                      : "영화 리뷰 기반으로 물어보세요 (영화 RAG)"
                  }
                  disabled={loading}
                  autoFocus
                  className="flex-1 bg-transparent text-white placeholder:text-gray-500 focus:outline-none text-lg disabled:opacity-50"
                />
                <button
                  type="submit"
                  disabled={loading || !query.trim()}
                  className="flex items-center gap-2 rounded-lg bg-white/10 px-4 py-2 text-sm text-white/80 transition-colors hover:bg-white/20 disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  {loading ? (
                    <svg
                      className="animate-spin h-5 w-5 text-white/60"
                      xmlns="http://www.w3.org/2000/svg"
                      fill="none"
                      viewBox="0 0 24 24"
                    >
                      <circle
                        className="opacity-25"
                        cx="12"
                        cy="12"
                        r="10"
                        stroke="currentColor"
                        strokeWidth="4"
                      ></circle>
                      <path
                        className="opacity-75"
                        fill="currentColor"
                        d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                      ></path>
                    </svg>
                  ) : (
                    <svg
                      width="20"
                      height="20"
                      viewBox="0 0 20 20"
                      fill="none"
                      className="text-white/60"
                    >
                      <circle
                        cx="10"
                        cy="10"
                        r="7"
                        stroke="currentColor"
                        strokeWidth="1.5"
                      />
                      <path
                        d="M10 6v4l2 2"
                        stroke="currentColor"
                        strokeWidth="1.5"
                        strokeLinecap="round"
                      />
                    </svg>
                  )}
                </button>
              </div>
            </div>
          </form>
        </div>
      </main>
    </div>
  );
}
