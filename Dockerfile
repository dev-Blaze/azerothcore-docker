FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y \
    git curl unzip sudo libreadline-dev cmake make gcc g++ clang \
    libssl-dev libbz2-dev libncurses-dev libboost-all-dev tmux gnupg \
    mysql-server libmysqlclient-dev mysql-client \
    vim nano iputils-ping \
    && rm -rf /var/lib/apt/lists/*

# Configure MySQL (bind address and disable binary logging)
RUN sed -i 's/^bind-address.*/bind-address = 0.0.0.0/' /etc/mysql/mysql.conf.d/mysqld.cnf && \
    sed -i 's/^mysqlx-bind-address.*/mysqlx-bind-address = 0.0.0.0/' /etc/mysql/mysql.conf.d/mysqld.cnf && \
    echo "disable_log_bin" >> /etc/mysql/mysql.conf.d/mysqld.cnf

# Clone AzerothCore
WORKDIR /azerothcore
RUN git clone https://github.com/mod-playerbots/azerothcore-wotlk.git . --branch=Playerbot

# Clone Playerbots module
WORKDIR /azerothcore/modules
RUN git clone https://github.com/mod-playerbots/mod-playerbots.git mod-playerbots --branch=master

# Build setup (Compilation moved to entrypoint.sh)
WORKDIR /azerothcore
RUN mkdir -p build

# Setup Aliases
RUN echo "alias wow='tmux attach -t world-session'" >> /root/.bashrc && \
    echo "alias auth='tmux attach -t auth-session'" >> /root/.bashrc && \
    echo "alias stop='tmux kill-server'" >> /root/.bashrc && \
    echo "alias pb='nano /azerothcore/env/dist/etc/modules/playerbots.conf'" >> /root/.bashrc && \
    echo "alias world='nano /azerothcore/env/dist/etc/worldserver.conf'" >> /root/.bashrc

# Copy Entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose Ports
# 3724: Auth Server
# 8085: World Server
# 3306: MySQL
EXPOSE 3724 8085 3306

# Volume for data persistence
# /var/lib/mysql: Database files
# /azerothcore/env/dist/etc: Config files
# /azerothcore/env/dist/data: Client data (maps, vmaps, etc)
VOLUME ["/var/lib/mysql", "/azerothcore/env/dist/etc", "/azerothcore/env/dist/data"]

ENTRYPOINT ["/entrypoint.sh"]
