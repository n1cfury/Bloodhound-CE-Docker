#!/usr/bin/env bash
# =============================================================================
# bh_setup.sh — BloodHound Legacy / Neo4j 4.4 Setup + Dump Import
# Run location: /home/n1c/bloodhound/
# Usage: sudo bash bh_setup.sh
# =============================================================================

set -euo pipefail

# --- Config ------------------------------------------------------------------
WORK_DIR="/home/n1c/bloodhound"
DUMP_FILE="${WORK_DIR}/*.dump"          # auto-detects first .dump in dir
NEO4J_VERSION="4.4"
NEO4J_PASSWORD="BloodHound1337"        # change this if you want
NEO4J_DB="neo4j"
LOG_FILE="${WORK_DIR}/bh_setup.log"
# -----------------------------------------------------------------------------

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $*" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[!]${NC} $*" | tee -a "$LOG_FILE"; }
err()  { echo -e "${RED}[✗]${NC} $*" | tee -a "$LOG_FILE"; exit 1; }
info() { echo -e "${CYAN}[*]${NC} $*" | tee -a "$LOG_FILE"; }

# --- Root check --------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
  err "Run as root: sudo bash bh_setup.sh"
fi

echo "" | tee "$LOG_FILE"
echo "=============================================" | tee -a "$LOG_FILE"
echo "  BloodHound / Neo4j Setup — $(date)"        | tee -a "$LOG_FILE"
echo "=============================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# --- Locate dump file --------------------------------------------------------
DUMP_PATH=$(ls "${WORK_DIR}"/*.dump 2>/dev/null | head -1 || true)

if [[ -z "$DUMP_PATH" ]]; then
  err "No .dump file found in ${WORK_DIR}. Drop it there and re-run."
fi

log "Found dump file: ${DUMP_PATH}"

# --- Remove Docker BloodHound if running -------------------------------------
info "Checking for conflicting Docker containers on port 7474/7687..."

# Stop and remove running containers on those ports
RUNNING=$(docker ps --filter "publish=7474" -q 2>/dev/null || true)
RUNNING+=" $(docker ps --filter "publish=7687" -q 2>/dev/null || true)"
RUNNING=$(echo "$RUNNING" | tr ' ' '\n' | sort -u | tr '\n' ' ' | xargs)

if [[ -n "$RUNNING" ]]; then
  warn "Stopping and removing Docker containers using Neo4j ports..."
  docker stop $RUNNING >> "$LOG_FILE" 2>&1
  docker rm $RUNNING >> "$LOG_FILE" 2>&1
  log "Docker containers stopped and removed."
else
  log "No running containers on ports 7474/7687."
fi

# Also catch any stopped BH/Neo4j containers that could resurrect
info "Checking for stopped BloodHound/Neo4j containers..."
STOPPED=$(docker ps -a --filter "name=bloodhound" --filter "name=neo4j" -q 2>/dev/null || true)
if [[ -n "$STOPPED" ]]; then
  warn "Removing stopped BloodHound/Neo4j containers..."
  docker rm $STOPPED >> "$LOG_FILE" 2>&1
  log "Stopped containers removed."
fi

# Optional: remove the compose stack if it exists
if [[ -f "${WORK_DIR}/docker-compose.yml" ]]; then
  warn "Found docker-compose.yml — tearing down the stack..."
  docker compose -f "${WORK_DIR}/docker-compose.yml" down -v >> "$LOG_FILE" 2>&1 && \
    log "Docker Compose stack torn down (volumes removed)."
fi

# --- Install Neo4j 4.4 natively ----------------------------------------------
if ! command -v neo4j &>/dev/null; then
  log "Installing Neo4j ${NEO4J_VERSION}..."

  # Dependencies
  apt-get update -qq
  apt-get install -y wget curl gnupg apt-transport-https >> "$LOG_FILE" 2>&1

  # Java (Neo4j 4.4 needs Java 11)
  apt-get install -y openjdk-11-jre >> "$LOG_FILE" 2>&1
  log "Java 11 installed."

  # Neo4j repo
  wget -qO - https://debian.neo4j.com/neotechnology.gpg.key | apt-key add - >> "$LOG_FILE" 2>&1
  echo "deb https://debian.neo4j.com stable ${NEO4J_VERSION}" \
    > /etc/apt/sources.list.d/neo4j.list

  apt-get update -qq
  apt-get install -y neo4j >> "$LOG_FILE" 2>&1
  log "Neo4j installed."
else
  log "Neo4j already installed: $(neo4j --version)"
fi

# --- Stop Neo4j before config/load ------------------------------------------
info "Stopping Neo4j for pre-load configuration..."
systemctl stop neo4j 2>/dev/null || true
sleep 2

# --- Set password ------------------------------------------------------------
log "Setting Neo4j password..."
neo4j-admin set-initial-password "${NEO4J_PASSWORD}" >> "$LOG_FILE" 2>&1 || \
  warn "Password may already be set — continuing."

# --- Load the dump -----------------------------------------------------------
log "Loading dump file into Neo4j (this may take a minute on 150MB)..."
neo4j-admin load \
  --from="${DUMP_PATH}" \
  --database="${NEO4J_DB}" \
  --force >> "$LOG_FILE" 2>&1

log "Dump loaded successfully."

# --- Start Neo4j -------------------------------------------------------------
log "Starting Neo4j..."
systemctl enable neo4j >> "$LOG_FILE" 2>&1
systemctl start neo4j
sleep 5

# --- Verify ------------------------------------------------------------------
info "Verifying Neo4j is up..."
MAX_WAIT=30
COUNT=0
until curl -s http://localhost:7474 &>/dev/null; do
  sleep 2
  COUNT=$((COUNT + 2))
  if [[ $COUNT -ge $MAX_WAIT ]]; then
    err "Neo4j didn't come up in ${MAX_WAIT}s. Check: journalctl -u neo4j -n 50"
  fi
done

log "Neo4j is up."

# --- Quick node count --------------------------------------------------------
info "Running quick node count to verify data loaded..."
NODE_COUNT=$(curl -s -u "neo4j:${NEO4J_PASSWORD}" \
  -H "Content-Type: application/json" \
  -d '{"statements":[{"statement":"MATCH (n) RETURN count(n) AS count"}]}' \
  http://localhost:7474/db/neo4j/tx/commit \
  2>/dev/null | grep -oP '"row":\[\K[0-9]+' | head -1 || echo "unknown")

echo ""
echo "============================================="
log "SETUP COMPLETE"
echo "============================================="
echo ""
info "Neo4j Browser : http://localhost:7474"
info "Bolt URI      : bolt://localhost:7687"
info "Username      : neo4j"
info "Password      : ${NEO4J_PASSWORD}"
info "Node count    : ${NODE_COUNT}"
echo ""
info "Connect BloodHound to bolt://localhost:7687 with the creds above."
info "Full log saved to: ${LOG_FILE}"
echo ""

# --- Verify with cypher hint -------------------------------------------------
warn "If node count shows 0 or 'unknown', run this manually in Neo4j browser:"
echo "  MATCH (n) RETURN count(n)"
echo ""