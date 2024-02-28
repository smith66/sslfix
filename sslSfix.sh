#!/bin/bash

# Ask for the domain name
read -p "Please provide domain name:" domain

live_dir="/etc/letsencrypt/live"
renewal_dir="/etc/letsencrypt/renewal"
archive_dir="/etc/letsencrypt/archive"
vhost_dir="/etc/httpd/vhosts"
lswsVhost_dir="/usr/local/lsws/vhosts"
nginxVhost_dir="/etc/nginx/vhosts"

# Step 1 - This will check what Web Server is running.
# Check if Apache HTTP server is running
if systemctl is-active --quiet httpd; then
  echo "Apache (httpd) is running."
else
  # Check if LiteSpeed is running
  if systemctl is-active --quiet lsws; then
    lsws_status=$(systemctl status lsws)
    if echo "$lsws_status" | grep -q "lshttpd.service - OpenLiteSpeed HTTP Server"; then
      echo "OpenLiteSpeed is running."
    else
      echo "LiteSpeed Enterprise is running."
    fi
  else
    # Check if Nginx is running
    if systemctl is-active --quiet nginx; then
      echo "Nginx is running."
      exit 1
    fi
    # If none of the supported web servers are running
    echo "No supported web server (Apache, LiteSpeed, or Nginx) is running. Script will stop."
    exit 1
  fi
fi

# step 2
# Check if there are suffixes for the domain in /etc/letsencrypt/live
latest_live_dir=$(find "$live_dir" -maxdepth 1 -type d -name "${domain}-*" | sort -V | tail -n 1)
latest_suffix=$(basename "$latest_live_dir" | sed -E "s/^${domain}-//")

conf_file_check=($(find "$renewal_dir" -type f -name "${domain}-${latest_suffix}\.conf"))

common_suffix=""
suffix_name=$(basename "$suffix" | sed -E "s/^${domain}-//")
if [ -f "$conf_file_check" ]; then
    common_suffix="$latest_suffix"
fi

echo "Suffix in live and renewal match"

# step 2
if [ -n "$common_suffix" ]; then
    if [ -d "$live_dir/$domain" ]; then
        for link in $(find "$live_dir/$domain" -type l); do
            unlink "$link"
        done
    fi

    echo "Unlinking the existing live directory"

    # step 3
    latest_archive_dir=$(find "$archive_dir" -maxdepth 1 -type d -name "${domain}-*" | sort -V | tail -n 1)
    if [ -n "$latest_archive_dir" ]; then
        rm -rf "$archive_dir/$domain"
        mv "$latest_archive_dir" "$archive_dir/$domain"
        for dir in $(find "$archive_dir" -maxdepth 1 -type d -name "${domain}-*"); do
            if [ "$dir" != "$archive_dir/$domain" ]; then
                rm -rf "$dir"
            fi
        done
    fi

    # Change ownership of the /etc/letsencrypt/archive directory recursively
    if [ -d "$archive_dir/$domain" ]; then
        chown -R exim:nobody "$archive_dir/$domain"
    fi
    
    echo "Changing the ownership of the directory archive"

    # step 4
    latest_live_dir=$(find "$live_dir" -maxdepth 1 -type d -name "${domain}-*" | sort -V | tail -n 1)
    if [ -n "$latest_live_dir" ]; then
        rm -rf "$live_dir/$domain"
        mv "$latest_live_dir" "$live_dir/$domain"
        for dir in $(find "$live_dir" -maxdepth 1 -type d -name "${domain}-*"); do
            if [ "$dir" != "$live_dir/$domain" ]; then
                rm -rf "$dir"
            fi
        done
    fi

    new_latest_archive_dir="${archive_dir}/${domain}"
    new_latest_live_dir="${live_dir}/${domain}"
    # Create symlinks for all files within the new folder
    for file in "$new_latest_archive_dir"/*; do
        if [ -f "$file" ] && [ "$file" != "$new_latest_archive_dir/README" ]; then
            filename=$(basename "$file")
            filename_without_numbers="${filename//[^[:alpha:].]/}"
            rm -rf "$new_latest_live_dir/$filename_without_numbers"
            ln -s "$file" "$new_latest_live_dir/$filename_without_numbers"
        fi
    done

    echo "Creating the new symlinks in live dir"

    # step 5
    # Remove all other .conf files in /etc/letsencrypt/renewal except the latest one
    for conf in "${renewal_dir}/${domain}-"*".conf"; do
        if [ "$conf" != "$renewal_dir/${domain}-${common_suffix}.conf" ]; then
            rm "$conf"
        fi
    done
    # Rename the last number in both directories and .conf file
    mv "$renewal_dir/${domain}-${common_suffix}.conf" "$renewal_dir/${domain}.conf"

    echo "Removing and fixing the config files"

    # step 6 edit files
    if [ -f "$renewal_dir/${domain}.conf" ]; then
        sed -i "s/${domain}-${common_suffix}/${domain}/g" "$renewal_dir/${domain}.conf"
    fi
    echo "Config file has been rewritten"

    # if [ -f "$vhost_dir/${domain}.conf" ]; then
    #     sed -i "s/${domain}-${common_suffix}/${domain}/g" "$vhost_dir/${domain}.conf"
    # fi
    # echo "The Vhost has been edited."

    # Check if Apache HTTP server is running
    if systemctl is-active --quiet httpd; then
        # This will rewrite Apache Vhost
        if [ -f "$vhost_dir/${domain}.conf" ]; then
            sed -i "s/${domain}-${common_suffix}/${domain}/g" "$vhost_dir/${domain}.conf"
            systemctl restart httpd
            echo "Apache vHost configuration updated. Reloading Apache..."
        fi
    # Check if LiteSpeed is running
    elif systemctl is-active --quiet lsws; then
        lsws_status=$(systemctl status lsws)
        if echo "$lsws_status" | grep -q "lshttpd.service - OpenLiteSpeed HTTP Server"; then
            # This will rewrite OpenLiteSpeed Vhost
            if [ -f "$lswsVhost_dir/${domain}.conf" ]; then
                sed -i "s/${domain}-${common_suffix}/${domain}/g" "$lswsVhost_dir/${domain}.conf"
                systemctl restart lsws
                echo "OpenLiteSpeed vHost configuration updated. Reloading OpenLiteSpeed..."
            fi
        else
            # This will rewrite LiteSpeed Vhost
            if [ -f "$vhost_dir/${domain}.conf" ]; then
                sed -i "s/${domain}-${common_suffix}/${domain}/g" "$vhost_dir/${domain}.conf"
                systemctl restart lsws
                echo "LiteSpeed Enterprise vHost configuration updated. Reloading LiteSpeed..."
            fi
        fi
    # Check if Nginx is running
    elif systemctl is-active --quiet nginx; then
        # This will rewrite Nginx Vhost
        if [ -f "$nginxVhost_dir/${domain}.conf" ]; then
            sed -i "s/${domain}-${common_suffix}/${domain}/g" "$nginxVhost_dir/${domain}.conf"
            systemctl restart nginx
            echo "Nginx vHost configuration updated. Reloading Nginx..."
        fi
    fi


fi
echo "The script has been executed succsessfully... Thx for using >Peace and Love<"
