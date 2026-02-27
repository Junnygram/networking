# Master Makefile to delegate to ShopMicro
.PHONY: help help-demo ev-% k8s-% ssh-% tf-% argocd-% endpoints push-trigger

help: ## Show help
	@cd ShopMicro && $(MAKE) help

help-demo: ## Show demo guide
	@cd ShopMicro && $(MAKE) help-demo

# Pattern match to delegate everything to ShopMicro/Makefile
%:
	@if [ -f ShopMicro/Makefile ]; then \
		cd ShopMicro && $(MAKE) $@; \
	else \
		echo "Error: ShopMicro/Makefile not found"; \
		exit 1; \
	fi
