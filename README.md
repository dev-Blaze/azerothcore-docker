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

### Shell Aliases

The following convenient aliases are available when you access the container shell (`docker exec -it azerothcore bash`):

-   `wow`: Attach to the **World Server** console (tmux session).
-   `auth`: Attach to the **Auth Server** console (tmux session).
-   `stop`: Stop the servers (kills tmux server).
-   `pb`: Edit `playerbots.conf` with nano.
-   `world`: Edit `worldserver.conf` with nano.
-   `compile`: Run the AzerothCore compilation (`./acore.sh compiler all`).
-   `build`: Run the AzerothCore build (`./acore.sh compiler build`).
-   `update`: Git pull the main repo and playerbots module.
-   `updatemods`: Update all modules in the `modules` directory.
-   `ah`: Edit `mod_ahbot.conf` with nano.

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

### Remote MySQL Access

To allow a remote user (e.g., from your host machine or another container) to access the database, you can configure it using a `.env` file.

1.  Copy `.env.example` to `.env`:
    ```bash
    cp .env.example .env
    ```
2.  Edit `.env` and uncomment/set the variables:
    ```ini
    MYSQL_REMOTE_USER=myuser
    MYSQL_REMOTE_PASSWORD=mypassword
    MYSQL_REMOTE_IP=192.168.1.5  # IP address allowed to connect
    # Use '%' for any IP (not recommended for production)
    ```
3.  Restart the container:
    ```bash
    docker compose up -d
    ```

### Adding Custom Mods

You can easily add extra modules (like Transmog, Autobalance, etc.) to your server.

**Method 1: Using `.env` (Recommended)**

1.  Add the `AC_MODS` variable to your `.env` file with a space-separated list of Git URLs:
    ```ini
    AC_MODS=https://github.com/azerothcore/mod-transmog.git https://github.com/azerothcore/mod-autobalance.git
    ```
2.  Restart the container. The startup script will clone the mods and automatically trigger a recompilation of the core.
    ```bash
    docker compose up -d
    ```

**Method 2: Using Volume Mount**

1.  Place your mod directories inside `./acore-data/modules` on your host machine.
2.  Restart the container. The script will detect the new files and recompile the core.

## Database Backups with Velld

You can use [Velld](https://github.com/dendianugerah/velld), a self-hosted database backup tool, to automate backups of your AzerothCore database. The "Remote MySQL Access" feature allows Velld to connect to the database container.

### Setting up Velld

1.  **Update `.env`**: Add the following configuration for Velld to your `.env` file:
    ```ini
    # Velld Configuration
    NEXT_PUBLIC_API_URL=http://localhost:8080
    JWT_SECRET=your_jwt_secret_here_32_chars  # Run: openssl rand -hex 32
    ENCRYPTION_KEY=your_enc_key_here_64_chars # Run: openssl rand -hex 32
    ADMIN_USERNAME_CREDENTIAL=admin
    ADMIN_PASSWORD_CREDENTIAL=password
    ALLOW_REGISTER=false
    ```

2.  **Update `docker-compose.yml`**: Add the Velld services to your `docker-compose.yml` file so they share the same network:
    ```yaml
    services:
      # ... existing acore service ...

      velld-api:
        image: ghcr.io/dendianugerah/velld/api:latest
        ports:
          - "8080:8080"
        env_file:
          - .env
        volumes:
          - ./acore-data/velld-data:/app/data
          - ./acore-data/backups:/app/backups
        restart: unless-stopped

      velld-web:
        image: ghcr.io/dendianugerah/velld/web:latest
        ports:
          - "3000:3000"
        environment:
          NEXT_PUBLIC_API_URL: ${NEXT_PUBLIC_API_URL}
          ALLOW_REGISTER: ${ALLOW_REGISTER}
        depends_on:
          - velld-api
        restart: unless-stopped
    ```

3.  **Restart**: Run `docker compose up -d`.

4.  **Configure Backup**:
    *   Open Velld at `http://localhost:3000`.
    *   Login with the credentials defined in `.env`.
    *   Create a new **Connection**:
        *   **Type**: MySQL
        *   **Host**: `azerothcore` (The container name)
        *   **Port**: `3306`
        *   **User**: The value of `MYSQL_REMOTE_USER`
        *   **Password**: The value of `MYSQL_REMOTE_PASSWORD`
        *   **Database**: `acore_world` (or `acore_characters`, `acore_auth`)

## Container Details

-   **OS:** Ubuntu 24.04
-   **Ports:**
    -   `3724`: Auth Server
    -   `8085`: World Server
    -   `3306`: MySQL
-   **Environment:**
    -   `acore` user is automatically created for the database.
    -   `root` user is used inside the container shell.
