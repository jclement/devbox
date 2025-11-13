#!/bin/bash
# PostgreSQL Service
# Handles PostgreSQL 16 database service

set -e

SERVICE_NAME="postgres"
PGVERSION="16"
PGCLUSTER="main"
PGDATA="/var/lib/postgresql/$PGVERSION/$PGCLUSTER"

case "${1:-start}" in
    install)
        echo "[postgres] Installing PostgreSQL $PGVERSION..."

        # Add PostgreSQL repository
        echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
        wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -

        # Install PostgreSQL
        apt-get update
        apt-get install -y postgresql-$PGVERSION postgresql-contrib-$PGVERSION
        rm -rf /var/lib/apt/lists/*

        # Setup directories and permissions
        mkdir -p /var/run/postgresql
        chown postgres:postgres /var/run/postgresql
        rm -rf /etc/postgresql /var/lib/postgresql

        echo "[postgres] PostgreSQL $PGVERSION installed successfully"
        ;;

    start)
        echo "[postgres] Starting PostgreSQL..."

        # Link /var/lib/postgresql to /state for data persistence
        if [ ! -L "/var/lib/postgresql" ]; then
            mkdir -p /state/postgres/data
            rm -rf /var/lib/postgresql
            ln -sf /state/postgres/data /var/lib/postgresql
            chown -h postgres:postgres /var/lib/postgresql
        fi

        # Link /etc/postgresql to /state for config persistence
        if [ ! -L "/etc/postgresql" ]; then
            mkdir -p /state/postgres/config
            rm -rf /etc/postgresql
            ln -sf /state/postgres/config /etc/postgresql
        fi

        # Initialize cluster if needed
        if [ ! -f "$PGDATA/PG_VERSION" ]; then
            echo "[postgres] Initializing cluster..."
            pg_createcluster $PGVERSION $PGCLUSTER
        fi

        # Configure PostgreSQL to listen on localhost only (Tailscale forwards from its IP)
        cat > /etc/postgresql/$PGVERSION/$PGCLUSTER/pg_hba.conf <<EOF
# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   all             all                                     peer
host    all             all             127.0.0.1/32            md5
host    all             all             ::1/128                 md5
EOF

        sed -i "/^listen_addresses/d" /etc/postgresql/$PGVERSION/$PGCLUSTER/postgresql.conf
        echo "listen_addresses = 'localhost'" >> /etc/postgresql/$PGVERSION/$PGCLUSTER/postgresql.conf

        # Start PostgreSQL temporarily if we need to create database
        if [ ! -f "/etc/postgres-db-created" ]; then
            echo "[postgres] First run - creating database..."
            pg_ctlcluster $PGVERSION $PGCLUSTER start
            sleep 2

            # Set password and create database
            su - postgres -c "psql -c \"ALTER USER postgres PASSWORD '${POSTGRES_PASSWORD:-postgres}';\"" || true

            DB_EXISTS=$(su - postgres -c "psql -lqt | cut -d \\| -f 1 | grep -qw ${POSTGRES_DB:-devdb} && echo yes || echo no")
            if [ "$DB_EXISTS" = "no" ]; then
                su - postgres -c "psql -c \"CREATE DATABASE ${POSTGRES_DB:-devdb};\""

                # Load seed if provided
                if [ -n "$DB_SEED_FILE" ] && [ -f "/workspace/$DB_SEED_FILE" ]; then
                    echo "[postgres] Loading seed file: $DB_SEED_FILE"
                    su - postgres -c "psql -d ${POSTGRES_DB:-devdb} -f /workspace/$DB_SEED_FILE" || true
                fi
            fi

            touch /etc/postgres-db-created
            pg_ctlcluster $PGVERSION $PGCLUSTER stop
            sleep 2
        fi

        # Generate .pgpass for the user (DO NOT EDIT MANUALLY - regenerated on startup)
        if [ -n "$USERNAME" ]; then
            USER_HOME="/home/${USERNAME}"
            cat > ${USER_HOME}/.pgpass <<EOF
# WARNING: This file is auto-generated on every startup. Do not edit manually.
# To customize, modify services/10-postgres.sh
localhost:5432:*:postgres:${POSTGRES_PASSWORD:-postgres}
*:5432:*:postgres:${POSTGRES_PASSWORD:-postgres}
EOF
            chmod 600 ${USER_HOME}/.pgpass
            chown ${USERNAME}:${USERNAME} ${USER_HOME}/.pgpass 2>/dev/null || true
        fi

        # Start PostgreSQL
        exec su - postgres -c "/usr/lib/postgresql/$PGVERSION/bin/postgres -D $PGDATA -c config_file=/etc/postgresql/$PGVERSION/$PGCLUSTER/postgresql.conf"
        ;;

    stop)
        echo "[postgres] Stopping PostgreSQL..."
        pg_ctlcluster $PGVERSION $PGCLUSTER stop || true
        ;;

    status)
        pg_ctlcluster $PGVERSION $PGCLUSTER status
        ;;

    *)
        echo "Usage: $0 {install|start|stop|status}"
        exit 1
        ;;
esac
