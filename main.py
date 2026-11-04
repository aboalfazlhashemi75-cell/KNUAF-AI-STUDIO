import os, uuid
from pathlib import Path
from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel
import edge_tts
from faster_whisper import WhisperModel
import httpx

BASE = Path(os.getenv("KNUAF_DATA_DIR", "./data")).resolve()
BASE.mkdir(parents=True, exist_ok=True)
app = FastAPI(title="KNUAF AI STUDIO API", version="0.1.0")
whisper_model = None

def get_whisper():
    global whisper_model
    if whisper_model is None:
        whisper_model = WhisperModel("small", device="cpu", compute_type="int8")
    return whisper_model

async def save_upload(upload: UploadFile) -> Path:
    suffix = Path(upload.filename or "clip.mp4").suffix or ".mp4"
    path = BASE / f"{uuid.uuid4().hex}{suffix}"
    with path.open("wb") as f:
        while chunk := await upload.read(1024 * 1024):
            f.write(chunk)
    return path

@app.get("/health")
def health():
    return {"ok": True, "service": "KNUAF AI STUDIO"}

@app.post("/transcribe")
async def transcribe(video: UploadFile = File(...)):
    path = await save_upload(video)
    try:
        model = get_whisper()
        segments, info = model.transcribe(str(path), language="fa", vad_filter=True)
        items, full = [], []
        for seg in segments:
            text = seg.text.strip()
            full.append(text)
            items.append({"start": round(seg.start, 2), "end": round(seg.end, 2), "text": text})
        return {"language": info.language, "text": " ".join(full), "segments": items}
    except Exception as e:
        raise HTTPException(500, f"Transcription failed: {e}")
    finally:
        path.unlink(missing_ok=True)

class TTSRequest(BaseModel):
    text: str
    voice: str = "fa-IR-FaridNeural"

@app.post("/tts")
async def text_to_speech(payload: TTSRequest):
    if not payload.text.strip():
        raise HTTPException(400, "Text is required")
    file_id = uuid.uuid4().hex
    out = BASE / f"{file_id}.mp3"
    try:
        await edge_tts.Communicate(payload.text, payload.voice).save(str(out))
        return FileResponse(out, media_type="audio/mpeg", filename="knuaf-narration.mp3",
                            headers={"X-Audio-File": file_id})
    except Exception as e:
        raise HTTPException(500, f"TTS failed: {e}")

@app.post("/content")
async def content(
    video: UploadFile = File(...),
    transcript: str = Form(""),
    business: str = Form("interior design and drywall"),
    platform: str = Form("Instagram Reels"),
    language: str = Form("Persian"),
):
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        raise HTTPException(503, "Set OPENAI_API_KEY on the backend server first.")
    path = await save_upload(video)
    try:
        prompt = (
            "You are a Persian social-video producer for a Knauf and interior-decoration contractor.\n"
            f"Business: {business}\nPlatform: {platform}\nTranscript: {transcript or '(not supplied)'}\n"
            "Write in Persian. Provide three reel concepts with opening hooks and suggested shot order. "
            "Do not claim scenes exist unless supported by transcript. Then write one natural professional "
            "caption with a clear call to action and 8-12 relevant hashtags. Avoid fake claims and promises of virality."
        )
        async with httpx.AsyncClient(timeout=90) as client:
            response = await client.post(
                os.getenv("OPENAI_BASE_URL", "https://api.openai.com/v1") + "/chat/completions",
                headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
                json={"model": os.getenv("OPENAI_MODEL", "gpt-4o-mini"),
                      "messages": [{"role": "user", "content": prompt}], "temperature": 0.7},
            )
        response.raise_for_status()
        result = response.json()["choices"][0]["message"]["content"]
        return {"ideas": result, "caption": ""}
    except httpx.HTTPError as e:
        raise HTTPException(502, f"AI provider error: {e}")
    finally:
        path.unlink(missing_ok=True)
