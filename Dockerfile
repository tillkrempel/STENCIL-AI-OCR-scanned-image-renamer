FROM python:3.11-slim

# Installiere notwendige OCR- und System-Tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    ocrmypdf \
    tesseract-ocr-deu \
    poppler-utils \
    curl \
    pciutils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY process.py run.sh ./
RUN chmod +x run.sh process.py

ENTRYPOINT ["/app/run.sh"]