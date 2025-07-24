library(plumber)

# Create and run the API locally on localhost:7001
#* @apiTitle Local API
#* @apiDescription This is a local API for testing purposes.
#* @apiVersion 1.0.0
pr <- plumb("./start.R")
pr$run(host = "127.0.0.1", port = 7001)