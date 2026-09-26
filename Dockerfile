FROM python:3.12-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    CHAOS_ARMED=0

WORKDIR /app

# Google Chrome matches Playwright channel="chrome" in chaos_action.py.
# xvfb gives that headed browser a display. iMessage/osascript stays macOS-only.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        wget \
        xvfb \
    && wget -q -O /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
    && apt-get install -y --no-install-recommends /tmp/chrome.deb \
    && rm -rf /var/lib/apt/lists/* /tmp/chrome.deb \
    && useradd --create-home --uid 1000 chaos

COPY sidecar/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY sidecar/chaos_action.py .

USER chaos

ENTRYPOINT ["xvfb-run", "-a", "--", "python", "chaos_action.py"]
CMD ["The user ignored their pet."]
