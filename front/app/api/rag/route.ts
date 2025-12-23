// @ts-ignore - Next.js 타입 정의
import { NextRequest, NextResponse } from "next/server";

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();

    // 백엔드 URL 설정 (환경 변수 또는 fallback)
    const backendBaseUrl =
      // @ts-expect-error - Node.js process 타입 (Next.js 서버 사이드에서 사용 가능)
      process.env.BACKEND_BASE_URL ||
      "http://ec2-13-124-217-222.ap-northeast-2.compute.amazonaws.com:8000";

    const backendUrl = `${backendBaseUrl}/rag`;

    console.log(`[API Route] Proxying to backend: ${backendUrl}`);

    // EC2 백엔드로 프록시 요청
    const response = await fetch(backendUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    });

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

