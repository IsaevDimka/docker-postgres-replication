-- ===== ROLES =====
DO $do$
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='role_ro') THEN
            CREATE ROLE role_ro NOLOGIN;
        END IF;

        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='role_rw') THEN
            CREATE ROLE role_rw NOLOGIN;
        END IF;

        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='maindb_owner') THEN
            CREATE ROLE maindb_owner LOGIN;
        END IF;

        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='user_owner') THEN
            CREATE ROLE user_owner LOGIN PASSWORD '123';
            GRANT maindb_owner TO user_owner;
        END IF;
    END
$do$;

-- ===== DATABASE =====
SELECT format(
           'CREATE DATABASE %I OWNER %I ENCODING %L TEMPLATE template0',
           'maindb', 'maindb_owner', 'UTF8'
       )
WHERE NOT EXISTS (
    SELECT 1 FROM pg_database WHERE datname = 'maindb'
)\gexec

\connect maindb

ALTER DATABASE maindb SET datestyle TO 'ISO, DMY';

REVOKE ALL ON DATABASE maindb FROM PUBLIC;
GRANT CONNECT ON DATABASE maindb TO maindb_owner;
