#!/bin/bash

YELLOW='\033[1;33m'
BLUE='\033[1;34m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${BLUE}[INIT] Starte Modell-Initialisierung...${NC}"

# 1. Manuelle Konfiguration aus .env prüfen
if [ -n "$OLLAMA_MODEL" ] && [ "$OLLAMA_MODEL" != "auto" ]; then
    MODEL="$OLLAMA_MODEL"
    echo -e "${GREEN}[INIT] Manuell konfiguriertes Modell aus .env übernommen: '$MODEL'${NC}"
else
    # 2. Hardware-Erkennung (NVIDIA -> AMD Sysfs -> System-RAM Fallback)
    MEM_MB=0

    # NVIDIA check
    if command -v nvidia-smi &>/dev/null; then
        MEM_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n 1 | tr -d '[:space:]')
    fi

    # AMD Linux Sysfs check
    if ! [[ "$MEM_MB" =~ ^[0-9]+$ ]] || [ "$MEM_MB" -eq 0 ]; then
        for vram_file in /sys/class/drm/card*/device/mem_info_vram_total; do
            if [ -f "$vram_file" ]; then
                bytes=$(cat "$vram_file" 2>/dev/null)
                if [[ "$bytes" =~ ^[0-9]+$ ]] && [ "$bytes" -gt 0 ]; then
                    MEM_MB=$((bytes / 1024 / 1024))
                    break
                fi
            fi
        done
    fi

    # Fallback für macOS / Docker Desktop VM / Reine CPUs
    if ! [[ "$MEM_MB" =~ ^[0-9]+$ ]] || [ "$MEM_MB" -eq 0 ]; then
        echo -e "${YELLOW}======================================================================${NC}"
        echo -e "${YELLOW} HINWEIS: VRAM KONNTE NICHT AUTOMATISCH ERKANNT WERDEN!              ${NC}"
        echo -e "${YELLOW}======================================================================${NC}"
        echo -e " Ursache    : Das System nutzt macOS (Apple Silicon), AMD/Intel GPU ohne ROCm,"
        echo -e "              reinen CPU-Betrieb oder Docker ohne GPU-Passthrough."
        echo -e " Aktion     : Lese den zugewiesenen Docker System-RAM (/proc/meminfo) aus."
        echo -e " TIPP       : Auf dem Host kann mit './configure_model.sh' manuell ein"
        echo -e "              Wunschmodell ausgewählt werden."
        echo -e "${YELLOW}======================================================================${NC}"
        
        if [ -f "/proc/meminfo" ]; then
            kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
            if [[ "$kb" =~ ^[0-9]+$ ]] && [ "$kb" -gt 0 ]; then
                MEM_MB=$(( (kb / 1024) * 80 / 100 ))
            fi
        fi
    fi

    # Modell-Zuordnung basierend auf Arbeitsspeicher
    if [ "$MEM_MB" -ge 20000 ]; then
        MODEL="gemma3:27b"
    elif [ "$MEM_MB" -ge 10000 ]; then
        MODEL="qwen2.5:14b"
    elif [ "$MEM_MB" -ge 5500 ]; then
        MODEL="qwen2.5:7b"
    else
        MODEL="qwen2.5:3b"
    fi
    echo -e "${GREEN}[+] Verfügbarer Speicher/VRAM: ${MEM_MB} MB -> Modell '$MODEL' gewählt.${NC}"
fi

# 3. Warten auf Ollama
echo -e "${BLUE}[INIT] Warte auf Ollama-Dienst (http://ollama:11434)...${NC}"
while ! curl -s http://ollama:11434/api/tags > /dev/null; do
    sleep 2
done

# 4. Modell herunterladen
echo -e "${BLUE}[INIT] Prüfe/Lade Modell '$MODEL' bei Ollama...${NC}"
curl -X POST http://ollama:11434/api/pull -d "{\"name\": \"$MODEL\"}"

echo -e "${GREEN}[INIT] Modell '$MODEL' ist einsatzbereit!${NC}"