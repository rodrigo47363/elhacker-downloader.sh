#!/bin/bash
set -e

REPO_URL="https://github.com/rodrigo47363/elhacker-downloader/raw/main/setup.sh"
SCRIPT_NAME="setup.sh"
LOCAL_PATH="/usr/local/bin/$SCRIPT_NAME"

# Configuración inicial
BASE_URL="https://elhacker.info"
TMP_LIST="/tmp/elhacker_all_files.txt"
DOWNLOAD_DIR="elhacker_downloads"

# Colores para consola
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
RESET="\e[0m"

# Verifica que las dependencias necesarias estén instaladas
check_dependencies() {
    local missing=0
    for cmd in curl wget pup; do
        if ! command -v "$cmd" &>/dev/null; then
            echo -e "${RED}[✘] Falta la dependencia: $cmd${RESET}"
            missing=1
        fi
    done
    if [[ $missing -eq 1 ]]; then
        echo -e "${RED}Por favor instala las dependencias faltantes antes de continuar.${RESET}"
        exit 1
    fi
}

# Asegura que una URL termine con "/"
normalize_url() {
    local url="$1"
    [[ "${url: -1}" != "/" ]] && url="${url}/"
    echo "$url"
}

# Listado recursivo de archivos desde URL base
list_recursive() {
    local url="$1"
    local prefix="$2"

    echo -e "${YELLOW}[*] Explorando: $url${RESET}"

    local links
    links=$(curl -s "$url" | pup 'a attr{href}' | grep -vE '^(\.\./|#|/$)')

    while read -r link; do
        [[ -z "$link" ]] && continue
        if [[ "$link" == */ ]]; then
            list_recursive "${url}${link}" "${prefix}${link}"
        else
            echo "${prefix}${link}" >> "$TMP_LIST"
        fi
    done <<< "$links"
}

# Listado simple (no recursivo) para URL específica
list_non_recursive() {
    local url="$1"
    echo -e "${YELLOW}[*] Listando archivos en: $url${RESET}"

    curl -s "$url" | pup 'a attr{href}' | grep -vE '^(\.\./|#|/$)' > "$TMP_LIST"
}

# Permite seleccionar archivos para descargar (usando fzf si está disponible)
select_files_to_download() {
    if command -v fzf &>/dev/null; then
        mapfile -t selected < <(cat "$TMP_LIST" | fzf --multi --prompt="Selecciona archivos ➤ ")
    else
        nl "$TMP_LIST"
        read -rp "Ingresa números separados por espacios: " nums
        selected=()
        for n in $nums; do
            selected+=("$(sed "${n}q;d" "$TMP_LIST")")
        done
    fi
}

# Pregunta si se quiere descargar todo o seleccionar archivos individualmente
choose_download_mode() {
    while true; do
        read -rp "¿Quieres descargar TODOS los archivos listados? (s/n): " yn
        case $yn in
            [Ss]* )
                mapfile -t selected < "$TMP_LIST"
                break
                ;;
            [Nn]* )
                select_files_to_download
                break
                ;;
            * )
                echo "Por favor responde s (sí) o n (no)."
                ;;
        esac
    done
}

# Descarga los archivos seleccionados preservando estructura de directorios
download_files() {
    mkdir -p "$DOWNLOAD_DIR"
    cd "$DOWNLOAD_DIR" || exit 1

    for file in "${selected[@]}"; do
        local file_dir
        if [[ "$file" =~ ^https?:// ]]; then
            # Extrae ruta relativa de URL absoluta para preservar carpetas
            file_dir=$(dirname "$(echo "$file" | sed -E 's#https?://[^/]+/(.*)#\1#')")
            mkdir -p "$file_dir"
            echo -e "${GREEN}[+] Descargando: $file${RESET}"
            wget -c "$file" -P "$file_dir"
        else
            file_dir=$(dirname "$file")
            mkdir -p "$file_dir"
            echo -e "${GREEN}[+] Descargando: ${base_url_for_download}${file}${RESET}"
            wget -c "${base_url_for_download}${file}" -P "$file_dir"
        fi
    done
}

# Menú principal para elegir modo y gestionar flujo
main_menu() {
    clear
    echo -e "${GREEN}======================================="
    echo -e "   Script de descarga recursiva de web"
    echo -e "=======================================${RESET}"
    echo "1) Explorar recursivamente desde URL base: $BASE_URL"
    echo "2) Ingresar URL específica (modo no recursivo)"
    echo "3) Salir"
    echo
    read -rp "Selecciona una opción (1-3): " option

    case "$option" in
        1)
            base_url_for_download=$(normalize_url "$BASE_URL")
            > "$TMP_LIST"
            list_recursive "$base_url_for_download" ""
            ;;
        2)
            read -rp "Ingresa la URL completa: " user_url
            if ! [[ "$user_url" =~ ^https?:// ]]; then
                echo -e "${RED}URL inválida. Debe comenzar con http:// o https://${RESET}"
                sleep 2
                main_menu
                return
            fi
            user_url=$(normalize_url "$user_url")
            > "$TMP_LIST"
            list_non_recursive "$user_url"
            base_url_for_download="$user_url"
            ;;
        3)
            echo -e "${YELLOW}Saliendo...${RESET}"
            exit 0
            ;;
        *)
            echo -e "${RED}Opción inválida.${RESET}"
            sleep 1
            main_menu
            ;;
    esac

    if [[ ! -s "$TMP_LIST" ]]; then
        echo -e "${RED}[✘] No se encontraron archivos para descargar.${RESET}"
        sleep 2
        main_menu
    fi

    echo -e "${GREEN}[✔] Se encontraron $(wc -l < "$TMP_LIST") archivos.${RESET}"

    choose_download_mode
    download_files

    echo -e "${GREEN}[✔] Descarga finalizada.${RESET}"

    read -rp "Presiona ENTER para volver al menú..."
    main_menu
}

# --- EJECUCIÓN ---

check_dependencies
main_menu
