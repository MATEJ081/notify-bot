FROM python:3.11-slim

WORKDIR /app

# Copy dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy source
COPY telegram_notifier.py .
COPY mcp_server.py .
COPY notify.py .

# Create log and state dirs
RUN mkdir -p logs state && chmod 700 logs state

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:5000/health', timeout=3)"

# Default: run MCP server
CMD ["python3", "mcp_server.py"]
