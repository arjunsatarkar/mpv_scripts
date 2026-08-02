#!/usr/bin/env sh
for script_dir in 'get_subtitle' 'mpvclip' 'savepoints'
do
    echo "Installing $script_dir"
    rsync --archive "$script_dir" ~/".config/mpv/scripts/"
done
