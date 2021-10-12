#!/bin/sh

SBCPOLLINTERVAL="${SBCPOLLINTERVAL:-1}"
SBCSCANINTERVAL="${SBCSCANINTERVAL:-300}"
SBCDIR="${SBCDIR:-/tmp/sponsorblockcast}"
SBCCATEGORIES="${SBCCATEGORIES:-sponsor}"

# Format categories for curl by quoting words, replacing spaces with commas and surrounding with escaped brackets
categories="\\[$(echo "$SBCCATEGORIES" | sed 's/[^ ]\+/"&"/g;s/\s/,/g')\\]"

[ -e "$SBCDIR" ] && rm -r "$SBCDIR"
mkdir "$SBCDIR" || exit 1
cd    "$SBCDIR" || exit 1

get_segments () {
  id=$1
  if [ -n "$id" ] && [ ! -f "$id".segments ]
  then
    curl -fs "https://sponsor.ajay.app/api/skipSegments?videoID=$id&categories=$categories" |\
    jq -r '.[] | (.segment|map_values(tostring)|join(" ")) + " " + .category' > "$id.segments"
  fi
}

watch () {
  uuid=$1
  go-chromecast watch -u "$uuid" --interval 1 \
  | while read -r status; do
    if echo "$status" | grep -q "YouTube (PLAYING)"
    then
      video_id=$(echo "$status" | grep -oP "id=\"\K[^\"]+")
      title=$(echo "$status" | grep -oP "title=\"[^ \"]+")
      artist=$(echo "$status" | grep -oP "artist=\"[^ \"]+")
      if [[ "$video_id" == "" ]]; then
        video_id=$(youtube-dl -j "ytsearch1:$title" | jq ". | select( .uploader == \"$artist\" ) | .id" | tr -d '"')
      fi
      if [[ ! -z "$video_id" ]]
      then
      get_segments "$video_id"
      progress=$(echo "$status" | grep -oP 'remaining=\K[^s]+')
      while read -r start end category; do
        if [ "$(echo "($progress > $start) && ($progress < ($end - 5))" | bc)" -eq 1 ]
        then
          echo "Skipping $category from $start -> $end on $uuid"
          go-chromecast -u "$uuid" seek-to "$end"
        fi
      done < "$video_id.segments"
      fi
    fi
  done;
}

scan_chromecasts() {
  go-chromecast ls | grep -v 'device="Google Cast Group"' | grep -oP 'uuid="\K[^"]+' | sed 's/-//g;' > devices
}

pid_exists () {
  kill -0 "$1" 2>/dev/null
}

# Takes a variable name and returns its value
expand () {
  eval "echo \$$1"
}

while :
do
  scan_chromecasts
  while read -r uuid; do
    uuid_var="sbc$uuid"
    if [ -z "$(expand "$uuid_var")" ] || ! pid_exists "$(expand "$uuid_var")"
    then
      watch "$uuid" &
      eval "$uuid_var=$!"
      echo watching "$uuid", pid="$(expand "$uuid_var")"
    fi
  done < devices
  sleep "$SBCSCANINTERVAL"
done

