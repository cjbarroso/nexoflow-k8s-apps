# WAHA Application

This folder contains the **WAHA (WhatsApp HTTP API)** application configuration for Kubernetes.

> WAHA is a WhatsApp API that you can run in a click! It allows you to send and receive messages from WhatsApp using a simple HTTP API.

## Docker Image
We use the **WAHA Plus** image, which provides extended features and stability.

- **Image Repository:** `devlikeapro/waha-plus`
- **Tag:** `latest`
- **Documentation:** [https://waha.devlike.pro/](https://waha.devlike.pro/)

## Prerequisites

- A Kubernetes cluster
- ArgoCD (for deployment, as indicated by the structure)
- A valid WhatsApp account to scan the QR code

## Configuration

The application is configured via environment variables and persistent storage.

### Key Environment Variables
These are configured in the container:
- `WAHA_HTTP_HOST`: `0.0.0.0` (Listens on all interfaces)
- `WAHA_HTTP_PORT`: `3000` (Default port)
- `WAHA_LOG_LEVEL`: `info` (Logging verbosity)

### Persistence
The application requires persistent storage to save session data (authentication credentials).
- **Mount Path:** `/app/.waha`
- **Recommended Size:** `5Gi`
- **Access Mode:** `ReadWriteOnce`

## Deployment

This application is designed to be deployed via ArgoCD or `kubectl apply`.

### Manual Deployment (Testing)

You can deploy the manifest manually using the provided configuration:

```bash
kubectl apply -f apps/waha/
```

### Accessing the Dashboard

Once deployed, the WAHA dashboard is available at:
`http://<service-ip>:3000/dashboard`

Use this dashboard to scan the QR code and manage sessions.

### API Documentation

Swagger API documentation is available at:
`http://<service-ip>:3000/docs`