from fastapi import FastAPI, UploadFile, File
from fastapi.responses import JSONResponse
import pytesseract
from PIL import Image
import io
import re

app = FastAPI()

@app.get("/")
def home():
    return {"message": "Tesseract OCR API"}

@app.post("/ocr")
async def ocr_image(file: UploadFile = File(...)):
    contents = await file.read()
    img = Image.open(io.BytesIO(contents))
    text = pytesseract.image_to_string(img, lang='tha+eng')
    cleaned = re.sub(r'\s+', ' ', text).strip()
    return JSONResponse(content={"text": cleaned})
