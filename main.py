from fastapi import FastAPI, UploadFile, File
from fastapi.responses import JSONResponse
import pytesseract
import cv2
import numpy as np
import re

app = FastAPI()

@app.get("/")
def home():
    return {"message": "OpenChat Verification API"}



def crop_username(img):
    h, w = img.shape[:2]
    return img[int(h*0.12):int(h*0.32), int(w*0.2):int(w*0.8)]



def crop_groupname(img):
    h, w = img.shape[:2]
    return img[int(h*0.32):int(h*0.50), int(w*0.1):int(w*0.9)]



def preprocess(img):
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    gray = cv2.resize(gray, None, fx=2, fy=2, interpolation=cv2.INTER_CUBIC)
    _, thresh = cv2.threshold(gray, 150, 255, cv2.THRESH_BINARY)
    return thresh



def ocr(img):
    config = r'--oem 3 --psm 6'
    text = pytesseract.image_to_string(img, lang='tha+eng', config=config)
    return re.sub(r'\s+', ' ', text).strip()


@app.post("/verify")
async def verify(file: UploadFile = File(...)):
    contents = await file.read()

    nparr = np.frombuffer(contents, np.uint8)
    img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

    
    user_crop = preprocess(crop_username(img))
    user_text = ocr(user_crop)

    
    user_match = re.search(r'โปรไฟล์\s*(.*?)$', user_text)
    username = user_match.group(1) if user_match else user_text

    
    group_crop = preprocess(crop_groupname(img))
    group_text = ocr(group_crop)

    group_match = re.search(r'ชื่อโอเพนแชท\s*(.*?)$', group_text)
    groupname = group_match.group(1) if group_match else group_text

    
    valid = False

    
    if "Sports" in groupname:
        valid = True

    return JSONResponse({
        "username": username,
        "groupname": groupname,
        "valid": valid
    })
