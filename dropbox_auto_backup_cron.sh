#!/bin/bash

#Save current date  as YYYY-MM-DD to a variable
DATE=$(date +"%Y-%m-%d")
BACKUP_FOLDER="/home/backup/"

#Loop through each file in the backup folder whose name has the current date



for X in "$BACKUP_FOLDER"*$DATE*; do

    #if file not found dont continue
    if [ ! -e $X ]
    then
        exit
    fi

    #X is the filename with path. Remove path to get just the filename.
    NAME_NO_PATH=${X##*/}

    #Remove the date from the name (removes all text between the periods)
    NEW_NAME="${NAME_NO_PATH%%.*}.${NAME_NO_PATH##*.}"
    
    #get username
    USER_NAME="${NAME_NO_PATH%%.*}"
    
    #Copy the file to tmp with the new non-dated name
    cp $X "$BACKUP_FOLDER$NEW_NAME"
    
    #Send it to Dropbox (using downloaded api dropbox_uploader.sh)
    /dropbox/dropbox_uploader.sh -f /root/.dropbox_uploader upload "$BACKUP_FOLDER$NEW_NAME" /
    
    #delete uploaded data
    rm -rf "$BACKUP_FOLDER$NEW_NAME"
        
    #Delete the backup using api (so the counter is updated in panel)
    v-delete-user-backup $USER_NAME $NAME_NO_PATH

done


