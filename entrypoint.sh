#!/bin/bash
set -e

echo "Starting AzerothCore Container Entrypoint..."

# --- Install Mods ---
NEED_RECOMPILE=false

# 1. From Environment Variable
if [ -n "$AC_MODS" ]; then
    echo "Installing mods from AC_MODS..."
    cd /azerothcore/modules
    for repo in $AC_MODS; do
        mod_name=$(basename "$repo" .git)
        if [ ! -d "$mod_name" ]; then
            echo "Cloning mod: $mod_name"
            if git clone "$repo" "$mod_name"; then
                NEED_RECOMPILE=true
            fi
        else
            echo "Mod $mod_name already exists."
        fi
    done
fi

# 2. From Volume
if [ -d "/modules-mount" ]; then
    # If directory is not empty
    if [ "$(ls -A /modules-mount)" ]; then
        echo "Installing mods from /modules-mount..."
        # Copy new mods, do not overwrite existing ones
        cp -rn /modules-mount/* /azerothcore/modules/ && NEED_RECOMPILE=true || true
    fi
fi

# --- Compilation ---
BIN_DIR="/azerothcore/env/dist/bin"
if [ ! -f "$BIN_DIR/worldserver" ] || [ "$RECOMPILE" = "true" ] || [ "$NEED_RECOMPILE" = "true" ]; then
    echo "Compiling AzerothCore... (This may take a while)"
    cd /azerothcore/build
    cmake ../ -DCMAKE_INSTALL_PREFIX=/azerothcore/env/dist -DCMAKE_C_COMPILER=/usr/bin/clang -DCMAKE_CXX_COMPILER=/usr/bin/clang++ -DWITH_WARNINGS=1 -DTOOLS_BUILD=all -DSCRIPTS=static -DMODULES=static
    make -j $(nproc)
    make install
    echo "Compilation complete."
else
    echo "Binaries found. Skipping compilation."
fi

# --- MySQL Setup ---
echo "Starting MySQL..."
# Ensure MySQL directories exist and have correct permissions
mkdir -p /var/run/mysqld
chown -R mysql:mysql /var/run/mysqld /var/lib/mysql

# Initialize MySQL if the data directory is empty
if [ -z "$(ls -A /var/lib/mysql)" ]; then
    echo "Initializing MySQL data directory..."
    mysqld --initialize-insecure --user=mysql --datadir=/var/lib/mysql
    echo "MySQL initialized."
fi

# Start MySQL in the background
mysqld_safe --user=mysql &
MYSQL_PID=$!

# Wait for MySQL to be ready
echo "Waiting for MySQL to start..."
until mysqladmin ping -h localhost --silent; do
    echo "Waiting for mysqld..."
    sleep 2
done

# Configure MySQL User and Databases
echo "Configuring MySQL users and databases..."
# Set root password if provided (optional, script uses passwordless local root or specific user)
# We recreate the user script logic here to ensure permissions are correct every startup
mysql -u root <<EOF
CREATE USER IF NOT EXISTS 'acore'@'localhost' IDENTIFIED BY 'acore';
ALTER USER 'acore'@'localhost' WITH MAX_QUERIES_PER_HOUR 0 MAX_CONNECTIONS_PER_HOUR 0 MAX_UPDATES_PER_HOUR 0;
GRANT ALL PRIVILEGES ON * . * TO 'acore'@'localhost' WITH GRANT OPTION;
CREATE DATABASE IF NOT EXISTS \`acore_world\` DEFAULT CHARACTER SET UTF8MB4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS \`acore_characters\` DEFAULT CHARACTER SET UTF8MB4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS \`acore_auth\` DEFAULT CHARACTER SET UTF8MB4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON \`acore_world\` . * TO 'acore'@'localhost' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON \`acore_characters\` . * TO 'acore'@'localhost' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON \`acore_auth\` . * TO 'acore'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF

# --- Remote User Configuration ---
if [ -n "$MYSQL_REMOTE_USER" ] && [ -n "$MYSQL_REMOTE_PASSWORD" ] && [ -n "$MYSQL_REMOTE_IP" ]; then
    echo "Configuring remote MySQL user: $MYSQL_REMOTE_USER for IP: $MYSQL_REMOTE_IP"
    mysql -u root <<EOF
CREATE USER IF NOT EXISTS '$MYSQL_REMOTE_USER'@'$MYSQL_REMOTE_IP' IDENTIFIED BY '$MYSQL_REMOTE_PASSWORD';
GRANT ALL PRIVILEGES ON \`acore_world\` . * TO '$MYSQL_REMOTE_USER'@'$MYSQL_REMOTE_IP';
GRANT ALL PRIVILEGES ON \`acore_characters\` . * TO '$MYSQL_REMOTE_USER'@'$MYSQL_REMOTE_IP';
GRANT ALL PRIVILEGES ON \`acore_auth\` . * TO '$MYSQL_REMOTE_USER'@'$MYSQL_REMOTE_IP';
FLUSH PRIVILEGES;
EOF
else
    echo "Remote MySQL configuration skipped (Env vars not set)."
fi

# --- Configuration Files ---
echo "Checking configuration files..."
CONF_DIR="/azerothcore/env/dist/etc"
mkdir -p "$CONF_DIR"

if [ ! -f "$CONF_DIR/worldserver.conf" ]; then
    echo "Copying worldserver.conf.dist to worldserver.conf"
    cp "$CONF_DIR/worldserver.conf.dist" "$CONF_DIR/worldserver.conf"
fi

if [ ! -f "$CONF_DIR/authserver.conf" ]; then
    echo "Copying authserver.conf.dist to authserver.conf"
    cp "$CONF_DIR/authserver.conf.dist" "$CONF_DIR/authserver.conf"
fi

if [ ! -f "$CONF_DIR/modules/playerbots.conf" ]; then
    if [ -f "$CONF_DIR/modules/playerbots.conf.dist" ]; then
        echo "Copying playerbots.conf.dist to playerbots.conf"
        cp "$CONF_DIR/modules/playerbots.conf.dist" "$CONF_DIR/modules/playerbots.conf"
    fi
fi

# --- Client Data ---
# The user script runs ./acore.sh client-data which downloads maps, mmaps, vmaps, dbc
echo "Checking client data..."
DATA_DIR="/azerothcore/env/dist/data"
# Check if data directory is empty or missing key folders
if [ ! -d "$DATA_DIR/dbc" ] || [ ! -d "$DATA_DIR/maps" ] || [ ! -d "$DATA_DIR/vmaps" ] || [ ! -d "$DATA_DIR/mmaps" ]; then
    echo "Client data missing. Downloading... (This may take a while)"
    cd /azerothcore
    ./acore.sh client-data
else
    echo "Client data appears to be present."
fi

# --- Start Servers with Tmux ---
echo "Starting Auth and World servers in tmux..."
cd /azerothcore/env/dist/bin

AUTH_SESSION="auth-session"
WORLD_SESSION="world-session"

# Check if sessions already exist (in case of container restart without kill), otherwise create
tmux has-session -t $AUTH_SESSION 2>/dev/null || tmux new-session -d -s $AUTH_SESSION
tmux has-session -t $WORLD_SESSION 2>/dev/null || tmux new-session -d -s $WORLD_SESSION

# Send commands
# We use a loop or check to prevent multiple starts if the container is restarted but processes persisted? 
# Docker restarts kill processes, so we assume fresh start.

echo "Launching authserver..."
tmux send-keys -t $AUTH_SESSION "./authserver" C-m

echo "Launching worldserver..."
tmux send-keys -t $WORLD_SESSION "./worldserver" C-m

echo "=========================================="
echo "Server Startup Complete!"
echo "To access the world server console, run: docker exec -it <container_name> bash -c 'tmux attach -t world-session'"
echo "To access the auth server console, run: docker exec -it <container_name> bash -c 'tmux attach -t auth-session'"
echo "=========================================="

# Keep the container running
# We tail the logs if they exist, or just wait. 
# Better: monitor the tmux sessions or wait on the background MySQL process.
# If we just sleep infinity, that works.
sleep infinity
