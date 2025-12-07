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

# hhccia PostgreSQL port-forwards (for tools like DBeaver)
HHCCIA_NAMESPACE ?= hhccia
HHCCIA_RW_SERVICE ?= hhccia-cluster-rw
HHCCIA_RO_SERVICE ?= hhccia-cluster-ro
HHCCIA_PGADMIN_SERVICE ?= hhccia-cluster-pgadmin

.PHONY: hhccia-pf-rw hhccia-pf-ro hhccia-pf-web

hhccia-pf-rw:
	kubectl -n $(HHCCIA_NAMESPACE) port-forward svc/$(HHCCIA_RW_SERVICE) 8087:5432

hhccia-pf-ro:
	kubectl -n $(HHCCIA_NAMESPACE) port-forward svc/$(HHCCIA_RO_SERVICE) 8088:5432

hhccia-pf-web:
	kubectl -n $(HHCCIA_NAMESPACE) port-forward svc/$(HHCCIA_PGADMIN_SERVICE) 8089:80
