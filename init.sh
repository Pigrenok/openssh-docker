#/usr/bin/env bash

SSH_PORT=${SSH_PORT:-2222}

# Set default username if not provided
USER_NAME=${USER_NAME:-user}

# Check if the user and group already exist, create them if not
if ! id -u $USER_NAME > /dev/null 2>&1; then
    groupadd -g ${PGID:-1000} usergroup && \
    useradd -m -u ${PUID:-1000} -g usergroup -s /bin/bash $USER_NAME
fi

# Set the timezone if provided
if [ ! -z "$TZ" ]; then
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
fi

# If home directory is not mounted, then it should be created.
if [ ! -d "/home/${USER_NAME}" ]; then
    echo "Creating directory /home/${USER_NAME}"
    mkdir -p "/home/${USER_NAME}"
else
    echo "Directory /home/${USER_NAME} already exists"
fi

# Set ownership and permissions for the directory
chown "${USER_NAME}:usergroup" "/home/${USER_NAME}"
chmod 755 "/home/${USER_NAME}"

echo "Changing home dir for user ${USER_NAME}"
usermod -d /home/${USER_NAME} ${USER_NAME}


# Configure SSH access
mkdir -p /home/$USER_NAME/.ssh
chmod 700 /home/$USER_NAME/.ssh

# Function to check if a public key is already in authorized_keys
key_exists_in_authorized_keys() {
    local key="$1"
    local file="/home/$USER_NAME/.ssh/authorized_keys"
    grep -qxF "$key" "$file"
}

record_key() {
    if [ ! -f /home/$USER_NAME/.ssh/authorized_keys ]; then
        touch /home/$USER_NAME/.ssh/authorized_keys
    fi

    if ! key_exists_in_authorized_keys "$1"; then
        echo "$1" >> /home/$USER_NAME/.ssh/authorized_keys
    fi
}

# Add public key if not already present
if [ ! -z "$PUBLIC_KEY" ]; then
    record_key "$PUBLIC_KEY"
fi

if [ ! -z "$PUBLIC_KEY_FILE" ] && [ -f "$PUBLIC_KEY_FILE" ]; then
    record_key "$(cat "$PUBLIC_KEY_FILE")"
fi

if [ ! -z "$PUBLIC_KEY_DIR" ] && [ -d "$PUBLIC_KEY_DIR" ]; then
    for keyfile in "$PUBLIC_KEY_DIR"/*.pub; do
        if [ -f "$keyfile" ]; then
            record_key "$(cat "$keyfile")"
        fi
    done
fi

if [ ! -z "$PUBLIC_KEY_URL" ]; then
    record_key "$(curl "$PUBLIC_KEY_URL")"
fi

if [ -f "/home/$USER_NAME/.ssh/authorized_keys" ]; then
    chmod 600 /home/$USER_NAME/.ssh/authorized_keys
    chown -R $USER_NAME:usergroup /home/$USER_NAME/.ssh
fi

# Configure sudo access if not already granted
if [ "$SUDO_ACCESS" = "true" ] && ! grep -q "^$USER_NAME" /etc/sudoers; then
    usermod -aG sudo $USER_NAME
    if [ "$PASSWORD_ACCESS" = "true" ]; then
        echo "$USER_NAME ALL=(ALL) ALL" >> /etc/sudoers
    else
        echo "$USER_NAME ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
    fi
fi

# Configure password access
if [ "$PASSWORD_ACCESS" = "true" ]; then
    if [ ! -z "$USER_PASSWORD" ]; then
        echo "$USER_NAME:$USER_PASSWORD" | chpasswd
    elif [ ! -z "$USER_PASSWORD_FILE" ] && [ -f "$USER_PASSWORD_FILE" ]; then
        USER_PASSWORD=$(cat "$USER_PASSWORD_FILE")
        echo "$USER_NAME:$USER_PASSWORD" | chpasswd
    fi
else
    passwd -d $USER_NAME
fi

# Disable root SSH login if not already disabled
if grep -q "^PermitRootLogin" /etc/ssh/sshd_config; then
    if ! grep -q "^PermitRootLogin no" /etc/ssh/sshd_config; then
        sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
    fi
else
    echo "PermitRootLogin no" >> /etc/ssh/sshd_config
fi

# Function to check if a line exists in a file
line_exists() {
    grep -q "$1" "$2"
}

# Function to replace a line in a file
replace_line() {
    sed -i "s/^#*\s*$1/$2/" "$3"
}

# Function to append a line to a file if it doesn't exist
append_line() {
    if ! line_exists "$1" "$2"; then
        echo "$1" >> "$2"
    fi
}

# Check if KEY_PASS is true
if [[ "$KEY_PASS" == "true" ]]; then
    # Check if at least one of the public key variables is set
    if [[ -n "${PUBLIC_KEY}" || -n "${PUBLIC_KEY_FILE}" || -n "${PUBLIC_KEY_DIR}" || -n "${PUBLIC_KEY_URL}" ]]; then
        # Check if USER_PASSWORD or USER_PASSWORD_FILE is set
        if [[ -n "${USER_PASSWORD}" || -n "${USER_PASSWORD_FILE}" ]]; then
            # Path to the sshd_config file
            SSHD_CONFIG="/etc/ssh/sshd_config"
            
            # Check if the AuthenticationMethods line exists
            if line_exists "^AuthenticationMethods" "$SSHD_CONFIG"; then
                # Replace the AuthenticationMethods line
                replace_line "AuthenticationMethods.*" "AuthenticationMethods publickey,password" "$SSHD_CONFIG"
            else
                # Append the AuthenticationMethods line if it doesn't exist
                append_line "AuthenticationMethods publickey,password" "$SSHD_CONFIG"
            fi
            
            echo "AuthenticationMethods configuration updated in sshd_config."
        else
            echo "USER_PASSWORD or USER_PASSWORD_FILE is not set."
        fi
    else
        echo "None of the public key variables (PUBLIC_KEY, PUBLIC_KEY_FILE, PUBLIC_KEY_DIR, PUBLIC_KEY_URL) are set."
    fi
else
    echo "KEY_PASS is not set to 'true'."
fi


# Iterate over all environment variables
for var in $(printenv | grep -o "^FILE__[^=]*"); do
    # Extract the variable name without the "FILE__" prefix
    name=${var#FILE__}
    
    # Get the file path from the environment variable
    file_path=${!var}
    
    # Check if the file exists and is readable
    if [ -r "$file_path" ]; then
        # Read the content of the file
        content=$(cat "$file_path")
        
        # Assign the content to the environment variable
        export "$name"="$content"
        echo "export $name=$content" >> /home/$USER_NAME/.bashrc
    else
        echo "File '$file_path' does not exist or is not readable."
    fi
done

# Function to run a script
run_script() {
    local script="$1"
    echo "Running script: $script"
    bash "$script"
}

# Run scripts in /custom-cont-init.d and its subdirectories
if [ -d "/custom-cont-init.d" ]; then
    echo "Running scripts in /custom-cont-init.d and its subdirectories"
    find "/custom-cont-init.d" -type f -executable -print0 | while IFS= read -r -d '' script; do
        run_script "$script"
    done
else
    echo "Directory /custom-cont-init.d not found"
fi

# Function to generate supervisord configuration for a service
generate_supervisord_config() {
    local service="$1"
    local service_name=$(basename "$service")
    
    cat > "/etc/supervisor/conf.d/${service_name}.conf" <<EOF
[program:${service_name}]
command=bash ${service}
autorestart=true
stderr_logfile=/var/log/supervisor/${service_name}.err.log
stdout_logfile=/var/log/supervisor/${service_name}.out.log
EOF
}

# Run services in /custom-services.d and its subdirectories
if [ -d "/custom-services.d" ]; then
    echo "Generating supervisord configurations for services in /custom-services.d and its subdirectories"
    find "/custom-services.d" -type f -executable -print0 | while IFS= read -r -d '' service; do
        generate_supervisord_config "$service"
    done
    
    echo "Starting supervisord"
    supervisord -c /etc/supervisor/supervisord.conf
else
    echo "Directory /custom-services.d not found"
fi

# Changing SSH port
sed -i "/^#*[[:blank:]]*Port/c\Port $SSH_PORT" /etc/ssh/sshd_config

# Start the SSH daemon
/usr/sbin/sshd -D