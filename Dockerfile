FROM python:3.12-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    CHAOS_ARMED=0 \
    PORT=8000

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
COPY docs/ ./docs/

USER chaos

EXPOSE 8000

# "serve" hosts the project site (docs/). Any other args go to the sidecar.
ENTRYPOINT ["sh", "-c", "if [ \"$1\" = serve ]; then exec python -m http.server \"${PORT:-8000}\" --bind 0.0.0.0 --directory /app/docs; fi; exec xvfb-run -a -- python /app/chaos_action.py \"$@\"", "--"]
CMD ["The user ignored their pet."]
