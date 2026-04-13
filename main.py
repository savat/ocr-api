from fastapi import FastAPI, UploadFile, File
from fastapi.responses import JSONResponse
from paddleocr import PaddleOCR
from PIL import Image
import numpy as np
import io

app = FastAPI()


ocr = PaddleOCR(lang='th', use_angle_cls=True, show_log=False)

@app.get("/")
def home():
    return {"message": "PaddleOCR API is running! Use POST /ocr to upload an image."}

@app.post("/ocr")
async def ocr_image(file: UploadFile = File(...)):
    contents = await file.read()
    img = Image.open(io.BytesIO(contents))
    img_np = np.array(img)
    
    result = ocr.ocr(img_np)
    
    if result and result[0]:
        texts = [line[1][0] for line in result[0]]
        full_text = '\n'.join(texts)
    else:
        full_text = ""
    
    return JSONResponse(content={"text": full_text})
