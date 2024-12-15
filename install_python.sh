#!/bin/bash

# Update the system package index
echo "Updating system package index..."
sudo apt update

# Check if Python is already installed
echo "Checking if Python is already installed..."
if command -v python3 &>/dev/null; then
    echo "Python 3 is already installed."
else
    echo "Python 3 not found, installing..."
    sudo apt install -y python3
    sudo apt install -y python3-pip  # Install pip for Python 3
    echo "Python 3 and pip installed successfully."
fi

# Verify installation
echo "Verifying Python 3 installation..."
python3 --version
pip3 --version

echo "Python installation completed!"
