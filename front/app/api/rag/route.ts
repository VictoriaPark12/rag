// @ts-ignore - Next.js 타입 정의
import { NextRequest, NextResponse } from "next/server";

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();

    // 백엔드 URL 설정 (환경 변수만 사용)
    // @ts-expect-error - Node.js process 타입 (Next.js 서버 사이드에서 사용 가능)
    const backendBaseUrl = process.env.BACKEND_BASE_URL;
    
    if (!backendBaseUrl) {
      console.error("[API Route] BACKEND_BASE_URL environment variable is not set");
      return NextResponse.json(
        { detail: "Backend URL is not configured. Please set BACKEND_BASE_URL environment variable." },
        { status: 500 }
      );
    }

    const backendUrl = `${backendBaseUrl}/rag`;

    console.log(`[API Route] Proxying to backend: ${backendUrl}`);

    // EC2 백엔드로 프록시 요청
    // Vercel 서버리스 함수 타임아웃: 기본 10초, 최대 60초 (Pro 플랜)
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 50000); // 50초 타임아웃
    
    let response: Response;
    try {
      response = await fetch(backendUrl, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
        signal: controller.signal,
      });
    } catch (fetchError) {
      clearTimeout(timeoutId);
      console.error(`[API Route] Fetch error for ${backendUrl}:`, fetchError);
      
      // 더 자세한 에러 메시지
      let errorMessage = "Unknown fetch error";
      if (fetchError instanceof Error) {
        if (fetchError.name === "AbortError") {
          errorMessage = "Backend request timeout. The server may be taking too long to respond.";
        } else if (fetchError.message.includes("ECONNREFUSED") || fetchError.message.includes("ENOTFOUND")) {
          errorMessage = `Cannot connect to backend server at ${backendUrl}. Please check if the backend is running.`;
        } else if (fetchError.message.includes("fetch failed")) {
          errorMessage = `Network error: Unable to reach backend server at ${backendUrl}. Check network connectivity and backend status.`;
        } else {
          errorMessage = fetchError.message;
        }
      }
      
      return NextResponse.json(
        { detail: errorMessage },
        { status: 500 }
      );
    }
    
    clearTimeout(timeoutId);

    if (!response.ok) {
      const errorText = await response.text();
      console.error(`[API Route] Backend error: ${response.status}`, errorText);
      return NextResponse.json(
        { detail: errorText || `Backend error: ${response.status}` },
        { status: response.status }
      );
    }

    const data = await response.json();
    return NextResponse.json(data);
  } catch (error) {
    console.error("[API Route] Error:", error);
    return NextResponse.json(
      { detail: error instanceof Error ? error.message : "Unknown error" },
      { status: 500 }
    );
  }
}

