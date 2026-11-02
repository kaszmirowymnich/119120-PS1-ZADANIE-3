#!/bin/bash
cd ~/zadanie3
docker compose down
sync
echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null
t0=$(date +%s.%N)
docker compose up -d
for i in $(seq 1 180); do
  if curl -sf -m 5 http://192.168.128.2:8080/v1/chat/completions -H "Content-Type: application/json" -d '{"model":"local","messages":[{"role":"user","content":"Powiedz cześć."}]}' -o /dev/null; then break; fi
  sleep 1
done
t1=$(date +%s.%N)
echo "docker zimny cache: $(echo "$t1 - $t0" | bc) s" | tee outputs/czas-docker-zimny.txt
