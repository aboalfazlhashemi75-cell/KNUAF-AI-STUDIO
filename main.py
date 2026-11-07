import os
import json
import uuid
import subprocess
from pathlib import Path

import httpx
import edge_tts
import imageio_ffmpeg

from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel


# =========================
# SETTINGS
# =========================

VERSION = "0.5.0"

BASE = Path(os.getenv("KNUAF_DATA_DIR", "./data")).resolve()
BASE.mkdir(parents=True, exist_ok=True)

DEEPGRAM_API_KEY = os.getenv("DEEPGRAM_API_KEY")
GROQ_API_KEY = os.getenv("GROQ_API_KEY")

DEEPGRAM_URL = "https://api.deepgram.com/v1/listen"

GROQ_URL = "https://api.groq.com/openai/v1/chat/completions"

app = FastAPI(
    title="KNUAF AI STUDIO",
    version=VERSION
)


# =========================
# MODELS
# =========================

class ContentRequest(BaseModel):
    transcript: str
    business: str = "KNUAF HASHEMI"


class TTSRequest(BaseModel):
    text: str
    voice: str = "fa-IR-DilaraNeural"


# =========================
# HOME
# =========================

@app.get("/")
async def home():
    return {
        "app": "KNUAF AI STUDIO",
        "version": VERSION,
        "status": "online"
    }


@app.get("/health")
async def health():
    return {
        "ok": True,
        "version": VERSION,
        "deepgram_configured": bool(DEEPGRAM_API_KEY),
        "groq_configured": bool(GROQ_API_KEY)
    }


# =========================
# VIDEO TO WAV
# =========================

async def extract_audio(video_path: Path, wav_path: Path):

    ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()

    command = [
        ffmpeg,
        "-y",
        "-i", str(video_path),
        "-vn",
        "-ac", "1",
        "-ar", "16000",
        "-acodec", "pcm_s16le",
        str(wav_path)
    ]

    result = subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180
    )

    if result.returncode != 0:
        raise HTTPException(
            status_code=400,
            detail="Audio extraction failed"
        )

    if not wav_path.exists():
        raise HTTPException(
            status_code=400,
            detail="Audio file was not created"
        )

    if wav_path.stat().st_size == 0:
        raise HTTPException(
            status_code=400,
            detail="Video has no usable audio"
        )


# =========================
# DEEPGRAM TRANSCRIPTION
# =========================

async def transcribe_deepgram(wav_path: Path):

    if not DEEPGRAM_API_KEY:
        raise HTTPException(
            status_code=500,
            detail="DEEPGRAM_API_KEY is not configured"
        )

    params = [
        ("model", "nova-3"),
        ("language", "fa"),
        ("smart_format", "true"),
        ("punctuate", "true"),
        ("keyterm", "پاساژ"),
        ("keyterm", "کناف"),
        ("keyterm", "هاشمی")
    ]

    headers = {
        "Authorization": f"Token {DEEPGRAM_API_KEY}",
        "Content-Type": "audio/wav"
    }

    audio_data = wav_path.read_bytes()

    async with httpx.AsyncClient(timeout=180) as client:

        response = await client.post(
            DEEPGRAM_URL,
            params=params,
            headers=headers,
            content=audio_data
        )

    if response.status_code != 200:
        raise HTTPException(
            status_code=502,
            detail=f"Deepgram error: {response.text[:1000]}"
        )

    data = response.json()

    try:
        alternative = (
            data["results"]["channels"][0]["alternatives"][0]
        )

        transcript = alternative.get("transcript", "")
        confidence = alternative.get("confidence", 0)

    except (KeyError, IndexError, TypeError):
        raise HTTPException(
            status_code=502,
            detail="Invalid Deepgram response"
        )

    return {
        "text": transcript.strip(),
        "confidence": confidence,
        "language": "fa",
        "provider": "deepgram",
        "model": "nova-3"
    }


# =========================
# TRANSCRIBE VIDEO
# =========================

@app.post("/transcribe")
async def transcribe(
    video: UploadFile = File(...)
):

    job_id = str(uuid.uuid4())

    video_path = BASE / f"{job_id}.mp4"
    wav_path = BASE / f"{job_id}.wav"

    try:

        video_data = await video.read()

        if not video_data:
            raise HTTPException(
                status_code=400,
                detail="Empty video"
            )

        if len(video_data) > 100 * 1024 * 1024:
            raise HTTPException(
                status_code=413,
                detail="Video is larger than 100 MB"
            )

        video_path.write_bytes(video_data)

        await extract_audio(
            video_path,
            wav_path
        )

        result = await transcribe_deepgram(wav_path)

        return {
            "ok": True,
            "text": result["text"],
            "language": result["language"],
            "confidence": result["confidence"],
            "provider": result["provider"],
            "model": result["model"]
        }

    except HTTPException:
        raise

    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=str(e)
        )

    finally:

        for path in [video_path, wav_path]:
            try:
                if path.exists():
                    path.unlink()
            except Exception:
                pass


# =========================
# GROQ AI
# =========================

async def groq_chat(prompt: str):

    if not GROQ_API_KEY:
        raise HTTPException(
            status_code=500,
            detail="GROQ_API_KEY is not configured"
        )

    headers = {
        "Authorization": f"Bearer {GROQ_API_KEY}",
        "Content-Type": "application/json"
    }

    payload = {
        "model": "openai/gpt-oss-20b",
        "messages": [
            {
                "role": "system",
                "content": (
                    "تو دستیار حرفه‌ای تولید محتوای فارسی هستی. "
                    "فقط بر اساس اطلاعات واقعی ارائه‌شده پاسخ بده. "
                    "هیچ موضوع یا جزئیاتی را اختراع نکن."
                )
            },
            {
                "role": "user",
                "content": prompt
            }
        ],
        "temperature": 0.4
    }

    async with httpx.AsyncClient(timeout=120) as client:

        response = await client.post(
            GROQ_URL,
            headers=headers,
            json=payload
        )

    if response.status_code != 200:
        raise HTTPException(
            status_code=502,
            detail=f"Groq error: {response.text[:1000]}"
        )

    data = response.json()

    return data["choices"][0]["message"]["content"]


# =========================
# CONTENT GENERATION
# =========================

@app.post("/content")
async def generate_content(request: ContentRequest):

    transcript = request.transcript.strip()

    if not transcript:
        raise HTTPException(
            status_code=400,
            detail="Transcript is empty"
        )

    prompt = f"""
متن زیر پیاده‌سازی گفتار یک ویدئو است.

متن گفتار:
{transcript}

نام کسب‌وکار:
{request.business}

وظایف:

1. موضوع واقعی ویدئو را تشخیص بده.
2. یک ایده مناسب برای انتشار در اینستاگرام پیشنهاد بده.
3. یک کپشن جذاب و طبیعی فارسی بنویس.
4. هشتگ‌های مرتبط پیشنهاد بده.
5. اگر ویدئو درباره کناف نیست، به هیچ عنوان آن را به کناف ربط نده.
6. هیچ اطلاعاتی را که در متن وجود ندارد اختراع نکن.
7. اگر بخشی از متن نامفهوم است، درباره آن حدس قطعی نزن.

پاسخ را به صورت JSON با این ساختار بده:

{{
  "topic": "موضوع ویدئو",
  "idea": "ایده انتشار",
  "caption": "کپشن",
  "hashtags": ["هشتگ اول", "هشتگ دوم"]
}}
"""

    result = await groq_chat(prompt)

    try:
        start = result.find("{")
        end = result.rfind("}") + 1

        if start >= 0 and end > start:
            parsed = json.loads(result[start:end])
        else:
            parsed = {"result": result}

    except Exception:
        parsed = {"result": result}

    return {
        "ok": True,
        "content": parsed
    }


# =========================
# TEXT TO SPEECH
# =========================

@app.post("/tts")
async def text_to_speech(request: TTSRequest):

    text = request.text.strip()

    if not text:
        raise HTTPException(
            status_code=400,
            detail="Text is empty"
        )

    voices = [
        "fa-IR-DilaraNeural",
        "fa-IR-FaridNeural"
    ]

    if request.voice not in voices:
        raise HTTPException(
            status_code=400,
            detail="Invalid voice"
        )

    job_id = str(uuid.uuid4())

    audio_path = BASE / f"{job_id}.mp3"

    try:

        communicate = edge_tts.Communicate(
            text,
            request.voice
        )

        await communicate.save(str(audio_path))

        return FileResponse(
            audio_path,
            media_type="audio/mpeg",
            filename="knuaf_audio.mp3",
            background=None
        )

    except Exception as e:

        raise HTTPException(
            status_code=500,
            detail=f"TTS error: {str(e)}"
        )
