#!/bin/bash
#
# Usage:
#   ./build.sh [tag]
# Example:
#   ./build.sh latest
#

function die(){
  echo $@ >&2
  exit 1
}

SCRIPT_DIR=${SCRIPT_DIR:-$(cd $(dirname $0) && pwd)}

TAG=${1:-`date "+%Y%m%d"`}
shift

IMAGE_NAME=neogenia/ez-gate
NAME_TAG=$IMAGE_NAME:$TAG
echo building image "$NAME_TAG" ...

cd $SCRIPT_DIR

time docker build --target base -t $NAME_TAG . $@
if [ $? -ne 0 ]; then
  exit 1
fi

time docker build -t $NAME_TAG-test . $@
if [ $? -ne 0 ]; then
  cat <<TEST_MSG

### TEST FAILED ### 
# Please run test and debug code, use below command:

docker run -v $PWD/src:/var/scripts -ti $NAME_TAG-test bash

$ rake test

TEST_MSG
  exit 1
fi

time docker build --target openappsec -t $NAME_TAG-openappsec . $@
if [ $? -ne 0 ]; then
  exit 1
fi

cat <<GUIDE
# build finished successfuly.
# If you push image to DockerHub, use below command:

docker login

docker push $NAME_TAG
docker push $NAME_TAG-openappsec

GUIDE
