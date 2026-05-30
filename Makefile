ARGOCD_NAMESPACE ?= argocd
ARGOCD_SERVICE ?= argocd-server
ARGOCD_LOCAL_PORT ?= 8080
ARGOCD_SERVICE_PORT ?= 443
ARGOCD_SERVER ?= localhost:$(ARGOCD_LOCAL_PORT)
ARGOCD_USERNAME ?= admin
ARGOCD_LOGIN_FLAGS ?= --grpc-web --insecure

.PHONY: argologin argoconnect

argologin:
	argocd login $(ARGOCD_SERVER) --username $(ARGOCD_USERNAME) $(ARGOCD_LOGIN_FLAGS)

argoconnect:
	kubectl -n $(ARGOCD_NAMESPACE) port-forward svc/$(ARGOCD_SERVICE) $(ARGOCD_LOCAL_PORT):$(ARGOCD_SERVICE_PORT)
