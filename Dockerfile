FROM r-base:latest

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    zlib1g-dev \
    libsodium-dev \
    libpq-dev \
    git \
    openssh-client \
    && rm -rf /var/lib/apt/lists/*

# Install package from public gitlab repository: https://git-dmz.thuenen.de/schnell/bwi.derived.git
RUN R -e "install.packages('remotes', repos='https://cloud.r-project.org')"
COPY ./bwi.derived /tmp/bwi.derived
RUN R -e "remotes::install_local('/tmp/bwi.derived', upgrade = 'never')" > /tmp/install_bwi_derived.log 2>&1

# Verify the installation of bwi.derived
RUN R -e "if (!requireNamespace('bwi.derived', quietly = TRUE)) { stop('bwi.derived package not found after installation') }"

# Install other required R packages
RUN R -e "install.packages(c('plumber', 'httr', 'jsonlite', 'dotenv', 'RPostgres', 'RPostgreSQL', 'stringr', 'DBI'), repos='https://cloud.r-project.org')"

# Set the working directory
WORKDIR /api

# Expose the port plumber will listen on
EXPOSE 8000

# Command to run when container starts
CMD ["R", "-e", "library(plumber); pr <- plumb('/api/start.R'); pr$run(host='0.0.0.0', port=7005)"]