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
