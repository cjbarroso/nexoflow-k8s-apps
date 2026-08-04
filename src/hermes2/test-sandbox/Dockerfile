FROM google/cloud-sdk:slim@sha256:570dc7ce2876a2810dbf80f1d2520c1654aa218a7f1347715243a79c98d166ae

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates \
       git \
       nodejs \
       npm \
       openssh-server \
       python3 \
       python3-pip \
       python3-venv \
    && python3 -m pip install --break-system-packages --no-cache-dir uv==0.8.14 \
    && npm install --global @googleworkspace/cli@0.22.5 \
    && python3 -m venv /opt/hermes-gws \
    && /opt/hermes-gws/bin/pip install --no-cache-dir google-auth==2.40.3 requests==2.32.3 \
    && useradd --create-home --uid 1000 --shell /bin/bash hermes-sandbox \
    && mkdir -p /run/sshd \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ENV PATH="/opt/google-cloud-sdk/bin:/usr/local/bin:${PATH}" \
    CLOUDSDK_CONFIG=/config/gcloud \
    GOOGLE_APPLICATION_CREDENTIALS=/etc/google-wif/credential-configuration.json \
    GOOGLE_WORKSPACE_DELEGATED_USER=carlos@cjbarroso.com \
    GOOGLE_WORKSPACE_SERVICE_ACCOUNT=hermes-sandbox-gcp@miintancia.iam.gserviceaccount.com \
    GOOGLE_WORKSPACE_SCOPES=https://www.googleapis.com/auth/drive.readonly,https://www.googleapis.com/auth/calendar.readonly

COPY gws-delegated /usr/local/bin/gws-delegated
COPY init-gcloud-auth /usr/local/bin/init-gcloud-auth
COPY sandbox-entrypoint /usr/local/bin/sandbox-entrypoint

RUN chmod 0755 /usr/local/bin/gws-delegated /usr/local/bin/init-gcloud-auth /usr/local/bin/sandbox-entrypoint
