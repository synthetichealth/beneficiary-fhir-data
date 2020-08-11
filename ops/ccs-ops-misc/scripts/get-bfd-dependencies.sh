#!/usr/bin/env bash
set -e
trap 'usage' ERR

usage() {
  echo "Please provide the name or id of the running bfd app container. Ex:"
  echo "    './get-bfd-dependencies.sh contributing_bfd_1'"
  echo "You can run 'docker ps' to list the running containers on your system."
  echo ""
  echo "To save the output to a file:"
  echo "./get-bfd-dependencies.sh contributing_bfd_1 > bfd-depends.txt"
}
[[ "$1" =~ ^-.* ]] && usage && exit 0
[[ "$1" =~ ^help.* ]] && usage && exit 0
    
mvncmd='mvn dependency:list | grep "\[INFO\][^:]*:[^:]*:[^:]*:[^:]*:.*" | cut -d] -f2- | sort | uniq > bfd.depends.txt'
if docker exec "$1" /bin/bash -c "cd /app/apps; ${mvncmd}"; then
  docker exec "$1" /bin/bash -c "cat /app/apps/bfd.depends.txt"
else
  usage
fi
