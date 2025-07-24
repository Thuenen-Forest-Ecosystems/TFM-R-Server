# FUK-R

## Requirements

- [Docker Compose](https://docs.docker.com/compose/install/)
- [Node.js](https://nodejs.org/en/download/)

## Setup
```bash
git clone --recurse-submodules -j8 https://gitlab.opencode.de/lfe/fuk/fuk-r-server.git
cd fuk-r-server
cp .env.example .env
nano .env # edit the file and set the environment variables
```

## Getting Started

```bash
docker build -t plumber-api .
docker-compose up -d
```

## Stop

```bash
docker-compose down
npm stop
```


## Webhook - Server

The hook-server is a simple server that listens for incoming requests from the [webhook](https://docs.gitlab.com/user/project/integrations/webhooks/). It will update the code and restart the R-Server.

### Install dependencies

[pm2](https://pm2.keymetrics.io/docs/usage/quick-start/) is used to manage the server. It will automatically restart the server if it crashes.

```bash
# npm install # install all dependencies
npm install pm2 -g # install pm2 globally
pm2 install pm2-logrotate # install pm2-logrotate globally
```

### Commands

```bash
npm start # start the server
npm run restart # restart the server
npm run logs # view the logs
npm stop # stop the server
```
