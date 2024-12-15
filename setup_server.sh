#!/bin/bash

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root."
  exit 1
fi

# Check if the SSH keys file exists
if [ ! -f ~/.ssh/authorized_keys ]; then
  echo "SSH keys file not found at ~/.ssh/authorized_keys. Please ensure your SSH keys are set up before running this script."
  exit 1
fi

# Prompt for username
read -p "Enter the new username: " new_user

# Prompt for password (hidden input)
read -s -p "Enter the password for $new_user: " password
echo

# Create the new user
adduser --gecos "" --disabled-password $new_user

# Set the password for the new user
echo "$new_user:$password" | chpasswd

# Add the new user to the sudo group
usermod -aG sudo $new_user

# Copy SSH keys from root to the new user
mkdir -p /home/$new_user/.ssh
cp -r ~/.ssh/authorized_keys /home/$new_user/.ssh/
chown -R $new_user:$new_user /home/$new_user/.ssh
chmod 700 /home/$new_user/.ssh
chmod 600 /home/$new_user/.ssh/authorized_keys

# Secure SSH configuration
ssh_config="/etc/ssh/sshd_config"
if grep -q "^PermitRootLogin" $ssh_config; then
  sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' $ssh_config
else
  echo "PermitRootLogin no" >> $ssh_config
fi

if grep -q "^PasswordAuthentication" $ssh_config; then
  sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' $ssh_config
else
  echo "PasswordAuthentication no" >> $ssh_config
fi

# Restart SSH service
systemctl restart ssh

# Install necessary packages
apt update && apt upgrade -y
apt install -y git curl wget htop tmux ufw unattended-upgrades

# Enable UFW and allow SSH
ufw allow OpenSSH
ufw --force enable

# Configure unattended upgrades
dpkg-reconfigure --priority=low unattended-upgrades

# Display completion message
echo "Setup complete! You can now log in as $new_user with your SSH key."
