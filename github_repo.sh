#!/bin/bash

# Configuration variables

REPO_URL="git@github.com:athlour/QuantTrading.git"     # Replace with your SSH repo URL
TARGET_DIR="/home/quant/quantrepo"                    # Replace with the target folder path
LOG_FILE="/home/quant/quantrepo.log"                  # Path to the log file
SSH_KEY="/home/quant/id_ed25519"                                  # Path to your private SSH key
BRANCH="master"                                         # Branch to pull from, can be changed as needed
REPO_NAME="quant trading"                               # Repository name for logging purposes
DOCKER_IMAGE_NAME="quant_trading_app"                   # Base name for the Docker image




# Function to log messages with timestamps
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function to generate the next Docker image tag with floating-point versioning
generate_next_tag() {
    # Get the list of tags for the Docker image, sort them, and find the highest version number
    existing_tags=$(docker images --format "{{.Tag}}" "$DOCKER_IMAGE_NAME" | grep -E '^v[0-9]+\.[0-9]+$' | sort -V)

    if [ -z "$existing_tags" ]; then
        # If no tags exist, start with v1.0
        echo "v1.0"
    else
        # Get the highest tag (e.g., v1.3) and increment the minor version
        latest_tag=$(echo "$existing_tags" | tail -n 1)
        latest_version=${latest_tag#v}         # Strip the 'v' prefix
        major_version=$(echo "$latest_version" | cut -d'.' -f1)
        minor_version=$(echo "$latest_version" | cut -d'.' -f2)

        # Increment the minor version
        minor_version=$((minor_version + 1))

        # If minor version reaches 10, roll over to the next major version
        if [ "$minor_version" -ge 10 ]; then
            major_version=$((major_version + 1))
            minor_version=0
        fi

        echo "v$major_version.$minor_version"
    fi
}

# Start the script
log_message "Starting repository update process."

# Check if the SSH key exists
if [ ! -f "$SSH_KEY" ]; then
    log_message "Error: SSH key $SSH_KEY not found."
    exit 1
fi

# Check if the REPO_URL is empty
if [ -z "$REPO_URL" ]; then
    log_message "Error: Repository URL is not set."
    exit 1
fi

# Create the target directory if it doesn't exist
if [ ! -d "$TARGET_DIR" ]; then
    log_message "Directory $TARGET_DIR does not exist. Creating the directory."
    mkdir -p "$TARGET_DIR"
    if [ $? -ne 0 ]; then
        log_message "Error: Failed to create directory $TARGET_DIR."
        exit 1
    fi
    log_message "Directory $TARGET_DIR created successfully."

    # Set the correct permissions for the directory
    log_message "Setting permissions for $TARGET_DIR."
    chmod -R 755 "$TARGET_DIR"
    chown -R $(whoami):$(whoami) "$TARGET_DIR"
    if [ $? -ne 0 ]; then
        log_message "Error: Failed to set permissions for $TARGET_DIR."
        exit 1
    fi
    log_message "Permissions set successfully."
fi

# Start SSH agent only if not already running
if [ -z "$SSH_AUTH_SOCK" ]; then
    log_message "Starting SSH agent."
    eval "$(ssh-agent -s)" >> "$LOG_FILE" 2>&1
fi

# Add the SSH key to the SSH agent
log_message "Adding SSH key to agent."
ssh-add "$SSH_KEY" >> "$LOG_FILE" 2>&1
if [ $? -ne 0 ]; then
    log_message "Error: Failed to add SSH key to the agent."
    exit 1
fi
log_message "SSH key added successfully."

# Check if the target directory exists and is a git repository
if [ -d "$TARGET_DIR/.git" ]; then
    log_message "Directory $TARGET_DIR exists. Pulling changes."
    cd "$TARGET_DIR" || { log_message "Error: Could not change to directory $TARGET_DIR"; exit 1; }

    # Fetch changes from the repository
    GIT_SSH_COMMAND="ssh -i $SSH_KEY -o StrictHostKeyChecking=no" git fetch origin "$BRANCH" >> "$LOG_FILE" 2>&1
    if [ $? -ne 0 ]; then
        log_message "Error: Failed to fetch changes."
        exit 1
    fi

    # Pull changes from the specified branch and log the output
    GIT_SSH_COMMAND="ssh -i $SSH_KEY -o StrictHostKeyChecking=no" git pull origin "$BRANCH" -v >> "$LOG_FILE" 2>&1
    if [ $? -eq 0 ]; then
        log_message "Successfully pulled changes from the repository."
    else
        log_message "Error: Failed to pull changes."
        exit 1
    fi
else
    log_message "Directory $TARGET_DIR does not exist. Cloning the repository."

    # Clone the repository and log the output
    GIT_SSH_COMMAND="ssh -i $SSH_KEY -o StrictHostKeyChecking=no" git clone "$REPO_URL" "$TARGET_DIR" >> "$LOG_FILE" 2>&1
    if [ $? -eq 0 ]; then
        log_message "Successfully cloned the repository to $TARGET_DIR."
    else
        log_message "Error: Failed to clone the repository."
        exit 1
    fi
fi

log_message "Repository update process completed."

# Kill the SSH agent after the operation
ssh-agent -k >> "$LOG_FILE" 2>&1
log_message "SSH agent stopped."

# Check for Dockerfile and build the Docker image if it exists
cd "$TARGET_DIR" || { log_message "Error: Could not change to directory $TARGET_DIR"; exit 1; }

if [ -f "Dockerfile" ]; then
    log_message "Dockerfile found. Building Docker image '$DOCKER_IMAGE_NAME'."

    # Generate the next Docker image tag
    NEXT_TAG=$(generate_next_tag)
    log_message "Generated new tag: $NEXT_TAG"

    # Build the Docker image with the new tag
    docker build -t "$DOCKER_IMAGE_NAME:$NEXT_TAG" . >> "$LOG_FILE" 2>&1
    if [ $? -eq 0 ]; then
        log_message "Docker image '$DOCKER_IMAGE_NAME:$NEXT_TAG' built successfully."
    else
        log_message "Error: Failed to build the Docker image."
        exit 1
    fi
else
    log_message "No Dockerfile found in the repository. Skipping Docker image build."
fi