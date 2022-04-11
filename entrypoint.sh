function trigger_workflow {
  echo "Triggering ${INPUT_EVENT_TYPE} in ${INPUT_OWNER}/${INPUT_REPO}"
  resp=$(curl -X POST -s "https://api.github.com/repos/${INPUT_OWNER}/${INPUT_REPO}/dispatches" \
    -H "Accept: application/vnd.github.v3+json" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${INPUT_TOKEN}" \
    -d "{\"event_type\": \"${INPUT_EVENT_TYPE}\", \"client_payload\": ${INPUT_CLIENT_PAYLOAD} }")

  if [ -z "$resp" ]
  then
    sleep 2
  else
    echo "Workflow failed to trigger"
    echo "$resp"
    exit 1
  fi
}

function find_workflow {
  counter=0
  action_start=$(date -u +%T)
  # TODO(toby): Remove this debug log
  echo "Action timestamp: $action_start"
  while [[ true ]]
  do
    counter=$(( $counter + 1 ))
    all_runs=$(curl -s "https://api.github.com/repos/${INPUT_OWNER}/${INPUT_REPO}/actions/runs" \
      -H "Accept: application/vnd.github.v3+json" \
      -H "Authorization: Bearer ${INPUT_TOKEN}" | jq '.workflow_runs' )

    # Github's API is eventually consistent when filtering by event which can
    # lead to bad results when using the `event` filter on the API query.
    # Filter here, instead, to work around this.
    dispatch_runs=$( echo $(echo $all_runs | jq 'map(select(.event=="repository_dispatch"))') )
    workflow=$( echo $(echo $dispatch_runs | jq '.[0]') )

    # TODO(toby): Remove this debug log
    echo "DEBUG: (Workflow) $workflow"

    wf_time=$( echo $(echo $workflow | jq '.created_at') | cut -c13-20 )
    # TODO(toby): Remove this debug log
    echo "Latest workflow timestamp: ${wf_time}"
    tdif=$(( $(date -d "$action_start" +"%s") - $(date -d "$wf_time" +"%s") ))
    
    if [[ "$tdif" -gt "10" ]]
    then
      if [[ "$counter" -gt "3" ]]
      then
        echo "Workflow not found"
        exit 1
      else
        sleep 2
      fi
    else
      break
    fi
  done

  wfid=$(echo $workflow | jq '.id')
  conclusion=$(echo $workflow | jq '.conclusion')
  
  echo "Workflow id is ${wfid}"
}

function wait_on_workflow {
  counter=0
  while [[ $conclusion == "null" ]]
  do
    if [[ "$counter" -ge "$INPUT_MAX_TIME" ]]
    then
      echo "Time limit exceeded"
      exit 1
    fi
    sleep $INPUT_WAIT_TIME
    conclusion=$(curl -s "https://api.github.com/repos/${INPUT_OWNER}/${INPUT_REPO}/actions/runs/${wfid}" \
    	-H "Accept: application/vnd.github.v3+json" \
    	-H "Authorization: Bearer ${INPUT_TOKEN}" | jq '.conclusion')
    counter=$(( $counter + $INPUT_WAIT_TIME ))
  done

  if [[ $conclusion == "\"success\"" ]]
  then
    echo "Workflow run successful"
  else
    echo "Workflow run failed"
    exit 1
  fi
}

function main {
  trigger_workflow
  find_workflow
  wait_on_workflow
}

main
