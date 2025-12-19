import { NextResponse } from "next/server";

export async function POST(req: Request) {
  // 항상 백엔드로 연결 (백엔드에서 OpenAI 또는 midm 사용)
  let backendBaseUrl = process.env.BACKEND_BASE_URL ?? "http://localhost:8000";

  // URL 끝의 슬래시 제거 (중복 방지)
  backendBaseUrl = backendBaseUrl.replace(/\/+$/, "");

  // 디버깅: 환경 변수 확인 (프로덕션에서는 로그에서만 확인 가능)
  console.log("[CHAT] Backend URL:", backendBaseUrl);
  console.log("[CHAT] Environment variables:", {
    BACKEND_BASE_URL: process.env.BACKEND_BASE_URL ? "SET" : "NOT SET",
    VERCEL: process.env.VERCEL,
  });

  const body = await req.text();

  try {
    // 타임아웃 설정 (30초)
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 30000);

    const upstream = await fetch(`${backendBaseUrl}/chat`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body,
      signal: controller.signal,
    });

    clearTimeout(timeoutId);

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
    console.error("[CHAT] Failed to connect to backend:", error);
    console.error("[CHAT] Backend URL attempted:", backendBaseUrl);
    console.error("[CHAT] Error details:", error instanceof Error ? error.message : String(error));

    return new NextResponse(
      JSON.stringify({
        detail: `Failed to connect to backend at ${backendBaseUrl}. Make sure the backend server is running and BACKEND_BASE_URL is set in Vercel environment variables.`,
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
