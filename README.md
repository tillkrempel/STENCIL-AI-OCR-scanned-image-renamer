# AI PDF OCR & Smart Renamer Pipeline

Eine automatisierte, gehärtete Pipeline zum Einlesen gescannter PDF-Dokumente, Durchführen von Texterkennung (OCR via **OCRmyPDF** / **Tesseract**) und strukturierter Dateibenennung mithilfe lokaler Large Language Models (**Ollama** / **Gemma / Qwen**).

---

## 📑 Inhaltsverzeichnis

1. [Funktionsweise](#-funktionsweise)
2. [Sicherheit & Prompt Injection Protection](#-sicherheit--prompt-injection-protection)
3. [Ordnerstruktur & Run-Logik](#-ordnerstruktur--run-logik)
4. [Fehlercodes & Verfolgbarkeit](#-fehlercodes--verfolgbarkeit)
5. [Setup-Varianten](#-setup-varianten)
   * [Variante 1: Standard-Setup (GPU / Auto-Detect)](#variante-1-standard-setup-gpu--auto-detect)
   * [Variante 2: Minimal-Setup (Alpine & Inline Ollama)](#variante-2-minimal-setup-alpine--inline-ollama)
   * [Variante 3: Decoupled Setup (Client / Remote Server)](#variante-3-decoupled-setup-client--remote-server)
6. [Quellcode der Kernskripte](#-quellcode-der-kernskripte)
   * [`process.py`](#processpy)
   * [`run.sh`](#runsh)
   * [`detect_gpu.sh`](#detect_gpush)
   * [`configure_model.sh`](#configure_modelsh)
7. [Umgebungsvariablen](#-umgebungsvariablen)

---

## 📄 Funktionsweise

1. **PDF Scan & OCR:** Neue PDFs im Ordner `./data` werden erfasst und mittels `ocrmypdf` um eine unsichtbare Textschicht ergänzt (`--skip-text --deskew`).
2. **Text-Extraktion:** `pdftotext` zieht den Text aus den ersten Seiten der Datei sicher im Speicher aus.
3. **AI-Metadaten-Analyse:** Das lokale LLM liest den Inhalt und extrahiert strukturiert Datum, Absender und Betreff.
4. **Isolierte Run-Ordner & Protokollierung:** Jeder Durchlauf erzeugt ein eigenes Unterverzeichnis `Run<N>` mit Logdatei, Farbausgabe auf der Konsole und Zeitmessung.
5. **Schutz vor Datenverlust:** Die primäre Dokumenten-ID (ursprünglicher Dateiname) bleibt immer als Suffix erhalten. Existierende Dateien werden nicht überschrieben.

---

## 🛡️ Sicherheit & Prompt Injection Protection

Das System ist gegen bösartige Eingaben und Code-Execution-Versuche in gescannten Dokumenten gehärtet:

* **No Shell Execution:** `pdftotext` und `python3` werden ohne Shell-Interpreting (`shell=False`) gestartet. Dokumenteninhalte können niemals als Systembefehle ausgeführt werden.
* **Prompt Guarding:** Der Dokumenteninhalt wird explizit in `<DOCUMENT_CONTENT_DATA>` gekapselt. Der System-Prompt zwingt das Modell, Anweisungen im Text strikt zu ignorieren.
* **Structured Output Enforcement:** Ollama liefert die Metadaten erzwungen im strukturierten `json`-Format.
* **Strict Sanitizing:** Extrahierte Strings werden per Regex (`[^a-zA-Z0-9_-]`) gefiltert. Pfadtrennzeichen (`/`, `\`) werden eliminiert (**Path-Traversal-Schutz**).

---

## 📂 Ordnerstruktur & Run-Logik

Bei jedem Ausführen baut die Pipeline folgende isolierte Struktur im Datenordner auf:

```text
data/
├── 26072026113621.pdf                 <-- Quell-Datei im Stammverzeichnis
├── Run1/
│   ├── Run1.log                       <-- Ausführliches Protokoll mit Config & Laufzeit
│   ├── ocr/
│   │   └── 26072026113621.pdf         <-- Durchsuchbares PDF
│   └── renamed/
│       └── 2026-07-26_Telekom_Rechnung_26072026113621.pdf
├── Run2/
│   ├── Run2.log
│   ├── ocr/ ...
```

## 🚨 Fehlercodes & Verfolgbarkeit

Sollte während der Verarbeitung ein Fehler auftreten, schlägt die Pipeline nicht fehl, sondern bricht die Verarbeitung des betroffenen Dokuments kontrolliert ab. 

Damit **keine Dokumente verloren gehen** und die Zuordnung zur Quell-Datei im Stammverzeichnis transparent bleibt, wird das PDF im Ordner `renamed/` unter Beibehaltung der **ursprünglichen Primär-ID** (Dateiname der Quell-Datei ohne `.pdf`) mit einem entsprechenden Fehler-Präfix gespeichert:

| Fehlercode | Ursache & Bedeutung | Auslöser / Abhilfe |
| :--- | :--- | :--- |
| `ERR01_NOTEXT_<ID>.pdf` | **Kein Text extrahierbar** | `pdftotext` konnte nach dem OCR-Schritt keinen verwertbaren Text auslesen (z. B. leeres Dokument, stark beschädigter Scan oder fehlerhafte PDF-Struktur). |
| `ERR02_OLLAMA_UNREACHABLE_<ID>.pdf` | **API nicht erreichbar** | Der Ollama-Container/Server war während des Aufrufs nicht unter `OLLAMA_URL` erreichbar (z. B. Netzwerk-Timeout, Container noch im Startvorgang oder falsche IP). |
| `ERR03_MODEL_ERROR_<ID>.pdf` | **Modell-/Validierungsfehler** | Das LLM hat kein gültiges JSON zurückgeliefert, der Response entsprach nicht dem Schema, oder der Prompt Guard hat eine versuchte Prompt Injection / ungültige Inhalte abgefangen. |

---

### Verfolgbarkeits-Garantie (ID-Traceability)

Jedes verarbeitete Dokument behält unabhängig vom Ausgang (Erfolg oder Fehler) seine eindeutige Kennung. 

* **Erfolgsfall (`SUCCESS`):**  
  `2026-07-26_Telekom_Rechnung_26072026113621.pdf`  
  *(Muster: `<Datum>_<Sender>_<Betreff>_<Original-ID>.pdf`)*

* **Fehlerfall (`ERROR`):**  
  `ERR01_NOTEXT_26072026113621.pdf`  
  *(Muster: `<Fehlercode>_<Original-ID>.pdf`)*

Dadurch lässt sich im Ordner `renamed/` jede Datei ohne Suchen sofort der ursprünglichen Datei im Stammverzeichnis (`26072026113621.pdf`) sowie den Detail-Logs im jeweiligen `Run<N>/Run<N>.log` zuordnen.

## 🛠️ Setup-Varianten

### Erforderliche Dateistruktur im Projekt
```text
pdf-ocr-pipeline/
├── docker-compose.yml
├── Dockerfile
├── configure_model.sh
├── detect_gpu.sh
├── process.py
├── run.sh
└── data/             <-- Quell-PDFs hier ablegen
```

### Variante 1: Standard-Setup (GPU / Auto-Detect)

Ideal für lokale Rechner oder Server mit NVIDIA-GPU. Ermittelt VRAM automatisch (`nvidia-smi` / Linux Sysfs / `/proc/meminfo`) und wählt das passende Modell (`qwen2.5:3b`, `7b`, `14b` oder `gemma3:27b`).

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

* **Starten:**
```bash
chmod +x configure_model.sh detect_gpu.sh run.sh process.py
./configure_model.sh  # Interaktiver Auswahldialog (optional)
docker compose up --build

```



---

### Variante 2: Minimal-Setup (Alpine & Inline Ollama)

Single-Container-Setup für schwache Hardware (z. B. Raspberry Pi oder kleinen NAS-Server). Benötigt unter 200 MB RAM im Leerlauf.

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

RUN curl -fsSL [https://ollama.com/install.sh](https://ollama.com/install.sh) | sh

CMD sh -c "ollama serve & sleep 3 && ollama pull $OLLAMA_MODEL && /app/run.sh"

```

* **Starten:**
```bash
docker compose -f docker-compose.minimal.yml up --build

```



---

### Variante 3: Decoupled Setup (Client / Remote Server)

Trennt die rechenintensive Inferenz auf einem externen GPU-Server von der lokalen PDF-Verarbeitung.

#### Server-Seite (`docker-compose.server.yml`)

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

#### Client-Seite (`docker-compose.client.yml`)

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

* **Starten:**
1. Auf dem GPU-Server: `docker compose -f docker-compose.server.yml up -d`
2. Auf der lokalen Client-Maschine: `docker compose -f docker-compose.client.yml up --build`



---

## ⚙️ Umgebungsvariablen

Die Pipeline lässt sich über folgende Umgebungsvariablen (in `.env` oder der jeweiligen `docker-compose.yml`) anpassen:

| Variable | Default-Wert | Beschreibung |
| --- | --- | --- |
| `OLLAMA_URL` | `http://ollama:11434` | Endpoint der Ollama-Instanz. |
| `OLLAMA_MODEL` | `qwen2.5:3b` | Das zu verwendende LLM-Modell. |
| `FILENAME_PATTERN` | `<YYYY-MM-DD>_<Sender>_<Subject>` | Muster für den generierten Dateinamen. |
| `OCR_LANG` | `deu` | Sprache für Tesseract OCR (`deu`, `eng`, `deu+eng`). |

---

## 📊 Beispiel-Logdatei (`data/Run1/Run1.log`)

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
