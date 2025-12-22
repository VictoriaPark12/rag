import { NextResponse } from "next/server";

export async function POST(req: Request) {
  // 항상 백엔드로 연결 (백엔드에서 OpenAI 또는 midm 사용)
  let backendBaseUrl = process.env.BACKEND_BASE_URL ?? "http://localhost:8000";

  // Fallback 백엔드 URL (1차 연결 실패 시 사용)
  const fallbackBackendUrl = "http://ec2-13-209-75-64.ap-northeast-2.compute.amazonaws.com:8000";

  // URL 정리: 끝의 슬래시, 점, 기타 문자 제거
  backendBaseUrl = backendBaseUrl.trim().replace(/[\/\.]+$/, "");

  // 디버깅: 환경 변수 확인 (프로덕션에서는 로그에서만 확인 가능)
  console.log("[CHAT] Backend URL:", backendBaseUrl);
  console.log("[CHAT] Fallback URL:", fallbackBackendUrl);
  console.log("[CHAT] Environment variables:", {
    BACKEND_BASE_URL: process.env.BACKEND_BASE_URL ? "SET" : "NOT SET",
    VERCEL: process.env.VERCEL,
  });

  const body = await req.text();

  // 백엔드 연결 시도 함수
  const tryBackend = async (url: string, timeout: number = 30000) => {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), timeout);

    try {
      const response = await fetch(`${url}/chat`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body,
        signal: controller.signal,
      });
      clearTimeout(timeoutId);
      return response;
    } catch (error) {
      clearTimeout(timeoutId);
      throw error;
    }
  };

  try {
    // 1차 백엔드 연결 시도
    let upstream = await tryBackend(backendBaseUrl);

    // 1차 연결 실패 시 fallback 시도
    if (!upstream.ok) {
      console.log(`[CHAT] Primary backend returned ${upstream.status}, trying fallback...`);
      try {
        upstream = await tryBackend(fallbackBackendUrl);
        console.log(`[CHAT] Fallback backend connected successfully`);
      } catch (fallbackError) {
        console.error(`[CHAT] Fallback backend also failed:`, fallbackError);
        const text = await upstream.text();
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
    }

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
    const errorMessage = error instanceof Error ? error.message : String(error);
    const isTimeout = errorMessage.includes("aborted") || errorMessage.includes("timeout");
    const isNetworkError = errorMessage.includes("fetch failed") || errorMessage.includes("ECONNREFUSED") || errorMessage.includes("ENOTFOUND");

    console.error("[CHAT] Failed to connect to primary backend:", error);
    console.error("[CHAT] Primary backend URL attempted:", backendBaseUrl);
    console.error("[CHAT] Error details:", errorMessage);
    console.error("[CHAT] Error type:", {
      isTimeout,
      isNetworkError,
      errorName: error instanceof Error ? error.name : "Unknown",
    });

    // 1차 연결 실패 시 fallback 백엔드 시도
    if (isTimeout || isNetworkError) {
      console.log(`[CHAT] Trying fallback backend: ${fallbackBackendUrl}`);
      try {
        const fallbackResponse = await tryBackend(fallbackBackendUrl, 30000);
        console.log(`[CHAT] Fallback backend connected successfully`);

        const contentType = fallbackResponse.headers.get("content-type") ?? "application/json";
        const text = await fallbackResponse.text();

        if (!fallbackResponse.ok) {
          return new NextResponse(
            JSON.stringify({ detail: `Backend error: ${fallbackResponse.status} - ${text}` }),
            {
              status: fallbackResponse.status,
              headers: {
                "content-type": "application/json",
              },
            }
          );
        }

        return new NextResponse(text, {
          status: fallbackResponse.status,
          headers: {
            "content-type": contentType,
          },
        });
      } catch (fallbackError) {
        console.error("[CHAT] Fallback backend also failed:", fallbackError);
      }
    }

    let detailMessage = `Failed to connect to backend at ${backendBaseUrl}.`;

    if (isTimeout) {
      detailMessage += " Connection timeout. The backend server may be slow or not responding.";
    } else if (isNetworkError) {
      detailMessage += " Network error. Please check: 1) EC2 security group allows port 8000 from 0.0.0.0/0, 2) Backend service is running on EC2, 3) Backend is bound to 0.0.0.0:8000 (not localhost).";
    } else {
      detailMessage += " Make sure the backend server is running and BACKEND_BASE_URL is set in Vercel environment variables.";
    }

    return new NextResponse(
      JSON.stringify({
        detail: detailMessage,
        backendUrl: backendBaseUrl,
        fallbackUrl: fallbackBackendUrl,
        errorType: isTimeout ? "timeout" : isNetworkError ? "network" : "unknown",
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
