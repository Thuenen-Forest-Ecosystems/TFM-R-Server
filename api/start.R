# plumber.R
# Load plumber and required libraries
library(plumber)
library(jsonlite)
library(httr)

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
apikey <- Sys.getenv("apikey")
user_token <- Sys.getenv("SUPABASE_USER_TOKEN")
service_role_token <- Sys.getenv("SUPABASE_SERVICE_ROLE_TOKEN")

path <- file.path(dirname(getwd()), "r", "r-api")


#* @apiTitle R API
#* @apiDescription This is an API for writing data to Supabase and a file.
#* @apiVersion 1.0.0

# Make sure CORS filter runs first
#* @filter cors
#* @preempt auth
cors <- function(req, res) {
    res$setHeader("Access-Control-Allow-Origin", "*")
    res$setHeader("Access-Control-Allow-Methods", "GET, OPTIONS")
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

    # if token is not equal service_role_token
    if (token != service_role_token) {
            

        # Make a request to Supabase to validate the token
        response <- tryCatch({
            httr::GET(
            paste0(supabase_url, "/auth/v1/user"),
            httr::add_headers(
                Authorization = paste0("Bearer ", token),
                apikey = Sys.getenv("apikey")
            )
            )
        }, error = function(e) {
            print(e);
            return(NULL)
        })
    
        # Check the response status
        if(is.null(response) || httr::status_code(response) != 200) {
            res$status <- 401
            return(list(error = paste0("Unauthorized: Invalid token: ")))
        }
    
  
        # Store user info in request for later use if needed
        user_data <- httr::content(response)
        req$user <- user_data
    }

    # Save the validated token as system environment variable
    Sys.setenv(SUPABASE_USER_TOKEN = token)
  
    # Continue to the next handler
    forward()
}

#* Write File to Output
#* @get /run-script
function(req, res) {

    if (supabase_url == "") {
        return(list(error = "Environment variable SUPABASE_URL is not set"))
    } else if (is.null(apikey) || apikey == "") {
        return(list(error = "Environment variable apikey is not set"))
    } else if (is.null(service_role_token) || service_role_token == "") {
        return(list(error = "Environment variable SUPABASE_SERVICE_ROLE_TOKEN is not set"))
    }

    

    # Get the content from the request
    content <- req$QUERY_STRING # not yet supported

    # Example Query: http://127.0.0.1:7001/run-script?script=write_to_template
    script_name <- req$args$script  # Change from req$script to req$args$script

    data_to_insert <- list(
        script = script_name,
        action = "started"
    )
    body <- toJSON(data_to_insert, auto_unbox = TRUE)

    # Start logging in Database
    headers <- c(
        "Content-Type" = "application/json",
        "apikey" = apikey,
        "Authorization" = paste0("Bearer ", service_role_token),
        "Content-Profile" = "public"
    )

    # Print debugging info
    cat("Received request to run script\n")

    ##response <- POST(
    ##    url = paste0(supabase_url, "/rest/v1/r_monitor"),
    ##    add_headers(headers),
    ##    body = body
    ##)

    # Print debugging info
    cat("after monitor\n")


    # Calculate base path to the 'r' directory relative to start.R's location
    # Assumes start.R is in an 'api' subdirectory of the project root
    project_root <- dirname(getwd())
    r_base_path <- file.path(project_root, "r")

    # Construct the full path to the script requested via the API
    script_path <- file.path(r_base_path, "r-api", paste0(script_name, ".R"))

    if (!file.exists(script_path)) {
        res$status <- 404
        return(list(error = paste("Script not found:", script_name)))
    }
    
    # Create a new environment to source the script into
    script_env <- new.env(parent = globalenv())
    source(script_path, local = script_env)

    # Call the function from the script
    if (exists('main', envir = script_env)) {
        # Check if the main function accepts parameters
        main_formals <- formals(get('main', envir = script_env))
        
        # Call main() with or without parameters based on its definition
        if (length(main_formals) > 0) {
            result <- script_env$main(r_base_path)
        } else {
            result <- script_env$main()
        }
    } else {
        result <- list(error = paste("Function 'main' not found in script:", script_name))
    }

    data_to_insert <- list(
        script = script_name,
        action = "finished",
        details = jsonlite::toJSON(result, auto_unbox = TRUE)
    )
    body <- toJSON(data_to_insert, auto_unbox = TRUE)

    ##response <- POST(
    ##    url = paste0(supabase_url, "/rest/v1/r_monitor"),
    ##    add_headers(headers),
    ##    body = body
    ##)

    # Return the result
    return(list(message = "Script executed successfully", result = result))
}

#* Return Json Response with list of files in the r-api directory
#* @get /get-scripts
function(req, res) {
    # Calculate base path to the 'r-api' directory
    project_root <- dirname(getwd())
    r_api_path <- file.path(project_root, "r", "r-api")

    # Get the list of R scripts in the 'r-api' directory
    script_files <- list.files(r_api_path, pattern = "\\.R$", full.names = TRUE)

    # Return the list file names as a JSON response
    script_files <- gsub(paste0(r_api_path, "/"), "", script_files)  # Remove the base path for cleaner output
    script_files <- gsub("\\.R$", "", script_files)  # Remove the .R extension
    return(script_files)
}