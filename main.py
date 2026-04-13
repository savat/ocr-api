from fastapi import FastAPI, UploadFile, File
from fastapi.responses import JSONResponse
import pytesseract
from PIL import Image
import io

app = FastAPI()

@app.get("/")
def home():
    return {"message": "OCR API is running! Use POST /ocr to upload an image."}

@app.post("/ocr")
async def ocr_image(file: UploadFile = File(...)):
  
    contents = await file.read()
    img = Image.open(io.BytesIO(contents))
    
    
    text = pytesseract.image_to_string(img, lang='eng+tha')
    
    return JSONResponse(content={"text": text.strip()})
