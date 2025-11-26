# AzerothCore with Playerbots (Dockerized)

This project provides a single Docker container running AzerothCore with the Playerbots module, including a built-in MySQL server. It uses Ubuntu 24.04 as the base image.

## Prerequisites

- Docker
- Docker Compose

## Quick Start (Easy Install)

This method uses the pre-built image from GitHub Container Registry.

1.  **Start the Server:**
    ```bash
    docker compose up -d
    ```
    *Note: The first run will be significantly longer as it compiles the server binaries and downloads client data. Subsequent runs will be faster.*

2.  **Monitor Progress:**
    You can check the logs to see the compilation and startup progress:
    ```bash
    docker compose logs -f
    ```

## Build from Source

If you want to build the image yourself (e.g., to modify the code):

1.  **Uncomment the `build: .` line in `docker-compose.yml`.**
2.  **Build and Start:**
    ```bash
    docker compose up -d --build
    ```

## Accessing the Server Console

The servers run inside `tmux` sessions within the container. To access them:

### World Server Console (GM Commands)
```bash
docker exec -it azerothcore bash -c "tmux attach -t world-session"
```
Or use the alias inside the container:
```bash
docker exec -it azerothcore bash
# Then inside the shell:
wow
```
(Press `Ctrl+B` then `D` to detach without stopping the server)

### Auth Server Console
```bash
docker exec -it azerothcore bash -c "tmux attach -t auth-session"
```
Or use the alias inside the container:
```bash
docker exec -it azerothcore bash
# Then inside the shell:
auth
```

## Configuration & Data

The setup persists data in the `./acore-data` directory on your host machine:

-   `./acore-data/mysql`: Database files.
-   `./acore-data/build`: Compilation build files (speeds up recompilation).
-   `./acore-data/env`: Contains binaries (`bin`), configuration (`etc`), and data (`data`).

You can edit configuration files in `./acore-data/env/dist/etc` on your host machine and restart the container to apply changes.

## Database Access

The MySQL server is exposed on port `3306`.
-   **User:** `acore`
-   **Password:** `acore`
-   **Database:** `acore_world`, `acore_characters`, `acore_auth`

## Container Details

-   **OS:** Ubuntu 24.04
-   **Ports:**
    -   `3724`: Auth Server
    -   `8085`: World Server
    -   `3306`: MySQL
-   **Environment:**
    -   `acore` user is automatically created for the database.
    -   `root` user is used inside the container shell.
