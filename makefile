# ==============================================================================
# CONFIGURACIÓN GENERAL
# ==============================================================================
MOUNT_POINT    := /media/nas
DIR_SAMBA      := $(MOUNT_POINT)/samba
DIR_NEXTCLOUD  := $(MOUNT_POINT)/nextcloud_data
ENV_FILE       := .env

.PHONY: all help install-deps setup-storage check-env setup-nextcloud-domain permissions up down restart status logs clean

# Comando predeterminado al ejecutar 'make'
all: install-deps setup-storage check-env up setup-nextcloud-domain

help: ## Muestra este menú de ayuda
	@echo "Uso: make [comando]"
	@echo ""
	@echo "Comandos disponibles:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2}'

# ==============================================================================
# 1. PREPARACIÓN E INSTALACIÓN DEL SISTEMA
# ==============================================================================
install-deps: ## Instala Docker y dependencias necesarias en la Raspberry Pi
	@echo "==> Actualizando paquetes del sistema..."
	sudo apt update && sudo apt upgrade -y
	sudo apt install -y curl ca-certificates util-linux
	@if ! command -v docker > /dev/null 2>&1; then \
		echo "==> Instalando Docker en la Raspberry Pi..."; \
		curl -fsSL https://get.docker.com -o get-docker.sh; \
		sudo sh get-docker.sh; \
		rm get-docker.sh; \
		sudo usermod -aG docker $$USER; \
		echo "==> Docker instalado correctamente."; \
	else \
		echo "==> Docker ya se encuentra instalado."; \
	fi

setup-storage: ## Crea las carpetas de almacenamiento e infraestructura
	@echo "==> Creando carpetas en el almacenamiento ($(MOUNT_POINT))..."
	sudo mkdir -p $(DIR_SAMBA)
	sudo mkdir -p $(DIR_NEXTCLOUD)
	@echo "==> Asignando permisos al usuario actual ($(USER))..."
	sudo chown -R $(USER):$(USER) $(MOUNT_POINT)
	sudo chmod -R 775 $(MOUNT_POINT)

check-env: ## Crea y valida el archivo .env con las credenciales y dominio
	@if [ ! -f $(ENV_FILE) ]; then \
		echo "==> Configurando variables de entorno iniciales..."; \
		read -p "Ingresa tu Token de Cloudflare Tunnel: " cf_token; \
		read -p "Ingresa el usuario para Samba (NAS): " smb_user; \
		read -s -p "Ingresa la contraseña para Samba (NAS): " smb_pass; echo ""; \
		read -p "Ingresa el subdominio completo de Nextcloud (ej. nube.midominio.com): " nc_domain; \
		echo "CLOUDFLARE_TOKEN=$$cf_token" > $(ENV_FILE); \
		echo "SAMBA_USER=$$smb_user" >> $(ENV_FILE); \
		echo "SAMBA_PASSWORD=$$smb_pass" >> $(ENV_FILE); \
		echo "NEXTCLOUD_DOMAIN=$$nc_domain" >> $(ENV_FILE); \
		echo "==> Archivo $(ENV_FILE) creado correctamente."; \
	fi

# ==============================================================================
# 2. CONFIGURACIÓN ESPECÍFICA DE NEXTCLOUD
# ==============================================================================
setup-nextcloud-domain: ## Agrega el dominio guardado en .env a trusted_domains en Nextcloud
	@echo "==> Aplicando dominio de confianza en Nextcloud..."
	@eval $$(cat $(ENV_FILE) | grep NEXTCLOUD_DOMAIN) && \
	if [ -n "$$NEXTCLOUD_DOMAIN" ]; then \
		docker exec nextcloud_app php occ config:system:set trusted_domains 2 --value=$$NEXTCLOUD_DOMAIN; \
		echo "==> Dominio $$NEXTCLOUD_DOMAIN registrado con éxito en Nextcloud."; \
	else \
		echo "==> [Aviso] No se encontró NEXTCLOUD_DOMAIN en el archivo .env"; \
	fi

permissions: ## Repara permisos en las rutas del NAS si hay problemas de escritura
	sudo chown -R $(USER):$(USER) $(MOUNT_POINT)
	sudo chmod -R 775 $(MOUNT_POINT)

# ==============================================================================
# 3. CONTROL DE DOCKER
# ==============================================================================
up: check-env ## Levanta e inicia todos los servicios
	@echo "==> Iniciando contenedores..."
	docker compose up -d

down: ## Detiene y remueve los contenedores
	@echo "==> Deteniendo servicios..."
	docker compose down

restart: ## Reinicia todos los servicios
	@echo "==> Reiniciando servicios..."
	docker compose restart

status: ## Muestra el estado actual de los servicios
	docker compose ps

logs: ## Muestra los logs en tiempo real de todos los contenedores
	docker compose logs -f

clean: ## Limpia contenedores e imágenes no utilizadas de Docker
	docker compose down
	docker system prune -f