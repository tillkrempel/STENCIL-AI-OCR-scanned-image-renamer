#!/bin/bash
set -euo pipefail

LANG_OCR="${OCR_LANG:-deu}"
DATA_DIR="/app/data"

# Farbunterstützung für Shell-Ausgaben
if [ -t 1 ]; then
    RED='\033[1;31m'
    YELLOW='\033[1;33m'
    GREEN='\033[0;32m'
    BLUE='\033[1;34m'
    NC='\033[0m'
else
    RED=''
    YELLOW=''
    GREEN=''
    BLUE=''
    NC=''
fi

# 1. Fortlaufende Run-Nummer & Run-ID ermitteln
max_run=0
for dir in "$DATA_DIR"/Run*; do
    if [ -d "$dir" ]; then
        dir_name=$(basename "$dir")
        num="${dir_name#Run}"
        if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -gt "$max_run" ]; then
            max_run=$num
        fi
    fi
done

next_run=$((max_run + 1))
RUN_ID="Run$next_run"
CURRENT_RUN_DIR="$DATA_DIR/$RUN_ID"
OCR_DIR="$CURRENT_RUN_DIR/ocr"

mkdir -p "$OCR_DIR"

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}Starte Durchlauf: $RUN_ID${NC}"
echo -e "${BLUE}Zielverzeichnis:  $CURRENT_RUN_DIR${NC}"
echo -e "${BLUE}==================================================${NC}"

# 2. OCRmyPDF ausführen
find "$DATA_DIR" -maxdepth 1 -type f -iname "*.pdf" -print0 | while IFS= read -r -d '' filepath; do
    filename=$(basename "$filepath")
    output_filepath="$OCR_DIR/$filename"

    if [ ! -f "$output_filepath" ]; then
        echo -e "[OCR] Processing: $filepath -> $output_filepath"
        if ! ocrmypdf -l "$LANG_OCR" --skip-text --deskew "$filepath" "$output_filepath"; then
            echo -e "${YELLOW}[WARNING] OCRmyPDF gab eine Warnung/einen Fehler für $filepath zurück.${NC}"
        fi
    fi
done

echo ""

# 3. Python-Verarbeitung & Logging starten
python3 /app/process.py "$CURRENT_RUN_DIR"