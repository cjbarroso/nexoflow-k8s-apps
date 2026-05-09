# Nexoflow K8s Apps

Welcome to the **Nexoflow K8s Apps** repository! This repository contains the GitOps configuration for the Nexoflow Kubernetes cluster, managed via [Argo CD](https://argo-cd.readthedocs.io/en/stable/).

## Overview

High-level goals of this repository:
1.  **GitOps Source of Truth**: All application manifests and configurations are stored here.
2.  **Automated Deployment**: Argo CD monitors this repository and synchronizes changes to the cluster.
3.  **Application Management**: Provides a structured way to manage multiple applications (e.g., n8n, Velero, Databases).

## Prerequisites for Developers

To work with this repository, you should have the following tools installed:

*   **`kubectl`**: For interacting with the Kubernetes cluster.
*   **`argocd` CLI**: For managing Argo CD applications and settings.
*   **`git`**: For cloning and pushing GitOps changes.

## Getting Started

1.  **Clone the Repository**:
    ```bash
    git clone https://github.com/cjbarroso/nexoflow-k8s-apps.git
    cd nexoflow-k8s-apps
    ```

2.  **Explore the Structure**:
    Check out `docs/02-ARCHITECTURE.md` to understand how applications are structured.

3.  **Check Application Status**:
    Before deploying or modifying applications, please read `docs/04-TROUBLESHOOTING.md` to see the current status of known issues (e.g., Waha, Cal.com).
