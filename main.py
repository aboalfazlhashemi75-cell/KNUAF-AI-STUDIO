import os
import json
import uuid
import re
from pathlib import Path

import httpx
import edge_tts

from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel


# -----------------------------
# SETTINGS
# -----------------------------

BASE = Path(os.getenv("KNUAF_DATA_DIR", "./data")).resolve()
BASE.mkdir(parents=True, exist_ok=True)

GROQ_API_KEY = os.getenv("GROQ_API_KEY")

GROQ_URL = "https://api.groq.com/openai/v1"

app = FastAPI(
    title="KNUAF AI STUDIO API",
    version="0.4.1"
)


# -----------------------------
# HEALTH
# -----------------------------

@app.get("/")
async def root():
    return {
        "service": "KNUAF AI STUDIO",
        "status": "online",
        "version": "0.4.1"
    }


@app.get("/health")
async def health():
    return {
        "ok": True,
        "service": "KNUAF AI STUDIO",
        "version": "0.4.1"
    }


# -----------------------------
# HELPERS
# -----------------------------

def check_api_key():
    if not GROQ_API_KEY:
        raise HTTPException(
            status_code=500,
            detail="GROQ_API_KEY is not configured."
        )


def extract_json(text):
    text = text.strip()

    text = re.sub(
        r"^```(?:json)?\s*",
        "",
        text,
        flags=re.IGNORECASE
    )

    text = re.sub(r"\s*```$", "", text)

    try:
        return json.loads(text)
    except json.JSONDecodeError:
        start = text.find("{")
        end = text.rfind("}")

        if start >= 0 and end > start:
            return json.loads(text[start:end + 1])

        raise ValueError("AI did not return valid JSON.")


async def groq_chat(prompt):
    check_api_key()

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
                    "You are an expert social media content creator. "
                    "Follow the user's instructions exactly. "
                    "Never invent facts or events."
                )
            },
            {
                "role": "user",
                "content": prompt
            }
        ],
        "temperature": 0.4,
        "max_completion_tokens": 3000
    }

    async with httpx.AsyncClient(timeout=120) as client:
        response = await client.post(
            f"{GROQ_URL}/chat/completions",
            headers=headers,
            json=payload
        )

    if response.status_code != 200:
        raise HTTPException(
            status_code=502,
            detail={
                "message": "Groq AI request failed",
                "status": response.status_code,
                "response": response.text[:1500]
            }
        )

    result = response.json()

    try:
        return result["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError):
        raise HTTPException(
            status_code=502,
            detail="Invalid response from AI provider."
        )


# -----------------------------
# TRANSCRIBE VIDEO
# -----------------------------

@app.post("/transcribe")
async def transcribe(
    video: UploadFile = File(...)
):
    check_api_key()

    filename = video.filename or "video.mp4"
    extension = Path(filename).suffix or ".mp4"

    temp_path = BASE / f"{uuid.uuid4()}{extension}"

    try:
        content = await video.read()

        if not content:
            raise HTTPException(
                status_code=400,
                detail="Uploaded file is empty."
            )

        if len(content) > 100 * 1024 * 1024:
            raise HTTPException(
                status_code=413,
                detail="File is larger than 100 MB."
            )

        temp_path.write_bytes(content)

        headers = {
            "Authorization": f"Bearer {GROQ_API_KEY}"
        }

        files = {
            "file": (
                filename,
                content,
                video.content_type or "video/mp4"
            )
        }

        data = {
            "model": "whisper-large-v3",
            "language": "fa",
            "response_format": "verbose_json",
            "temperature": "0",
            "prompt": (
                "این فایل شامل گفت‌وگوی فارسی محاوره‌ای است. "
                "کلمات را دقیق و مطابق صدای واقعی بنویس. "
                "جملات روزمره، شوخی، مکالمه دو نفره و "
                "اصطلاحات فارسی را حفظ کن. "
                "کلمات نامفهوم را حدس نزن و چیزی نساز. "
                "متن را به زبان فارسی و با نگارش طبیعی بنویس."
            )
        }

        async with httpx.AsyncClient(timeout=180) as client:
            response = await client.post(
                f"{GROQ_URL}/audio/transcriptions",
                headers=headers,
                files=files,
                data=data
            )

        if response.status_code != 200:
            raise HTTPException(
                status_code=502,
                detail={
                    "message": "Transcription failed",
                    "response": response.text[:1500]
                }
            )

        result = response.json()

        return {
            "ok": True,
            "text": result.get("text", ""),
            "language": result.get("language", "fa")
        }

    finally:
        if temp_path.exists():
            temp_path.unlink()


# -----------------------------
# GENERATE CONTENT
# -----------------------------

@app.post("/content")
async def generate_content(
    video: UploadFile = File(...),
    transcript: str = Form(""),
    business: str = Form(
        "گروه دکوراسیون داخلی هاشمی"
    ),
    platform: str = Form("Instagram"),
    language: str = Form("Persian")
):

    transcript = transcript.strip()
    business = business.strip()
    platform = platform.strip()
    language = language.strip()

    if len(transcript) > 15000:
        transcript = transcript[:15000]

    if not transcript:
        return {
            "ok": True,
            "needs_more_info": True,
            "message": (
                "متن گفتار فیلم خالی است. "
                "لطفاً موضوع فیلم یا توضیح صحنه‌های آن را وارد کنید."
            ),
            "ideas": [],
            "caption": ""
        }

    prompt = f"""
You are a professional social media content strategist.

Your task is to create social media content based on the ACTUAL SUBJECT
of the video's spoken transcript.

IMPORTANT RULES:

1. The transcript is the primary source for identifying the video's topic.

2. Do NOT automatically make every video about Knauf,
construction, interior decoration, renovation or lighting.

3. If the transcript is about cooking, travel, cars, daily life,
entertainment, education, business or any other subject,
create content about THAT subject.

4. Business information is only background context.
It must NEVER override the actual subject of the transcript.

5. Never pretend that an unrelated video is a Knauf project.

6. Never invent customers, locations, projects, measurements,
prices, events, people or conversations.

7. You have NOT visually inspected the video.
You only have its transcript.

8. If the transcript is unclear or incomplete,
do not confidently guess the subject.

9. If the transcript clearly identifies a subject unrelated
to the business, create content about that subject.

10. Write naturally in the requested language.

BUSINESS BACKGROUND:
{business}

PLATFORM:
{platform}

OUTPUT LANGUAGE:
{language}

ACTUAL VIDEO TRANSCRIPT:
{transcript}

Return ONLY valid JSON.

Use exactly this structure:

{{
  "needs_more_info": false,
  "message": "",
  "detected_topic": "The actual subject identified from the transcript",
  "ideas": [
    {{
      "title": "Idea title",
      "hook": "Opening hook",
      "shot_order": [
        "Suggested shot 1",
        "Suggested shot 2",
        "Suggested shot 3"
      ],
      "editing_tip": "Editing suggestion"
    }},
    {{
      "title": "Idea title",
      "hook": "Opening hook",
      "shot_order": [
        "Suggested shot 1",
        "Suggested shot 2",
        "Suggested shot 3"
      ],
      "editing_tip": "Editing suggestion"
    }},
    {{
      "title": "Idea title",
      "hook": "Opening hook",
      "shot_order": [
        "Suggested shot 1",
        "Suggested shot 2",
        "Suggested shot 3"
      ],
      "editing_tip": "Editing suggestion"
    }}
  ],
  "caption": "Complete social media caption with relevant hashtags"
}}

All ideas must be relevant to the actual transcript.

If the transcript does not provide enough information,
return:

{{
  "needs_more_info": true,
  "message": "Please describe the video's subject.",
  "detected_topic": "",
  "ideas": [],
  "caption": ""
}}
"""

    ai_text = await groq_chat(prompt)

    try:
        parsed = extract_json(ai_text)
    except Exception:
        raise HTTPException(
            status_code=502,
            detail={
                "message": "Could not parse AI response.",
                "ai_response": ai_text[:2000]
            }
        )

    return {
        "ok": True,
        "needs_more_info": parsed.get(
            "needs_more_info", False
        ),
        "message": parsed.get("message", ""),
        "detected_topic": parsed.get(
            "detected_topic", ""
        ),
        "ideas": parsed.get("ideas", []),
        "caption": parsed.get("caption", "")
    }


# -----------------------------
# TEXT TO SPEECH
# -----------------------------

class TTSRequest(BaseModel):
    text: str
    voice: str = "fa-IR-FaridNeural"


@app.post("/tts")
async def text_to_speech(request: TTSRequest):

    text = request.text.strip()

    if not text:
        raise HTTPException(
            status_code=400,
            detail="Text cannot be empty."
        )

    if len(text) > 5000:
        raise HTTPException(
            status_code=400,
            detail="Text is too long."
        )

    allowed_voices = [
        "fa-IR-FaridNeural",
        "fa-IR-DilaraNeural"
    ]

    if request.voice not in allowed_voices:
        raise HTTPException(
            status_code=400,
            detail="Unsupported voice."
        )

    filename = f"{uuid.uuid4()}.mp3"
    output_path = BASE / filename

    try:
        communicate = edge_tts.Communicate(
            text,
            request.voice
        )

        await communicate.save(str(output_path))

        return FileResponse(
            path=output_path,
            media_type="audio/mpeg",
            filename=filename
        )

    except Exception as error:
        raise HTTPException(
            status_code=500,
            detail=f"TTS failed: {str(error)}"
        )
