FROM r-base:latest

# ADD SSH https://www.r-bloggers.com/2019/03/securing-a-dockerized-plumber-api-with-ssl-and-basic-authentication/

# Install system dependencies for R packages including libsodium-dev
RUN apt-get update && apt-get install -y --no-install-recommends \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    zlib1g-dev \
    libsodium-dev \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Install required R packages
RUN R -e "install.packages(c('plumber', 'httr', 'jsonlite', 'dotenv', 'RPostgreSQL', 'stringr', 'DBI'), repos='https://cloud.r-project.org')"

# Set the working directory
WORKDIR /api

# Expose the port plumber will listen on
EXPOSE 8000

# Command to run when container starts with simple HTTP (no SSL)
CMD ["R", "-e", "library(plumber); pr <- plumb('/api/start.R'); pr$run(host='0.0.0.0', port=8000)"]