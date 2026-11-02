# Zadanie 3: llamafile (Qwen3.5-4B) w Dockerze

Ta sama usługa co w zadaniu 2 (systemd), ale w kontenerze Docker na Ubuntu Server ARM64 (UTM, 2 CPU, ok. 5,3 GiB RAM). Obraz jest w rejestrze GHCR: `ghcr.io/kaszmirowymnich/llamafile-qwen:1.0`.

## Kroki (odtworzenie na nowej maszynie)

Maszyna: Ubuntu Server z kartą host-only (u mnie `192.168.128.2`). Przy budowaniu potrzeba ok. 12 GB wolnego miejsca (u mnie rozszerzono wolumen LVM: `sudo lvextend -r -l +100%FREE /dev/ubuntu-vg/ubuntu-lv`).

1. Instalacja Dockera:

```
sudo apt update && sudo apt -y install docker.io docker-compose-v2
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
```

Po tym wyloguj się i zaloguj ponownie.

2. Repozytorium i konfiguracja:

```
git clone git@github.com:kaszmirowymnich/119120-PS1-ZADANIE-3.git && cd 119120-PS1-ZADANIE-3
cp .env.example .env
nano .env
```

W `.env` ustaw `LLAMAFILE_SHA256` (sumę modelu da `sha256sum plik.llamafile`), `HOST_ONLY_ADDRESS` (adres z `ip -br a`), `PORT` i `THREADS`.

3. Uruchomienie z obrazu z rejestru (bez budowania):

```
docker compose pull
docker compose up -d
docker compose ps
```

Po ok. 20-90 s stan to `(healthy)`.

4. Opcjonalnie, własny build i push do GHCR (token PAT z uprawnieniem `write:packages`):

```
docker compose build
echo "$TOKEN" | docker login ghcr.io -u kaszmirowymnich --password-stdin
docker compose push
```

Pakiet w GHCR jest ustawiony jako publiczny.

Jeśli działa stara usługa systemd z zadania 2, wyłącz ją (`sudo systemctl disable --now llamafile`), bo zajmuje ten sam adres i port.

## Decyzje projektowe

- Dwa etapy: w etapie `build` curl pobiera model, a `sha256sum -c` weryfikuje sumę. Obraz końcowy to `debian:trixie-slim` bez curl.
- Obraz bazowy ma wersję `debian:trixie-slim`, nie `latest`.
- Proces działa jako użytkownik `llamafile` (uid 999) z katalogiem domowym `/var/lib/llamafile`, bo llamafile rozpakowuje tam `.ape`.
- Flaga `--nobrowser` z szablonu nie jest obsługiwana przez llamafile 0.10.6 (`invalid argument`, kontener w pętli restartów), więc ją usunięto.
- `.env` (adres, port, wątki, suma, URL) nie jest w repozytorium. Jest `.env.example`.
- Limity: `mem_limit: 3g`, `cpus: 2`. Pomiary: szczyt 2,2 GB w systemd (zadanie 2), 1,9 GiB w kontenerze po obciążeniu. Limit 3g daje ok. 35% zapasu i nie wypycha stron modelu z cache, a 2 CPU odpowiadają liczbie rdzeni VM i `THREADS=2`.
- Port publikowany jako `192.168.128.2:8080:8080`, więc nie jest dostępny pod innymi adresami.
- `restart: unless-stopped` oraz Docker włączony w systemd dają autostart po restarcie maszyny.

## Dockerfile

```dockerfile
FROM debian:trixie-slim AS build
ARG LLAMAFILE_URL
ARG LLAMAFILE_SHA256
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL -o /model.llamafile "$LLAMAFILE_URL" \
 && echo "$LLAMAFILE_SHA256  /model.llamafile" | sha256sum -c - \
 && chmod +x /model.llamafile

FROM debian:trixie-slim
RUN useradd --system --create-home --home-dir /var/lib/llamafile \
      --shell /usr/sbin/nologin llamafile
ENV HOME=/var/lib/llamafile
COPY --from=build /model.llamafile /opt/llamafile/model.llamafile
USER llamafile
EXPOSE 8080
ENTRYPOINT ["sh", "/opt/llamafile/model.llamafile", "--server", "--gpu", "disable", "--host", "0.0.0.0"]
CMD ["--port", "8080"]
```

## compose.yaml

```yaml
services:
  llm:
    image: ${REGISTRY_IMAGE}
    build:
      context: .
      args:
        LLAMAFILE_URL: ${LLAMAFILE_URL}
        LLAMAFILE_SHA256: ${LLAMAFILE_SHA256}
    command: ["--port", "8080", "--threads", "${THREADS}"]
    ports:
      - "${HOST_ONLY_ADDRESS}:${PORT}:8080"
    restart: unless-stopped
    mem_limit: 3g
    cpus: 2
    healthcheck:
      test: ["CMD", "bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/8080"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 90s
```

## Dockerfile

```dockerfile
FROM debian:trixie-slim AS build
ARG LLAMAFILE_URL
ARG LLAMAFILE_SHA256
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL -o /model.llamafile "$LLAMAFILE_URL" \
 && echo "$LLAMAFILE_SHA256  /model.llamafile" | sha256sum -c - \
 && chmod +x /model.llamafile

FROM debian:trixie-slim
RUN useradd --system --create-home --home-dir /var/lib/llamafile \
      --shell /usr/sbin/nologin llamafile
ENV HOME=/var/lib/llamafile
COPY --from=build /model.llamafile /opt/llamafile/model.llamafile
USER llamafile
EXPOSE 8080
ENTRYPOINT ["sh", "/opt/llamafile/model.llamafile", "--server", "--gpu", "disable", "--host", "0.0.0.0"]
CMD ["--port", "8080"]
```

## compose.yaml

```yaml
services:
  llm:
    image: ${REGISTRY_IMAGE}
    build:
      context: .
      args:
        LLAMAFILE_URL: ${LLAMAFILE_URL}
        LLAMAFILE_SHA256: ${LLAMAFILE_SHA256}
    command: ["--port", "8080", "--threads", "${THREADS}"]
    ports:
      - "${HOST_ONLY_ADDRESS}:${PORT}:8080"
    restart: unless-stopped
    mem_limit: 3g
    cpus: 2
    healthcheck:
      test: ["CMD", "bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/8080"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 90s
```

### docker image ls

```
IMAGE                                        ID             DISK USAGE   CONTENT SIZE   EXTRA
ghcr.io/kaszmirowymnich/llamafile-qwen:1.0   73b9867bd9df       7.72GB          3.7GB        
```

### docker compose ps (healthy)

```
NAME             IMAGE                                        COMMAND                  SERVICE   CREATED          STATUS                    PORTS
zadanie3-llm-1   ghcr.io/kaszmirowymnich/llamafile-qwen:1.0   "sh /opt/llamafile/m…"   llm       18 seconds ago   Up 17 seconds (healthy)   192.168.128.2:8080->8080/tcp
```

### ss -tlnp (8080 tylko na adresie host-only)

```
State  Recv-Q Send-Q Local Address:Port  Peer Address:PortProcess
LISTEN 0      4096   127.0.0.53%lo:53         0.0.0.0:*    users:(("systemd-resolve",pid=31115,fd=18))
LISTEN 0      4096       127.0.0.1:41491      0.0.0.0:*    users:(("containerd",pid=1059,fd=14))
LISTEN 0      4096      127.0.0.54:53         0.0.0.0:*    users:(("systemd-resolve",pid=31115,fd=20))
LISTEN 0      4096         0.0.0.0:22         0.0.0.0:*    users:(("sshd",pid=102590,fd=3),("systemd",pid=1,fd=249))
LISTEN 0      4096   192.168.128.2:8080       0.0.0.0:*    users:(("docker-proxy",pid=104452,fd=7))
LISTEN 0      4096            [::]:22            [::]:*    users:(("sshd",pid=102590,fd=4),("systemd",pid=1,fd=256))
```

### Użytkownik w kontenerze

```
uid=999(llamafile) gid=999(llamafile) groups=999(llamafile)
```

### Restart po kill -9

```
PID przed: 104923
NAME             IMAGE                                        COMMAND                  SERVICE   CREATED              STATUS                   PORTS
zadanie3-llm-1   ghcr.io/kaszmirowymnich/llamafile-qwen:1.0   "sh /opt/llamafile/m…"   llm       About a minute ago   Up 5 seconds (healthy)   192.168.128.2:8080->8080/tcp
PID po: 105130, restarty: 2
```

### Autostart po restarcie maszyny

```
 21:25:55 up 0 min,  1 user,  load average: 0.19, 0.05, 0.02
NAME             IMAGE                                        COMMAND                  SERVICE   CREATED       STATUS                 PORTS
zadanie3-llm-1   ghcr.io/kaszmirowymnich/llamafile-qwen:1.0   "sh /opt/llamafile/m…"   llm       4 hours ago   Up 4 hours (healthy)   192.168.128.2:8080->8080/tcp
zimny start, sekundy od uruchomienia petli: 1
NAME             IMAGE                                        COMMAND                  SERVICE   CREATED       STATUS                 PORTS
zadanie3-llm-1   ghcr.io/kaszmirowymnich/llamafile-qwen:1.0   "sh /opt/llamafile/m…"   llm       4 hours ago   Up 4 hours (healthy)   192.168.128.2:8080->8080/tcp
```

### Pamięć i limity

```
CONTAINER ID   NAME             CPU %     MEM USAGE / LIMIT   MEM %     NET I/O           BLOCK I/O         PIDS
1ecf0db064b8   zadanie3-llm-1   0.01%     1.285GiB / 4GiB     32.12%    5.06kB / 4.19kB   14.6GB / 1.07GB   15
CONTAINER ID   NAME             CPU %     MEM USAGE / LIMIT   MEM %     NET I/O           BLOCK I/O       PIDS
1ecf0db064b8   zadanie3-llm-1   0.01%     1.897GiB / 4GiB     47.41%    4.67kB / 6.92kB   863MB / 683MB   15
CONTAINER ID   NAME             CPU %     MEM USAGE / LIMIT   MEM %     NET I/O           BLOCK I/O         PIDS
4ed6d2a4a449   zadanie3-llm-1   0.01%     224.7MiB / 3GiB     7.32%     5.06kB / 4.12kB   22.7GB / 1.63GB   15
```

### Zapytanie curl i odpowiedź modelu

```
$ curl http://192.168.128.2:8080/v1/chat/completions -H "Content-Type: application/json" -d '{"model":"local","messages":[{"role":"user","content":"Powiedz cześć w jednym zdaniu."}]}'
{"choices":[{"finish_reason":"stop","index":0,"message":{"role":"assistant","content":"Cześć!"}}],"model":"/zip/Qwen3.5-4B-Q5_K_S.gguf","object":"chat.completion","usage":{"completion_tokens":5,"prompt_tokens":23,"total_tokens":28}}
```

### Brak dostępu przez pozostałe adresy

```
curl -m 3 http://127.0.0.1:8080/health  -> curl: (7) Failed to connect (kod 7)
curl -m 3 http://10.0.2.15:8080/health  -> curl: (7) Failed to connect (kod 7)
```

## Porównanie: systemd vs Docker

| Kryterium | systemd (zad. 2) | Docker (zad. 3) |
|---|---|---|
| Miejsce na dysku | 3,7 GB (`/opt/llamafile`) | 3,7 GB (obraz, `docker image ls`); cache buildu do usunięcia przez `docker builder prune` |
| Czas od startu do pierwszej odpowiedzi | 22,1 s (ciepły cache) | 9,3 s (ciepły cache), 10,6 s (zimny cache po `drop_caches`) |
| Zużycie pamięci | 2,2 GB (`systemctl status`, szczyt) | 1,9 GiB po obciążeniu (`docker stats`), limit 3 GiB |
| Kroki na nowej maszynie | 6 (użytkownik i katalogi, pobranie modelu, ufw, plik jednostki, daemon-reload, enable) | 4 (instalacja Dockera, git clone, `.env`, `docker compose up -d`) |

Uwaga: pomiar systemd wykonano przy ciepłym cache, a dla zimnego cache nie wykonano go wcale, więc porównanie czasów jest przybliżone.
