#!/bin/bash
REPOSITORY="$1"
BRANCH="$5"

if [ "$REPOSITORY" == "" ] ; then
  echo "Something is wrong. Your Repository name is blank!"
  exit 1
fi

if [ -f /etc/default/octohost ]; then
  . /etc/default/octohost
fi

if [ -d "$REPO_PATH" ]; then rm -rf "$REPO_PATH"; fi
echo "Put repo in src format somewhere."
mkdir -p "$REPO_PATH" && cat | tar -x -C "$REPO_PATH"
echo "Building Docker image."
BASE=`basename $REPOSITORY .git`

if [ "$BRANCH" != "master" ]
then
  BASE="$BASE-$BRANCH"
fi
echo "Base: $BASE"

# Find out the old container ID.
OLD_ID=$(sudo docker ps | grep "\b$BASE:latest\b" | cut -d ' ' -f 1)

IMAGE_ID=$(sudo docker images | grep "$BUILD_ORG_NAME\/$BASE " | awk '{ print $3 }')

if [ -e "$DOCKERFILE" ]
then

  # Look for a file to touch (to prevent Docker invalidating the cache based on timestamp)
  TOUCH_FILE=$(grep -i "^# TOUCH " $DOCKERFILE | cut -d ' ' -f 3)
  TOUCH_PARAMS=$(grep -i "^# TOUCH " $DOCKERFILE | cut -d ' ' -f 4-)
  if [ -n "$TOUCH_FILE" ]
  then
    echo "Touching -d '$TOUCH_PARAMS' $REPO_PATH/$TOUCH_FILE"
    $(touch -d "$TOUCH_PARAMS" "$REPO_PATH/$TOUCH_FILE")
  fi

  sudo docker build -t $BUILD_ORG_NAME/$BASE $REPO_PATH

  if [ $? -ne 0 ]
  then
    echo "Failed build - exiting."
    exit
  fi
  
  
  #Kill the old container by ID.  
  #TODO: Make this dependent on there being a name supplied in options.
  if [ -n "$OLD_ID" ]
  then
    echo "Killing $OLD_ID container."
    sudo docker kill $OLD_ID
  else
    echo "Not killing any containers."
  fi

  KILLED_ID=$(docker ps --all |grep "Exited" | grep "\b$BASE\b" | awk '{ print $1 }')
  if [ -n "$KILLED_ID" ]
  then
     echo "Removing docker image with the same name"
     sudo docker rm "$KILLED_ID"
  fi

else
  echo "There is no Dockerfile present."
  exit
fi

if [ -n "$XIP_IO" ]
then
  echo "Adding $LINK_PREFIX://$BASE.$XIP_IO"
  DOMAINS="$BASE.$XIP_IO"
fi

if [ -n "$DOMAIN_SUFFIX" ]
then
  echo "Adding $LINK_PREFIX://$BASE.$DOMAIN_SUFFIX"
  if [ -n "$XIP_IO" ]
  then
    DOMAINS="$DOMAINS,$BASE.$DOMAIN_SUFFIX"
  else
    DOMAINS="$BASE.$DOMAIN_SUFFIX"
  fi
fi

# Support a CNAME file in repo src
CNAME=/home/git/src/$REPOSITORY/CNAME
if [ -f $CNAME ]
then
  # Add a new line at end if it does not exist to ensure the loop gets last line
  sed -i -e '$a\\' $CNAME
  while read DOMAIN
  do
    echo "Adding $LINK_PREFIX://$DOMAIN"
    DOMAINS="$DOMAINS,$DOMAIN"
  done < $CNAME
fi

/usr/bin/octo domains:set "$BASE" "$DOMAINS"

NUM_CONTAINERS=$(/usr/bin/octo config:get $BASE/CONTAINERS)
NUM_CONTAINERS=${NUM_CONTAINERS:-1}

/usr/bin/octo start "$BASE" "$NUM_CONTAINERS"

# Kill the old container by ID.
if [ -n "$OLD_ID" ]
then
  /usr/bin/octo stop "$BASE" "$IMAGE_ID"
else
  echo "Not killing any containers."
fi

/usr/bin/octo config:consul_template "$BASE"

if [ -n "$XIP_IO" ]; then echo "Your site is available at: $LINK_PREFIX://$BASE.$XIP_IO";fi
if [ -n "$DOMAIN_SUFFIX" ]; then echo "Your site is available at: $LINK_PREFIX://$BASE.$DOMAIN_SUFFIX";fi

if [ -n "$PRIVATE_REGISTRY" ]; then
  echo "Pushing $BASE to a private registry."
  /usr/bin/octo push $BASE > /dev/null
fi
