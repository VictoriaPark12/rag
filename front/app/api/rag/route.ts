import { NextResponse } from "next/server";

export async function POST(req: Request) {
  // Vercel 환경에서는 OpenAI 사용, 로컬에서는 백엔드(midm) 사용
  const useOpenAI = process.env.VERCEL === "1" || process.env.USE_OPENAI === "true";
  const openaiApiKey = process.env.OPENAI_API_KEY;

  const body = await req.text();
  const requestData = JSON.parse(body);

  // Vercel 환경에서 OpenAI 사용 (RAG는 백엔드 벡터 스토어 필요하므로 백엔드로 전달)
  // RAG는 벡터 검색이 필요하므로 백엔드를 통해야 함
  // 단, Vercel에서도 백엔드로 연결하도록 설정
  const backendBaseUrl = process.env.BACKEND_BASE_URL ?? "http://localhost:8000";

  try {
    const upstream = await fetch(`${backendBaseUrl}/rag`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body,
    });

    const contentType = upstream.headers.get("content-type") ?? "application/json";
    const text = await upstream.text();

    if (!upstream.ok) {
      console.error(`Backend error: ${upstream.status} - ${text}`);
      return new NextResponse(
        JSON.stringify({ detail: `Backend error: ${upstream.status} - ${text}` }),
        {
          status: upstream.status,
          headers: {
            "content-type": "application/json",
          },
        }
      );
    }

    return new NextResponse(text, {
      status: upstream.status,
      headers: {
        "content-type": contentType,
      },
    });
  } catch (error) {
    console.error("Failed to connect to backend:", error);
    return new NextResponse(
      JSON.stringify({
        detail: `Failed to connect to backend at ${backendBaseUrl}. Make sure the backend server is running.`,
      }),
      {
        status: 503,
        headers: {
          "content-type": "application/json",
        },
      }
    );
  }
}


