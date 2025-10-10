# plumber.R
# Load plumber and required libraries
library(plumber)
library(jsonlite)
library(httr)
library(RPostgreSQL)

library(bwi.derived)

# Determine the working directory
current_file_dir <- getwd()

# Construct the path to the .env file in the parent directory
env_file_path <- file.path(dirname(current_file_dir), ".env")

if (file.exists(env_file_path)) {
  cat("Loading environment variables from .env file...\n")
  dotenv::load_dot_env(file = env_file_path)
} else {
  cat(".env file not found at path:", env_file_path, "\n")
}


# --- Configuration (read from environment variables) ---
supabase_url <- Sys.getenv("SUPABASE_URL")
supabase_anon_token <- Sys.getenv("SUPABASE_ANON_TOKEN")
user_token <- Sys.getenv("SUPABASE_USER_TOKEN")
service_role_token <- Sys.getenv("SUPABASE_SERVICE_ROLE_TOKEN")

path <- file.path(dirname(getwd()), "r", "api")


#* @apiTitle R API
#* @apiDescription This is an API for writing data to Supabase and a file.
#* @apiVersion 1.0.0

# Make sure CORS filter runs first
#* @filter cors
#* @preempt auth
cors <- function(req, res) {
    
    res$setHeader("Access-Control-Allow-Origin", "*")
    res$setHeader("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
    res$setHeader("Access-Control-Allow-Headers", "Authorization, Content-Type, Accept, Origin, X-Requested-With")
    res$setHeader("Access-Control-Max-Age", "3600")
    
    # Print debugging info
    cat("CORS filter executed\n")
    cat("Request method:", req$REQUEST_METHOD, "\n")
    
    if (req$REQUEST_METHOD == "OPTIONS") {
        cat("Handling OPTIONS request\n")
        res$status <- 200
        return(list(status = "ok"))
    }
    
    plumber::forward()
}

# Authentication filter middleware
#* @filter auth
function(req, res) {
    # Skip auth for paths that don't need it (e.g., __docs__)
    if (!grepl("^/run-script/", req$PATH_INFO)) {
        forward()
        return()
    }
    
    # Check for the Authorization header
    auth_header <- req$HTTP_AUTHORIZATION
    
    if(is.null(auth_header) || !grepl("^Bearer\\s+", auth_header)) {
        res$status <- 401
        return(list(error = "Unauthorized: Bearer token required"))
    }
    
    # Extract the token
    token <- sub("^Bearer\\s+", "", auth_header)

    # Check if the token is empty
    if (token == "") {
        res$status <- 401
        return(list(error = "Unauthorized: Empty Bearer token"))
    }
    
    # Validate the token with Supabase    
    if(supabase_url == "") {
        stop("SUPABASE_URL environment variable is not set")
    }
    if(is.null(supabase_anon_token) || supabase_anon_token == "") {
        stop("SUPABASE_ANON_TOKEN environment variable is not set")
    }

    # if token is not equal service_role_token
    if (token != service_role_token) {

        # Make a request to Supabase to validate the token
        response <- tryCatch({
            httr::GET(
                paste0(supabase_url, "/auth/v1/user"),
                httr::add_headers(
                    Authorization = paste0("Bearer ", token),
                    apikey = token
                )
            )
        }, error = function(e) {
            print(e);
            return(NULL)
        })
        # Print debugging info
        cat("Auth filter executed3\n")

        # Check the response status
        if(is.null(response) || httr::status_code(response) != 200) {

            # Set appropriate status code
            if(is.null(response)) {
                res$status <- 401
                cat("Connection error: Could not validate token\n")
            } else {
                res$status <- httr::status_code(response)
                cat("Message:", httr::content(response, "text"), "\n")
            }
            cat("Unauthorized: Invalid token:", token, "\n")
            return(list(error = "Unauthorized: Invalid token"))
        }

        # Store user info in request for later use if needed
        user_data <- httr::content(response)
        req$user <- user_data
    }

    # Save the validated token as system environment variable
    Sys.setenv(SUPABASE_USER_TOKEN = token)

    # Print debugging info
    cat("Auth filter executed6\n")

    # Continue to the next handler
    forward()
}

#* Write File to Output
#* @get /run-script/<script_name>
function(req, res) {

    if (supabase_url == "") {
        return(list(error = "Environment variable SUPABASE_URL is not set"))
    } else if (is.null(supabase_anon_token) || supabase_anon_token == "") {
        return(list(error = "Environment variable SUPABASE_ANON_TOKEN is not set"))
    } else if (is.null(service_role_token) || service_role_token == "") {
        return(list(error = "Environment variable SUPABASE_SERVICE_ROLE_TOKEN is not set"))
    }

    # Get the content from the request
    content <- req$QUERY_STRING # not yet supported

    # Example Query: http://127.0.0.1:7001/run-script/write_to_template
    script_name <- req$args$script_name  # Change from req$script to req$args$script_name

    data_to_insert <- list(
        script = script_name,
        action = "started"
    )
    body <- toJSON(data_to_insert, auto_unbox = TRUE)

    # Start logging in Database
    headers <- c(
        "Content-Type" = "application/json",
        "apikey" = supabase_anon_token,
        "Authorization" = paste0("Bearer ", service_role_token),
        "Content-Profile" = "public",
        "Prefer" = "return=representation"
    )

    # log supabase_url
    cat("Supabase URL:", supabase_url, "\n")

    response <- tryCatch({
        POST(
            url = paste0(supabase_url, "/rest/v1/r_monitor"),
            add_headers(headers),
            body = body
        )
    }, error = function(e) {
        cat("Error connecting to Supabase:", e$message, "\n")
        return(list(error = paste("Failed to connect to Supabase:", e$message)))
    })

    # Check if response is an error list
    if (is.list(response) && !is.null(response$error)) {
        return(response)
    }

    # Check response status
    if (status_code(response) != 201 && status_code(response) != 200) {
        return(list(error = paste("Failed to log to Supabase. Status:", status_code(response))))
    }

    # Get the added row id with proper error handling
    response_content <- content(response)
    added_row_id <- NULL

    # With Prefer: return=representation, the response should contain the inserted row(s)
    if (is.list(response_content) && length(response_content) > 0) {
        # Response should be an array with the inserted row
        if (is.list(response_content[[1]]) && !is.null(response_content[[1]]$id)) {
            added_row_id <- response_content[[1]]$id
            cat("Successfully extracted row ID:", added_row_id, "\n")
        }
    }

    if (is.null(added_row_id)) {
        cat("Warning: Could not extract ID from response\n")
        cat("Response content:", jsonlite::toJSON(response_content), "\n")
        # Continue without ID for logging
    }

    # Calculate base path to the 'r' directory relative to start.R's location
    # Assumes start.R is in an 'api' subdirectory of the project root
    project_root <- dirname(getwd())
    r_base_path <- file.path(project_root, "r")

    # Construct the full path to the script requested via the API
    script_path <- file.path(r_base_path, "api", paste0(script_name, ".R"))

    if (!file.exists(script_path)) {
        res$status <- 404
        return(list(error = paste("Script not found:", script_name)))
    }
    
    # Create a new environment to source the script into
    script_env <- new.env(parent = globalenv())
    source(script_path, local = script_env)

    postgres_connection <- tryCatch({
        dbConnect(RPostgreSQL::PostgreSQL(), # Explicit namespace
            host=Sys.getenv("HOST_DOCKER_INTERNAL"),
            user=Sys.getenv("SUPABASE_PG_USER"),
            password=Sys.getenv("SUPABASE_PG_PW"),
            port=Sys.getenv("SUPABASE_PG_PORT"),
            dbname=Sys.getenv("SUPABASE_PG_DB")
        )
    }, error = function(e) {
        stop(paste("Failed to connect to PostgreSQL database:", e$message))
    })

    # Ensure connection is closed even if request is canceled
    on.exit(dbDisconnect(postgres_connection))

    # Call the function from the script
    if (exists('main', envir = script_env)) {
        # Check if the main function accepts parameters
        main_formals <- formals(get('main', envir = script_env))
        num_formals <- length(main_formals)
        
        # Call main() with appropriate arguments based on its definition
        if (num_formals >= 2) {
            result <- script_env$main(postgres_connection, r_base_path)
        } else if (num_formals == 1) {
            result <- script_env$main(postgres_connection)
        } else {
            result <- script_env$main()
        }
    } else {
        result <- list(error = paste("Function 'main' not found in script:", script_name))
    }

    dbDisconnect(postgres_connection)

    if (!is.null(added_row_id)) {
        data_to_insert <- list(
            action = "finished",
            details = jsonlite::toJSON(result, auto_unbox = TRUE),
            timestamp_finished = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z") # Postgrest timestamptz
        )
        body <- toJSON(data_to_insert, auto_unbox = TRUE)

        cat("Attempting to update row ID:", added_row_id, "\n")

        # Update to added_row_id
        update_response <- tryCatch({
            PATCH(
                url = paste0(supabase_url, "/rest/v1/r_monitor?id=eq.", added_row_id),
                add_headers(headers),
                body = body
            )
        }, error = function(e) {
            cat("Error updating Supabase log:", e$message, "\n")
            return(NULL)
        })
    } else {
        cat("No row ID available for updating log\n")
    }
    

    # Return the result
    return(list(message = "Script executed successfully", result = result))
}

#* Return Json Response with list of files in the r-api directory
#* @get /get-scripts
function(req, res) {
    # Calculate base path to the 'r-api' directory
    project_root <- dirname(getwd())
    r_api_path <- file.path(project_root, "r", "api")

    # Get the list of R scripts in the 'r-api' directory
    script_files <- list.files(r_api_path, pattern = "\\.R$", full.names = TRUE)

    # Return the list file names as a JSON response
    script_files <- gsub(paste0(r_api_path, "/"), "", script_files)  # Remove the base path for cleaner output
    script_files <- gsub("\\.R$", "", script_files)  # Remove the .R extension
    return(script_files)
}