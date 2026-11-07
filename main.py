import os
import uuid
import json
from pathlib import Path

import httpx
import edge_tts

from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel


BASE = Path(os.getenv("KNUAF_DATA_DIR", "./data")).resolve()
BASE.mkdir(parents=True, exist_ok=True)

app = FastAPI(
    title="KNUAF AI STUDIO API",
    version="0.3.0"
)

GROQ_API_KEY = os.getenv("GROQ_API_KEY")
GROQ_URL = "https://api.groq.com/openai/v1"


async def save_upload(upload: UploadFile) -> Path:
    suffix = Path(upload.filename or "clip.mp4").suffix or ".mp4"
    path = BASE / f"{uuid.uuid4().hex}{suffix}"

    with path.open("wb") as f:
        while chunk := await upload.read(1024 * 1024):
            f.write(chunk)

    return path


@app.get("/health")
def health():
    return {
        "ok": True,
        "service": "KNUAF AI STUDIO",
        "version": "0.3.0"
    }


@app.post("/transcribe")
async def transcribe(video: UploadFile = File(...)):

    if not GROQ_API_KEY:
        raise HTTPException(503, "GROQ_API_KEY is missing.")

    path = await save_upload(video)

    try:
        if path.stat().st_size > 25 * 1024 * 1024:
            raise HTTPException(
                413,
                "Video must be smaller than 25 MB."
            )

        async with httpx.AsyncClient(timeout=180) as client:
            with path.open("rb") as f:
                response = await client.post(
                    f"{GROQ_URL}/audio/transcriptions",
                    headers={
                        "Authorization": f"Bearer {GROQ_API_KEY}"
                    },
                    data={
                        "model": "whisper-large-v3-turbo",
                        "language": "fa",
                        "response_format": "verbose_json"
                    },
                    files={
                        "file": (
                            path.name,
                            f,
                            video.content_type or "video/mp4"
                        )
                    }
                )

        if response.status_code != 200:
            raise HTTPException(
                response.status_code,
                f"Transcription error: {response.text[:1000]}"
            )

        result = response.json()

        return {
            "language": result.get("language", "fa"),
            "text": result.get("text", ""),
            "segments": result.get("segments", [])
        }

    except HTTPException:
        raise

    except Exception as e:
        raise HTTPException(
            500,
            f"Transcription failed: {str(e)}"
        )

    finally:
        path.unlink(missing_ok=True)


class TTSRequest(BaseModel):
    text: str
    voice: str = "fa-IR-FaridNeural"


@app.post("/tts")
async def text_to_speech(payload: TTSRequest):

    if not payload.text.strip():
        raise HTTPException(400, "Text is required.")

    file_id = uuid.uuid4().hex
    out = BASE / f"{file_id}.mp3"

    try:
        await edge_tts.Communicate(
            payload.text,
            payload.voice
        ).save(str(out))

        return FileResponse(
            out,
            media_type="audio/mpeg",
            filename="knuaf-narration.mp3"
        )

    except Exception as e:
        raise HTTPException(
            500,
            f"TTS failed: {str(e)}"
        )


@app.post("/content")
async def content(
    video: UploadFile = File(...),
    transcript: str = Form(""),
    business: str = Form(
        "گروه دکوراسیون داخلی هاشمی؛ طراحی و اجرای کناف، سقف کاذب، نورپردازی و بازسازی"
    ),
    platform: str = Form("Instagram Reels"),
    language: str = Form("Persian")
):

    if not GROQ_API_KEY:
        raise HTTPException(503, "GROQ_API_KEY is missing.")

    path = await save_upload(video)

    try:
        if path.stat().st_size > 25 * 1024 * 1024:
            raise HTTPException(
                413,
                "Video must be smaller than 25 MB."
            )

        prompt = f"""
You are an expert Persian Instagram content strategist
specialized in construction, Knauf and interior decoration.

BUSINESS:
{business}

PLATFORM:
{platform}

OUTPUT LANGUAGE:
{language}

VIDEO TRANSCRIPT:
{transcript.strip() or "No transcript was provided."}

IMPORTANT RULES:

1. This business specializes in:
   - Knauf drywall systems
   - False ceilings
   - Decorative ceilings
   - Linear lighting
   - Interior decoration
   - Painting and patina
   - Renovation and project execution

2. Create content specifically relevant to this business.

3. Use the transcript as the main source of information.

4. Do not invent customers, names, locations, projects,
   dialogue, measurements or events.

5. Do not claim that you visually inspected the video.
   You only have the transcript.

6. If the transcript is empty or unrelated to the business,
   suggest general Knauf and interior decoration content
   without pretending it describes the video.

7. Write naturally in fluent Persian.
   Avoid awkward translations and exaggerated advertising.

RETURN ONLY VALID JSON.
Do not use Markdown code fences.

Use exactly this JSON structure:

{{
  "ideas": [
    {{
      "title": "عنوان ایده اول",
      "hook": "جمله جذاب شروع ریلز",
      "shot_order": [
        "پیشنهاد نمای اول",
        "پیشنهاد نمای دوم",
        "پیشنهاد نمای سوم"
      ],
      "editing_tip": "پیشنهاد تدوین"
    }},
    {{
      "title": "عنوان ایده دوم",
      "hook": "جمله جذاب شروع ریلز",
      "shot_order": [
        "پیشنهاد نمای اول",
        "پیشنهاد نمای دوم",
        "پیشنهاد نمای سوم"
      ],
      "editing_tip": "پیشنهاد تدوین"
    }},
    {{
      "title": "عنوان ایده سوم",
      "hook": "جمله جذاب شروع ریلز",
      "shot_order": [
        "پیشنهاد نمای اول",
        "پیشنهاد نمای دوم",
        "پیشنهاد نمای سوم"
      ],
      "editing_tip": "پیشنهاد تدوین"
    }}
  ],
  "caption": "کپشن کامل و حرفه‌ای فارسی همراه با دعوت به اقدام و هشتگ‌های مرتبط"
}}

The caption must be complete, ready to publish,
and contain relevant Persian hashtags.
"""

        async with httpx.AsyncClient(timeout=120) as client:

            response = await client.post(
                f"{GROQ_URL}/chat/completions",
                headers={
                    "Authorization": f"Bearer {GROQ_API_KEY}",
                    "Content-Type": "application/json"
                },
                json={
                    "model": "openai/gpt-oss-20b",
                    "messages": [
                        {
                            "role": "system",
                            "content": (
                                "You are a professional Persian "
                                "content creator. Return valid JSON only."
                            )
                        },
                        {
                            "role": "user",
                            "content": prompt
                        }
                    ],
                    "temperature": 0.5,
                    "max_completion_tokens": 3000
                }
            )

        if response.status_code != 200:
            raise HTTPException(
                response.status_code,
                f"AI content error: {response.text[:1000]}"
            )

        result = response.json()

        ai_text = result["choices"][0]["message"]["content"]

        try:
            parsed = json.loads(ai_text)

        except json.JSONDecodeError:
            cleaned = ai_text.strip()

            if cleaned.startswith("```"):
                cleaned = cleaned.replace("```json", "", 1)
                cleaned = cleaned.replace("```", "")

            parsed = json.loads(cleaned.strip())

        return {
            "ideas": parsed.get("ideas", []),
            "caption": parsed.get("caption", "")
        }

    except HTTPException:
        raise

    except Exception as e:
        raise HTTPException(
            500,
            f"Content generation failed: {str(e)}"
        )

    finally:
        path.unlink(missing_ok=True)
