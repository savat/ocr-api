from fastapi import FastAPI, UploadFile, File
from fastapi.responses import JSONResponse
import pytesseract
from PIL import Image
import io
import re

app = FastAPI()

@app.get("/")
def home():
    return {"message": "OCR API is running! Use POST /ocr to upload an image."}

@app.post("/ocr")
async def ocr_image(file: UploadFile = File(...)):
    contents = await file.read()
    img = Image.open(io.BytesIO(contents))
    
    
    img = img.resize((int(img.width*1.5), int(img.height*1.5)), Image.LANCZOS)
    
    
    text = pytesseract.image_to_string(img, lang='tha+eng')
    
    
    cleaned_text = re.sub(r'\s+', ' ', text).strip()
    
    return JSONResponse(content={"text": cleaned_text})
