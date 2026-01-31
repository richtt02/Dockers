# Custom Claude Code Container with Firewall Support
# Based on richtt02/claude-base (Node.js 22 Debian + Claude CLI + Anthropic Tools)

FROM richtt02/claude-base:latest

USER root

# Copy entrypoint and firewall scripts with explicit permissions
COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chmod=755 init-firewall.sh /usr/local/bin/init-firewall.sh

# Fix potential Windows line endings (CRLF -> LF)
RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh /usr/local/bin/init-firewall.sh

# Verify the files were copied correctly (fails build if not)
RUN ls -la /usr/local/bin/entrypoint.sh /usr/local/bin/init-firewall.sh && \
    test -x /usr/local/bin/entrypoint.sh || \
    (echo "ERROR: entrypoint.sh not executable" && exit 1) && \
    test -x /usr/local/bin/init-firewall.sh || \
    (echo "ERROR: init-firewall.sh not executable" && exit 1)

WORKDIR /workspace

# Entrypoint handles: firewall init -> UID/GID mapping -> drop privileges
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
# Keep container running for docker exec access
CMD ["sleep", "infinity"]