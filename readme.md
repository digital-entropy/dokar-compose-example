# App Deployer

A simple containerized setup for deploying App applications.

## Installation

1. Copy .env.example to .env

   1.1. Pay attention in this certain env

   ```
   DOCKER_IMAGE=registry.example.com/app/app
   DOCKER_TAG=experiment
   DOCKER_PORT=8082
   DOCKER_VOLUMES_DRIVER=local
   DOCKER_NETWORKS_DRIVER=bridge
   DOCKER_HOSTNAME=app-from-unknown-server
   ```

   1.2. Login to registry

   ```
   docker login registry.example.com
   ```

2. Generate new `APP_KEY` by running

   ```
   ./nge a key:generate --show
   ```

3. Run:

   ```
   ./nge install
   ```

4. (Optional) you may need to restore database, run this command to restore it

   ```
   ./nge mysql:import < /path/to/file.sql
   ```

5. (Optional) Start Extra Services

   **PgBouncer (Connection Pooling)**
   If you need connection pooling, configure `PGBOUNCER_UPSTREAM_*` in your `.env` and start the service:
   ```bash
   ./nge up pgbouncer
   ```
   *Update your app's `DB_HOST` to use `pgbouncer`.*

   **Sentry Relay**
   To run a local Sentry Relay, set `SENTRY_UPSTREAM` in your `.env` and start the service:
   ```bash
   ./nge up sentry-relay
   ```
   *Point your app's Sentry DSN to this local relay.*
