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
    
    
    custom_config = r'--oem 3 --psm 6'
    
    
    text = pytesseract.image_to_string(
        img, 
        lang='tha+eng',  
        config=custom_config
    )
    
    
    cleaned_text = re.sub(r'\s+', ' ', text)  
    cleaned_text = re.sub(r' ([.,!?;:])', r'\1', cleaned_text)  
    cleaned_text = cleaned_text.strip()
    
    return JSONResponse(content={"text": cleaned_text})
