#!/bin/bash
# Simulate what Caddy sends when proxying WebSocket
curl -v \
  -H "Upgrade: websocket" \
  -H "Connection: Upgrade" \
  -H "Sec-WebSocket-Key: test123" \
  -H "Sec-WebSocket-Version: 13" \
  -H "X-Forwarded-For: 1.2.3.4" \
  -H "X-Forwarded-Proto: https" \
  http://localhost:8080/
