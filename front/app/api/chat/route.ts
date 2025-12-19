import { NextResponse } from "next/server";

export async function POST(req: Request) {
  // Vercel 환경에서는 OpenAI 사용, 로컬에서는 백엔드(midm) 사용
  const useOpenAI = process.env.VERCEL === "1" || process.env.USE_OPENAI === "true";
  const openaiApiKey = process.env.OPENAI_API_KEY;

  const body = await req.text();
  const requestData = JSON.parse(body);

  // Vercel 환경에서 OpenAI 사용
  if (useOpenAI && openaiApiKey) {
    try {
      const messages = [
        ...(requestData.conversation_history || []).map((msg: { role: string; content: string }) => ({
          role: msg.role,
          content: msg.content,
        })),
        {
          role: "user",
          content: requestData.message || requestData.question || "",
        },
      ];

      const openaiResponse = await fetch("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${openaiApiKey}`,
        },
        body: JSON.stringify({
          model: process.env.OPENAI_MODEL || "gpt-4o-mini",
          messages: messages,
          temperature: 0.7,
        }),
      });

      if (!openaiResponse.ok) {
        const errorText = await openaiResponse.text();
        console.error(`OpenAI API error: ${openaiResponse.status} - ${errorText}`);
        return new NextResponse(
          JSON.stringify({ detail: `OpenAI API error: ${openaiResponse.status}` }),
          {
            status: openaiResponse.status,
            headers: {
              "content-type": "application/json",
            },
          }
        );
      }

      const openaiData = await openaiResponse.json();
      const answer = openaiData.choices[0]?.message?.content || "응답을 생성할 수 없습니다.";

      return new NextResponse(
        JSON.stringify({
          message: requestData.message || requestData.question || "",
          answer: answer,
        }),
        {
          status: 200,
          headers: {
            "content-type": "application/json",
          },
        }
      );
    } catch (error) {
      console.error("OpenAI API request failed:", error);
      return new NextResponse(
        JSON.stringify({
          detail: `OpenAI API request failed: ${error instanceof Error ? error.message : "Unknown error"}`,
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

  // 로컬 환경에서는 백엔드(midm) 사용
  const backendBaseUrl = process.env.BACKEND_BASE_URL ?? "http://localhost:8000";

  try {
    const upstream = await fetch(`${backendBaseUrl}/chat`, {
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


