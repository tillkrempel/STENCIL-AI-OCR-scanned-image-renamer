# Stencil - AI PDF OCR & Smart Renamer Pipeline

An automated, hardened pipeline for ingesting scanned PDF documents, performing optical character recognition (OCR via **OCRmyPDF** / **Tesseract**), and applying structured file renaming using local Large Language Models (**Ollama** / **Gemma / Qwen**).

---

## 📑 Table of Contents

1. [How It Works](https://www.google.com/search?q=%23-how-it-works)
2. [Security & Prompt Injection Protection](https://www.google.com/search?q=%23-security--prompt-injection-protection)
3. [Folder Structure & Run Logic](https://www.google.com/search?q=%23-folder-structure--run-logic)
4. [Error Codes & Traceability](https://www.google.com/search?q=%23-error-codes--traceability)
5. [Setup Variants](https://www.google.com/search?q=%23-setup-variants)
* [Variant 1: Standard Setup (GPU / Auto-Detect)](https://www.google.com/search?q=%23variant-1-standard-setup-gpu--auto-detect)
* [Variant 2: Minimal Setup (Alpine & Inline Ollama)](https://www.google.com/search?q=%23variant-2-minimal-setup-alpine--inline-ollama)
* [Variant 3: Decoupled Setup (Client / Remote Server)](https://www.google.com/search?q=%23variant-3-decoupled-setup-client--remote-server)


6. [Core Scripts Source Code](https://www.google.com/search?q=%23-core-scripts-source-code)
* [`process.py`](https://www.google.com/search?q=%23processpy)
* [`run.sh`](https://www.google.com/search?q=%23runsh)
* [`detect_gpu.sh`](https://www.google.com/search?q=%23detect_gpush)
* [`configure_model.sh`](https://www.google.com/search?q=%23configure_modelsh)


7. [Environment Variables](https://www.google.com/search?q=%23-environment-variables)

---

## 📄 How It Works

1. **PDF Scan & OCR:** New PDFs in the `./data` directory are detected and augmented with an invisible text layer using `ocrmypdf` (`--skip-text --deskew`).
2. **Text Extraction:** `pdftotext` securely extracts text from the first pages of the file directly in memory.
3. **AI Metadata Analysis:** The local LLM reads the content and extracts date, sender, and subject in a structured format.
4. **Isolated Run Folders & Logging:** Each run creates its own `Run<N>` subdirectory containing log files, colored console output, and execution timing.
5. **Data Loss Prevention:** The primary document ID (original filename) is always retained as a suffix. Existing files are never overwritten.

---

## 🛡️ Security & Prompt Injection Protection

The system is hardened against malicious inputs and code execution attempts within scanned documents:

* **No Shell Execution:** `pdftotext` and `python3` are spawned without shell interpreting (`shell=False`). Document contents can never be executed as system commands.
* **Prompt Guarding:** Document content is explicitly encapsulated inside `<DOCUMENT_CONTENT_DATA>`. The system prompt strictly forces the model to ignore instructions found within the document text.
* **Structured Output Enforcement:** Ollama strictly enforces output delivery in `json` format.
* **Strict Sanitizing:** Extracted strings are filtered using regex (`[^a-zA-Z0-9_-]`). Path separators (`/`, `\`) are eliminated (**Path Traversal Protection**).

---

## 📂 Folder Structure & Run Logic

On every execution, the pipeline builds the following isolated structure inside the data directory:

```text
data/
├── 26072026113621.pdf                 <-- Source file in root directory
├── Run1/
│   ├── Run1.log                       <-- Detailed log with config & runtime info
│   ├── ocr/
│   │   └── 26072026113621.pdf         <-- Searchable PDF
│   └── renamed/
│       └── 2026-07-26_Telekom_Rechnung_26072026113621.pdf
├── Run2/
│   ├── Run2.log
│   ├── ocr/ ...

```

## 🚨 Error Codes & Traceability

If an error occurs during processing, the pipeline does not crash; instead, it gracefully aborts processing for the affected document.

To ensure **no documents are lost** and maintaining full visibility of their mapping to the source file in the root directory, the PDF is saved in the `renamed/` directory with a corresponding error prefix while retaining its **original primary ID** (source filename without `.pdf`):

| Error Code | Cause & Meaning | Trigger / Resolution |
| --- | --- | --- |
| `ERR01_NOTEXT_<ID>.pdf` | **No text extractable** | `pdftotext` could not extract usable text after the OCR step (e.g., empty document, heavily damaged scan, or corrupted PDF structure). |
| `ERR02_OLLAMA_UNREACHABLE_<ID>.pdf` | **API unreachable** | The Ollama container/server was not reachable at `OLLAMA_URL` during execution (e.g., network timeout, container still starting up, or wrong IP). |
| `ERR03_MODEL_ERROR_<ID>.pdf` | **Model / Validation Error** | The LLM did not return valid JSON, the response did not conform to the schema, or the prompt guard caught a prompt injection attempt / invalid content. |

---

### Traceability Guarantee (ID Traceability)

Every processed document retains its unique identifier regardless of the outcome (success or error).

* **Success Case (`SUCCESS`):**
`2026-07-26_Telekom_Rechnung_26072026113621.pdf`
*(Pattern: `<Date>_<Sender>_<Subject>_<Original-ID>.pdf`)*
* **Error Case (`ERROR`):**
`ERR01_NOTEXT_26072026113621.pdf`
*(Pattern: `<ErrorCode>_<Original-ID>.pdf`)*

This allows any file in the `renamed/` directory to be immediately matched to its source file in the root folder (`26072026113621.pdf`) and its detailed logs in `Run<N>/Run<N>.log` without searching.

---

## 🛠️ Setup Variants

### Required Project File Structure

```text
pdf-ocr-pipeline/
├── docker-compose.yml
├── Dockerfile
├── configure_model.sh
├── detect_gpu.sh
├── process.py
├── run.sh
└── data/             <-- Place source PDFs here

```

### Variant 1: Standard Setup (GPU / Auto-Detect)

Ideal for local workstations or servers with NVIDIA GPUs. Automatically detects available VRAM (`nvidia-smi` / Linux Sysfs / `/proc/meminfo`) and selects the appropriate model (`qwen2.5:3b`, `7b`, `14b`, or `gemma3:27b`).

#### `docker-compose.yml`

```yaml
services:
  ollama:
    image: ollama/ollama:latest
    container_name: ollama_service
    ports:
      - "11434:11434"
    volumes:
      - ollama_data:/root/.ollama
    restart: unless-stopped
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]

  ollama-pull:
    build: .
    container_name: ollama_model_pull
    depends_on:
      - ollama
    env_file:
      - .env
    volumes:
      - ./detect_gpu.sh:/detect_gpu.sh
    entrypoint: ["/bin/bash", "/detect_gpu.sh"]

  pdf-processor:
    build: .
    container_name: pdf_ocr_processor
    depends_on:
      ollama-pull:
        condition: service_completed_successfully
    env_file:
      - .env
    environment:
      - OLLAMA_URL=http://ollama:11434
    volumes:
      - ./data:/app/data

volumes:
  ollama_data:

```

* **Launch:**

```bash
chmod +x configure_model.sh detect_gpu.sh run.sh process.py
./configure_model.sh  # Interactive model selection menu (optional)
docker compose up --build

```

---

### Variant 2: Minimal Setup (Alpine & Inline Ollama)

Single-container setup designed for low-power hardware (e.g., Raspberry Pi or lightweight NAS servers). Consumes under 200 MB RAM at idle.

#### `docker-compose.minimal.yml`

```yaml
services:
  pdf-minimal:
    build:
      context: .
      dockerfile: Dockerfile.minimal
    container_name: pdf_ocr_minimal
    environment:
      - OLLAMA_MODEL=qwen2.5:0.5b
      - FILENAME_PATTERN=<YYYY-MM-DD>_<Sender>_<Subject>
      - OCR_LANG=deu
    volumes:
      - ./data:/app/data
      - ollama_min_data:/root/.ollama

volumes:
  ollama_min_data:

```

#### `Dockerfile.minimal`

```dockerfile
FROM python:3.11-alpine

RUN apk add --no-cache \
    poppler-utils \
    tesseract-ocr \
    tesseract-ocr-data-deu \
    ocrmypdf \
    curl \
    bash

WORKDIR /app

COPY process.py run.sh ./
RUN chmod +x run.sh process.py

RUN curl -fsSL https://ollama.com/install.sh | sh

CMD sh -c "ollama serve & sleep 3 && ollama pull $OLLAMA_MODEL && /app/run.sh"

```

* **Launch:**

```bash
docker compose -f docker-compose.minimal.yml up --build

```

---

### Variant 3: Decoupled Setup (Client / Remote Server)

Separates compute-heavy LLM inference on a remote GPU server from local PDF processing.

#### Server Side (`docker-compose.server.yml`)

```yaml
services:
  llm-server:
    image: ollama/ollama:latest
    container_name: remote_llm_server
    ports:
      - "11434:11434"
    environment:
      - OLLAMA_HOST=0.0.0.0
    volumes:
      - ollama_remote_data:/root/.ollama
    restart: unless-stopped
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]

volumes:
  ollama_remote_data:

```

#### Client Side (`docker-compose.client.yml`)

```yaml
services:
  pdf-client:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: pdf_ocr_client
    environment:
      - OLLAMA_URL=http://<REMOTE-SERVER-IP>:11434
      - OLLAMA_MODEL=qwen2.5:7b
      - FILENAME_PATTERN=<YYYY-MM-DD>_<Sender>_<Subject>
      - OCR_LANG=deu
    volumes:
      - ./data:/app/data

```

* **Launch:**

1. On the GPU server: `docker compose -f docker-compose.server.yml up -d`
2. On the local client machine: `docker compose -f docker-compose.client.yml up --build`

---

## ⚙️ Environment Variables

The pipeline can be configured using the following environment variables (defined in `.env` or in the respective `docker-compose.yml` file):

| Variable | Default Value | Description |
| --- | --- | --- |
| `OLLAMA_URL` | `http://ollama:11434` | Endpoint of the Ollama instance. |
| `OLLAMA_MODEL` | `qwen2.5:3b` | The LLM model to use. |
| `FILENAME_PATTERN` | `<YYYY-MM-DD>_<Sender>_<Subject>` | Pattern for the generated filename. |
| `OCR_LANG` | `deu` | Language for Tesseract OCR (`deu`, `eng`, `deu+eng`). |

---

## 📊 Sample Log File (`data/Run1/Run1.log`)

```text
========================================================================
 PROCESSING LOG - RUN ID: Run1
========================================================================
Start Timestamp : 2026-07-26 23:30:00
Run Directory   : /app/data/Run1
Ollama URL      : http://ollama:11434
Ollama Model    : qwen2.5:3b
Filename Pattern: <YYYY-MM-DD>_<Sender>_<Subject>
OCR Language    : deu
========================================================================

--- Processing File: 26072026113621.pdf (ID: 26072026113621) ---
  Source Path: /app/data/Run1/ocr/26072026113621.pdf
  Extracted Text Length: 1420 chars
  Target Destination: /app/data/Run1/renamed/2026-07-26_Telekom_Rechnung_26072026113621.pdf
  Status: SUCCESS

========================================================================
 PROCESSING SUMMARY - RUN ID: Run1
========================================================================
Start Timestamp       : 2026-07-26 23:30:00
End Timestamp         : 2026-07-26 23:30:04
Elapsed Time          : 4.12s (4.12 seconds)
Total Files Processed : 1
  - Successfully Renamed : 1
  - ERR01 (No Text)     : 0
  - ERR02 (Ollama Down) : 0
  - ERR03 (Model Error) : 0
========================================================================

```
