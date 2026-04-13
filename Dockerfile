
FROM ubuntu:22.04 as tesseract-layer

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y tesseract-ocr tesseract-ocr-tha && \
    rm -rf /var/lib/apt/lists/*


FROM python:3.11-slim


COPY --from=tesseract-layer /usr/bin/tesseract /usr/bin/tesseract
COPY --from=tesseract-layer /usr/share/tesseract-ocr /usr/share/tesseract-ocr
COPY --from=tesseract-layer /usr/lib/x86_64-linux-gnu /usr/lib/x86_64-linux-gnu

ENV TESSERACT_PATH=/usr/bin/tesseract

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "10000"]
