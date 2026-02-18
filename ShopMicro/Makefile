# ShopMicro Makefile

.PHONY: help build up down restart logs k8s-apply k8s-delete k8s-status

help: ## Show this help message
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

build: ## Build Docker images locally using docker-compose
	docker-compose build

up: ## Start services locally in detached mode
	docker-compose up -d

down: ## Stop and remove local containers, networks, and volumes
	docker-compose down

restart: down up ## Restart local environment

logs: ## Tail logs for local services
	docker-compose logs -f

k8s-apply: ## Apply all Kubernetes manifests (Deployment)
	kubectl apply -f k8s/

k8s-delete: ## Delete all Kubernetes resources
	kubectl delete -f k8s/

k8s-status: ## Check status of Kubernetes pods and services in the namespace
	kubectl get all -n shopmicro
