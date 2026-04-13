from fastapi import FastAPI, UploadFile, File
from fastapi.responses import JSONResponse
import pytesseract
from PIL import Image, ImageFilter, ImageEnhance
import io
import re
import numpy as np

app = FastAPI()

@app.get("/")
def home():
    return {"message": "OCR API is running! Use POST /ocr to upload an image."}

def preprocess_image(img):
    
    img = img.resize((img.width*3, img.height*3), Image.LANCZOS)
    
    
    img = img.convert('L')
    
    
    enhancer = ImageEnhance.Sharpness(img)
    img = enhancer.enhance(2.0)
    
    
    enhancer = ImageEnhance.Contrast(img)
    img = enhancer.enhance(1.5)
    
    
    img = img.filter(ImageFilter.MedianFilter(size=3))
    
    return img

@app.post("/ocr")
async def ocr_image(file: UploadFile = File(...)):
    contents = await file.read()
    img = Image.open(io.BytesIO(contents))
    
    
    img = preprocess_image(img)
    
    
    custom_config = r'--oem 3 --psm 6 -c tessedit_char_whitelist=กขฃคฆงจฉชซฌญฎฏฐฑฒณดตถทธนบปผฝพฟภมยรลวศษสหฬอฮฯะาิีึืุูเแโใไๅๆ็่้๊๋์abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789:.()- '
    
    text = pytesseract.image_to_string(img, lang='tha+eng', config=custom_config)
    
    
    cleaned_text = re.sub(r'\s+', ' ', text)
    cleaned_text = re.sub(r' ([.,!?;:])', r'\1', cleaned_text)
    cleaned_text = cleaned_text.strip()
    
    return JSONResponse(content={"text": cleaned_text})
