#!/bin/bash

ENV_FILE=".env"

# VRAM-Erkennungsfunktion
get_vram() {
    if command -v nvidia-smi &> /dev/null; then
        vram=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n 1 | tr -d '[:space:]')
        if [[ "$vram" =~ ^[0-9]+$ ]] && [ "$vram" -gt 0 ]; then
            echo "$vram"
            return
        fi
    fi
    echo "0"
}

VRAM_MB=$(get_vram)
VRAM_GB=$((VRAM_MB / 1024))

RECOMMENDED_MODEL="qwen2.5:3b"

if [ "$VRAM_GB" -ge 20 ]; then
    RECOMMENDED_MODEL="gemma3:27b"
elif [ "$VRAM_GB" -ge 10 ]; then
    RECOMMENDED_MODEL="qwen2.5:14b"
elif [ "$VRAM_GB" -ge 6 ]; then
    RECOMMENDED_MODEL="qwen2.5:7b"
else
    RECOMMENDED_MODEL="qwen2.5:3b"
fi

echo "=================================================="
echo "         Ollama Modell Konfigurator               "
echo "=================================================="

if [ "$VRAM_MB" -gt 0 ]; then
    echo "[+] NVIDIA GPU erkannt: ${VRAM_GB} GB VRAM (${VRAM_MB} MB)"
else
    echo "[!] Keine NVIDIA GPU erkannt (oder macOS / AMD / CPU)."
fi

echo "[i] Empfohlenes Modell für dein System: $RECOMMENDED_MODEL"
echo "=================================================="
echo ""
echo "Bitte wähle das zu nutzende Ollama-Modell:"
echo ""
echo "  1) qwen2.5:3b    (~1.9 GB) -> Leicht & Schnell (Ideal für CPU / <6 GB RAM)"
echo "  2) qwen2.5:7b    (~4.7 GB) -> Balanced (Sehr gut für 6-10 GB VRAM/RAM)"
echo "  3) qwen2.5:14b   (~9.0 GB) -> Hohe Präzision (Benötigt >= 12 GB VRAM/RAM)"
echo "  4) gemma3:27b    (~16  GB) -> Max. Genauigkeit (Benötigt >= 20 GB VRAM/RAM)"
echo "  5) Auto-Detect   (Nutze dynamisch: $RECOMMENDED_MODEL)"
echo ""

read -p "Auswahl treffen [1-5] (Default: 5): " choice

case $choice in
    1) SELECTED_MODEL="qwen2.5:3b" ;;
    2) SELECTED_MODEL="qwen2.5:7b" ;;
    3) SELECTED_MODEL="qwen2.5:14b" ;;
    4) SELECTED_MODEL="gemma3:27b" ;;
    *) SELECTED_MODEL="$RECOMMENDED_MODEL" ;;
esac

echo ""
echo "[+] Ausgewähltes Modell: $SELECTED_MODEL"

# Erstelle oder überschreibe .env
cat <<EOF > "$ENV_FILE"
OLLAMA_MODEL=$SELECTED_MODEL
OCR_LANG=deu
EOF

echo "[+] Konfiguration erfolgreich in '$ENV_FILE' gespeichert!"