#!/usr/bin/env bash
# Envoie des messages syslog de test vers SC4S (UDP 514 et TCP 514).
# Usage : bash tools/send_syslog.sh <hôte SC4S> [nombre]
set -euo pipefail
SC4S=${1:-ing01}; N=${2:-20}
now() { date '+%b %d %H:%M:%S'; }

for i in $(seq 1 "$N"); do
  # Linux sshd (RFC 3164) -> index osnix
  echo "<38>$(now) lnx01 sshd[1234]: Failed password for invalid user admin from 192.0.2.$((RANDOM%250)) port 5$((RANDOM%9999)) ssh2" | nc -u -w0 "$SC4S" 514
  # Cisco IOS -> index netops
  echo "<189>$i: $(now): %LINK-3-UPDOWN: Interface GigabitEthernet0/$((i%4)), changed state to down" | nc -u -w0 "$SC4S" 514
  # Cisco ASA -> index netfw (TCP)
  echo "<166>$(now) asa01 : %ASA-6-302013: Built outbound TCP connection $i for outside:198.51.100.$((RANDOM%250))/443 (198.51.100.10/443) to inside:10.0.0.$((RANDOM%250))/5$((RANDOM%999)) (203.0.113.5/1234)" | nc -w1 "$SC4S" 514
  # RFC 5424 générique
  echo "<134>1 $(date -u +%Y-%m-%dT%H:%M:%SZ) app01 myapp 999 ID47 - message RFC5424 numero $i" | nc -u -w0 "$SC4S" 514
done
echo "$N x 4 messages envoyés à $SC4S. Dans Splunk : index=* (sourcetype=cisco:* OR sourcetype=nix:syslog OR sourcetype=sc4s:*) earliest=-15m"
