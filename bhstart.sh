#!/bin/bash
set -e

BH_DIR="/home/n1c/bloodhound"

echo "[*] Starting BloodHound..."
cd "$BH_DIR" || { echo "[!] Could not find $BH_DIR"; exit 1; }

sudo docker-compose up -d

echo "[*] Waiting for containers to stabilize..."
sleep 5

echo "[*] Container status:"
sudo docker-compose ps

echo ""
echo "[+] BloodHound should be reachable at: http://bloodhound:8080"
echo "[*] If this is first-ever startup, grab initial password with:"
echo "    sudo docker-compose logs | grep -i initialpassword"