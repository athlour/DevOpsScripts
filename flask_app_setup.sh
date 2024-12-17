#!/bin/bash

# Configuration variables
REPO_URL="git@github.com:athlour/QuantServer.git"     # Replace with your SSH repo URL
TARGET_DIR="/home/athlour/quantserver"                    # Replace with the target folder path
LOG_FILE="/home/athlour/quantserver.log"                  # Path to the log file
SSH_KEY="/home/athlour/DevOpsScripts/id_ed25519"                      # Path to your private SSH key
BRANCH="master"                                       # Branch to pull from, can be changed as needed
FLASK_PORT="5000"                                     # Flask app port
UFW_SERVICE_NAME="flask"                              # Custom service name for UFW rule

# Function to log messages with timestamps
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Ensure SSH key permissions are secure
check_ssh_key_permissions() {
    if [ ! -f "$SSH_KEY" ]; then
        log_message "Error: SSH key $SSH_KEY not found."
        exit 1
    fi

    # Set proper permissions for the SSH key
    chmod 600 "$SSH_KEY"
    if [ $? -ne 0 ]; then
        log_message "Error: Failed to set permissions for SSH key $SSH_KEY."
        exit 1
    fi
    log_message "SSH key permissions set to 600."
}

# Start the script
log_message "Starting repository update process."

# Check if the SSH key exists and set permissions
check_ssh_key_permissions

# Check if the REPO_URL is empty
if [ -z "$REPO_URL" ]; then
    log_message "Error: Repository URL is not set."
    exit 1
fi

# Create the target directory if it doesn't exist
if [ ! -d "$TARGET_DIR" ]; then
    log_message "Directory $TARGET_DIR does not exist. Creating the directory."
    mkdir -p "$TARGET_DIR" && chmod -R 755 "$TARGET_DIR" && chown -R $(whoami):$(whoami) "$TARGET_DIR"
    if [ $? -ne 0 ]; then
        log_message "Error: Failed to create directory $TARGET_DIR or set permissions."
        exit 1
    fi
    log_message "Directory $TARGET_DIR created successfully and permissions set."
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

# Post-clone setup: install dependencies and setup Flask
log_message "Post-clone setup: Installing dependencies and setting up Flask app."

# Check if python3-venv is installed
log_message "Checking if python3-venv is installed."

if ! dpkg -l | grep -q python3-venv; then
    log_message "python3-venv is not installed. Installing it."
    sudo apt install -y python3-venv >> "$LOG_FILE" 2>&1
    if [ $? -ne 0 ]; then
        log_message "Error: Failed to install python3-venv."
        exit 1
    fi
    log_message "python3-venv installed successfully."
fi

# Create a virtual environment
log_message "Creating a virtual environment."
python3 -m venv "$TARGET_DIR/venv"

if [ $? -ne 0 ]; then
    log_message "Error: Failed to create a virtual environment."
    exit 1
fi
log_message "Virtual environment created successfully."

# Activate the virtual environment
log_message "Activating the virtual environment."
source "$TARGET_DIR/venv/bin/activate"

# Install the required dependencies
log_message "Installing dependencies."
pip install -r "$TARGET_DIR/requirements.txt" >> "$LOG_FILE" 2>&1
if [ $? -ne 0 ]; then
    log_message "Error: Failed to install dependencies."
    exit 1
fi
log_message "Dependencies installed successfully."

# Enable the Flask app's port (5000) in UFW
log_message "Enabling Flask port ($FLASK_PORT) in UFW."

# Check if UFW is active
if sudo ufw status | grep -q "Status: inactive"; then
    log_message "UFW is inactive. Enabling UFW."
    sudo ufw enable >> "$LOG_FILE" 2>&1
    if [ $? -ne 0 ]; then
        log_message "Error: Failed to enable UFW."
        exit 1
    fi
    log_message "UFW enabled successfully."
fi

# Allow traffic on Flask's port
sudo ufw allow "$FLASK_PORT" comment "$UFW_SERVICE_NAME" >> "$LOG_FILE" 2>&1
if [ $? -ne 0 ]; then
    log_message "Error: Failed to allow traffic on port $FLASK_PORT."
    exit 1
fi
log_message "Flask port ($FLASK_PORT) enabled in UFW successfully."

# Check if the Flask app is already running
if pgrep -f "python3 main.py" > /dev/null; then
    log_message "Flask app is already running in the background."
else
    log_message "Starting Flask app in the background."

    # Navigate to the target directory and activate the virtual environment
    cd "$TARGET_DIR" || { log_message "Error: Could not change to directory $TARGET_DIR"; exit 1; }
    source "$TARGET_DIR/venv/bin/activate"

    # Run the Flask app with nohup and log the output
    nohup python3 main.py >> "$LOG_FILE" 2>&1 &
    if [ $? -ne 0 ]; then
        log_message "Error: Failed to start the Flask app."
        deactivate
        exit 1
    fi

    log_message "Flask app started successfully."
fi

log_message "Flask app setup process completed."

# Kill the SSH agent after the operation
ssh-agent -k >> "$LOG_FILE" 2>&1
log_message "SSH agent stopped."