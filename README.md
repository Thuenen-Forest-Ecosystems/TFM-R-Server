# FUK-R

## Requirements

- [Docker Compose](https://docs.docker.com/compose/install/)
- [Node.js](https://nodejs.org/en/download/)

## Setup
```bash
git clone --recurse-submodules -j8 https://github.com/Thuenen-Forest-Ecosystems/TFM-R-Server.git
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
