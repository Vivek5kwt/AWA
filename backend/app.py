from fastapi import FastAPI, UploadFile, File
from fastapi import FastAPI, UploadFile, File
from fastapi.responses import JSONResponse
import speech_recognition as sr
import tempfile
import os

app = FastAPI()


def _detect_language(text: str) -> str:
    def contains_range(start: int, end: int) -> bool:
        return any(start <= ord(ch) <= end for ch in text)

    if contains_range(0x0A00, 0x0A7F):
        return "pa-IN"
    if contains_range(0x0A80, 0x0AFF):
        return "gu-IN"
    if contains_range(0x0B80, 0x0BFF):
        return "ta-IN"
    if contains_range(0x0980, 0x09FF):
        return "bn-IN"
    if contains_range(0x0600, 0x06FF):
        return "Urdu"
    if contains_range(0x0900, 0x097F):
        marathi_chars = [0x0933, 0x0931, 0x0934, 0x0972, 0x0911, 0x090D]
        if any(ord(c) in marathi_chars for c in text):
            return "mr-IN"
        return "hi-IN"
    return "en"


@app.post("/detect_language/")
async def detect_language(audio: UploadFile = File(...)):
    with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as tmp:
        tmp.write(await audio.read())
        tmp_path = tmp.name

    r = sr.Recognizer()
    try:
        with sr.AudioFile(tmp_path) as source:
            data = r.record(source)
        text = r.recognize_google(data)
    except Exception:
        text = ""

    os.remove(tmp_path)

    lang = _detect_language(text)
    return JSONResponse({"language": lang})
