FROM google/cloud-sdk:slim@sha256:570dc7ce2876a2810dbf80f1d2520c1654aa218a7f1347715243a79c98d166ae AS gcloud

FROM lscr.io/linuxserver/openssh-server:version-9.6_p1-r0@sha256:813375fb9b6d247c4ee355d94ac2feda372d0f5553f01f2a12e44b258972fee2

COPY --from=gcloud /usr/lib/google-cloud-sdk /opt/google-cloud-sdk

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates \
       git \
       nodejs \
       npm \
       python3 \
       python3-pip \
       python3-venv \
    && python3 -m pip install --break-system-packages --no-cache-dir uv==0.8.14 \
    && npm install --global @googleworkspace/cli@0.22.5 \
    && python3 -m venv /opt/hermes-gws \
    && /opt/hermes-gws/bin/pip install --no-cache-dir google-auth==2.40.3 requests==2.32.3 \
    && ln -s /opt/hermes-gws/bin/python /usr/local/bin/hermes-gws-python \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN ln -s /opt/google-cloud-sdk/bin/gcloud /usr/local/bin/gcloud \
    && ln -s /opt/google-cloud-sdk/bin/gsutil /usr/local/bin/gsutil \
    && ln -s /opt/google-cloud-sdk/bin/bq /usr/local/bin/bq

ENV PATH="/opt/google-cloud-sdk/bin:/usr/local/bin:${PATH}" \
    CLOUDSDK_CONFIG=/config/gcloud \
    GOOGLE_APPLICATION_CREDENTIALS=/etc/google-wif/credential-configuration.json \
    GOOGLE_WORKSPACE_DELEGATED_USER=carlos@cjbarroso.com \
    GOOGLE_WORKSPACE_SERVICE_ACCOUNT=hermes-sandbox-gcp@miintancia.iam.gserviceaccount.com \
    GOOGLE_WORKSPACE_SCOPES=https://www.googleapis.com/auth/drive.readonly,https://www.googleapis.com/auth/calendar.readonly

COPY gws-delegated /usr/local/bin/gws-delegated
COPY init-gcloud-auth /custom-cont-init.d/20-gcloud-auth

RUN chmod 0755 /usr/local/bin/gws-delegated /custom-cont-init.d/20-gcloud-auth
