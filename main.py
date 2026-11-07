import os
import uuid
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
    version="0.2.0"
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
        "version": "0.2.0"
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
    business: str = Form("Knauf and interior decoration"),
    platform: str = Form("Instagram Reels"),
    language: str = Form("Persian")
):

    if not GROQ_API_KEY:
        raise HTTPException(503, "GROQ_API_KEY is missing.")

    path = await save_upload(video)

    try:

        prompt = f"""
You are a professional Persian social media content creator.

Business: {business}
Platform: {platform}
Language: {language}

Video transcript:
{transcript or "No transcript provided."}

Create:
1. Three creative Reel ideas.
2. A strong opening hook for each idea.
3. Suggested shot order.
4. One professional Persian Instagram caption.
5. A clear call to action.
6. 8 to 12 relevant hashtags.

Do not invent scenes that are not supported by the transcript.
Write naturally and professionally.
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
                            "role": "user",
                            "content": prompt
                        }
                    ],
                    "temperature": 0.7
                }
            )

        if response.status_code != 200:
            raise HTTPException(
                response.status_code,
                f"AI content error: {response.text[:1000]}"
            )

        result = response.json()["choices"][0]["message"]["content"]

        return {
            "ideas": result,
            "caption": ""
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
