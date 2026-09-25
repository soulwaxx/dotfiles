#!/usr/bin/env zsh
# ============================================================================
# AWS SSM / ECS debugging helpers
# ============================================================================

# ============================================================================
# AWS EC2 SSM session
# ============================================================================

# Connect to EC2 instance via SSM Session Manager
aws-ssm() {
    local instance_id="$1"
    local region="${2:-}"

    if [[ -z "$instance_id" ]]; then
        echo -n "Enter EC2 instance ID: "
        read instance_id
    fi

    if [[ -z "$instance_id" ]]; then
        echo "Error: Instance ID is required"
        return 1
    fi

    if [[ -z "$region" ]]; then
        echo -n "Enter AWS region [eu-west-1]: "
        read region
    fi
    region=${region:-eu-west-1}

    echo "Connecting to $instance_id in $region via SSM..."
    aws ssm start-session --target "$instance_id" --region "$region"
}

# ============================================================================
# ECS DEBUGGING
# Quickly diagnose failing ECS tasks without going through the AWS console.
#
# Defaults (override per-session via env vars):
#   ECS_REGION=eu-west-1
#
# ecss / ecs-status  — fzf: cluster → service → show task sets, health, events
# ecsl / ecs-logs    — fzf: cluster → service → container → docker logs
# ecse / ecs-exec <service> <container> <cmd>  — docker exec via SSM
# ecsc / ecs-curl <service> <url>              — HTTP GET from inside task namespace
# ============================================================================

ECS_REGION="${ECS_REGION:-eu-west-1}"

# Send a shell command to an EC2 instance via SSM, poll, and print stdout.
_ecs_ssm_run() {
    local instance_id="$1"
    local cmd="$2"

    local parameters cmd_id
    parameters=$(jq -cn --arg cmd "$cmd" '{commands: [$cmd]}') || return 1

    cmd_id=$(aws ssm send-command \
        --instance-ids "$instance_id" \
        --document-name AWS-RunShellScript \
        --parameters "$parameters" \
        --region "$ECS_REGION" \
        --query "Command.CommandId" \
        --output text 2>&1)

    [[ $? -ne 0 || -z "$cmd_id" ]] && { echo "SSM send-command failed: $cmd_id" >&2; return 1; }

    local ssm_status="" elapsed=0
    while true; do
        sleep 1
        (( elapsed++ ))
        (( elapsed > 30 )) && { echo "SSM timed out after 30s" >&2; return 1; }

        ssm_status=$(aws ssm get-command-invocation \
            --command-id "$cmd_id" \
            --instance-id "$instance_id" \
            --region "$ECS_REGION" \
            --query "Status" \
            --output text 2>/dev/null) || continue

        [[ "$ssm_status" == "InProgress" || "$ssm_status" == "Pending" ]] && continue

        aws ssm get-command-invocation \
            --command-id "$cmd_id" \
            --instance-id "$instance_id" \
            --region "$ECS_REGION" \
            --query "StandardOutputContent" \
            --output text 2>/dev/null

        [[ "$ssm_status" == "Success" ]] && return 0 || return 1
    done
}

# List cluster short names for the current region.
_ecs_pick_cluster() {
    local clusters
    clusters=$(aws ecs list-clusters \
        --region "$ECS_REGION" \
        --query "clusterArns[*]" \
        --output text 2>/dev/null | tr '\t' '\n' | sed 's|.*/||')
    [[ -z "$clusters" ]] && { echo "No clusters found" >&2; return 1; }
    if command -v fzf &>/dev/null; then
        echo "$clusters" | fzf --prompt="cluster> " --height=40% --border
    else
        echo "$clusters" | head -1
    fi
}

# List service short names in a cluster.
_ecs_pick_service() {
    local cluster="$1"
    local services
    services=$(aws ecs list-services \
        --cluster "$cluster" \
        --region "$ECS_REGION" \
        --query "serviceArns[*]" \
        --output text 2>/dev/null | tr '\t' '\n' | sed 's|.*/||' | sort)
    [[ -z "$services" ]] && { echo "No services found in $cluster" >&2; return 1; }
    if command -v fzf &>/dev/null; then
        echo "$services" | fzf --prompt="service> " --height=40% --border
    else
        echo "$services" | head -1
    fi
}

# Resolve container instance ARN → EC2 instance ID.
_ecs_instance_id() {
    local cluster="$1"
    local instance_arn="$2"
    aws ecs describe-container-instances \
        --cluster "$cluster" \
        --container-instances "$instance_arn" \
        --region "$ECS_REGION" \
        --query "containerInstances[0].ec2InstanceId" \
        --output text
}

# Interactive picker for cluster and service (shared by ecs-status, ecs-logs, ecs-logs-follow).
# Prints "<cluster> <service>" or returns 1.
# Usage: _ecs_pick_cluster_service [cluster] [service]
_ecs_pick_cluster_service() {
    local cluster="${1:-}"
    local service="${2:-}"

    if [[ -z "$cluster" ]]; then
        cluster=$(_ecs_pick_cluster) || return 1
        [[ -z "$cluster" ]] && return 1
    fi
    if [[ -z "$service" ]]; then
        service=$(_ecs_pick_service "$cluster") || return 1
        [[ -z "$service" ]] && return 1
    fi

    echo "$cluster $service"
}

# Resolve task → container → runtime_id for a given cluster/service.
# Prints: "<task_id> <ec2_id> <container_name> <runtime_id>" or returns 1.
# Usage: _ecs_resolve_container <cluster> <service> <container> [task_id]
_ecs_resolve_container() {
    local cluster="$1"
    local service="$2"
    local container="${3:-}"
    local task_hint="${4:-}"

    local task_info
    task_info=$(_ecs_debug_task "$cluster" "$service" "$task_hint") || return 1
    local task_id="${task_info%% *}"
    local ec2_id="${task_info##* }"

    local containers_json
    containers_json=$(aws ecs describe-tasks \
        --cluster "$cluster" \
        --tasks "$task_id" \
        --region "$ECS_REGION" \
        --query "tasks[0].containers[*].{name:name,runtimeId:runtimeId}" \
        --output json 2>/dev/null)

    local runtime_id
    if [[ -n "$container" ]]; then
        runtime_id=$(echo "$containers_json" | jq -r ".[] | select(.name == \"$container\") | .runtimeId")
        if [[ -z "$runtime_id" ]]; then
            echo "Container '$container' not found. Available:"
            echo "$containers_json" | jq -r '.[].name'
            return 1
        fi
    elif command -v fzf &>/dev/null; then
        local selected
        selected=$(echo "$containers_json" | jq -r '.[].name' | fzf --prompt="container> " --height=40% --border)
        [[ -z "$selected" ]] && return 1
        container="$selected"
        runtime_id=$(echo "$containers_json" | jq -r ".[] | select(.name == \"$container\") | .runtimeId")
    else
        container=$(echo "$containers_json" | jq -r '.[0].name')
        runtime_id=$(echo "$containers_json" | jq -r '.[0].runtimeId')
    fi

    echo "$task_id $ec2_id $container $runtime_id"
}

# fzf-pick a running task for a service.
# If multiple tasks exist (e.g. blue-green), shows a picker with task ID + health + revision.
# Pass task_id as 3rd arg to bypass fzf entirely.
# Usage: _ecs_debug_task <cluster> <service> [task_id]
# Prints: "<task_id> <ec2_instance_id>"
_ecs_debug_task() {
    local cluster="$1"
    local service="$2"
    local task_hint="${3:-}"

    local task_id
    if [[ -n "$task_hint" ]]; then
        task_id="$task_hint"
    else
        local task_arns
        task_arns=$(aws ecs list-tasks \
            --cluster "$cluster" \
            --service-name "$service" \
            --desired-status RUNNING \
            --region "$ECS_REGION" \
            --query "taskArns" \
            --output text 2>/dev/null | tr '\t' '\n' | grep -v '^$')

        [[ -z "$task_arns" ]] && { echo "No running tasks for: $service" >&2; return 1; }

        local task_arn
        local count
        count=$(echo "$task_arns" | wc -l | tr -d ' ')

        if (( count > 1 )) && command -v fzf &>/dev/null; then
            local task_lines
            task_lines=$(aws ecs describe-tasks \
                --cluster "$cluster" \
                --tasks $(echo "$task_arns" | tr '\n' ' ') \
                --region "$ECS_REGION" \
                --query "tasks[*].{id:taskArn,def:taskDefinitionArn,health:healthStatus}" \
                --output json 2>/dev/null | \
                jq -r '.[] | "\(.id | split("/")[-1])  [\(.health)]  \(.def | split(":")[-2] | split("/")[-1]):\(.def | split(":")[-1])"')

            local selected
            selected=$(echo "$task_lines" | fzf --prompt="task> " --height=40% --border) || return 1
            [[ -z "$selected" ]] && return 1

            local selected_id
            selected_id=$(echo "$selected" | awk '{print $1}')
            task_arn=$(echo "$task_arns" | grep "$selected_id")
        else
            task_arn=$(echo "$task_arns" | head -1)
        fi

        task_id="${task_arn##*/}"
    fi

    local instance_arn
    instance_arn=$(aws ecs describe-tasks \
        --cluster "$cluster" \
        --tasks "$task_id" \
        --region "$ECS_REGION" \
        --query "tasks[0].containerInstanceArn" \
        --output text)

    local ec2_id
    ec2_id=$(_ecs_instance_id "$cluster" "$instance_arn")
    [[ -z "$ec2_id" || "$ec2_id" == "None" ]] && { echo "Could not resolve EC2 instance" >&2; return 1; }

    echo "$task_id $ec2_id"
}

# ecs-status [service [cluster [task_id]]]
# fzf picks any omitted args. Pass all three to bypass funnel entirely.
ecs-status() {
    local service="${1:-}"
    local cluster="${2:-}"
    local task_hint="${3:-}"

    local picked
    picked=$(_ecs_pick_cluster_service "$cluster" "$service") || return 1
    read cluster service <<< "$picked"

    echo "=== $service | cluster: $cluster ==="
    echo ""

    echo "--- Task Sets ---"
    aws ecs describe-services \
        --cluster "$cluster" \
        --services "$service" \
        --region "$ECS_REGION" \
        --query "services[0].taskSets[*].{status:status,taskDef:taskDefinition,running:runningCount,stability:stabilityStatus}" \
        --output table

    echo ""
    echo "--- Container Health (pick task) ---"
    local task_info
    task_info=$(_ecs_debug_task "$cluster" "$service" "$task_hint") || { echo "No running tasks"; return 0; }
    local task_id="${task_info%% *}"

    aws ecs describe-tasks \
        --cluster "$cluster" \
        --tasks "$task_id" \
        --region "$ECS_REGION" \
        --query "tasks[0].{taskId:taskArn,health:healthStatus,containers:containers[*].{name:name,health:healthStatus,status:lastStatus}}" \
        --output json | jq -r '"Task: \(.taskId | split("/")[-1]) [\(.health)]",
            (.containers[] | "  \(.name): \(.health) [\(.status)]")'

    echo ""
    echo "--- Last 5 Events ---"
    aws ecs describe-services \
        --cluster "$cluster" \
        --services "$service" \
        --region "$ECS_REGION" \
        --query "services[0].events[:5].message" \
        --output text | tr '\t' '\n'

    echo ""
    echo "# Rerun: ecss $service $cluster $task_id"
}

# ecs-logs [container [cluster [service [task_id]]]]
# fzf picks any omitted args. Pass all four to bypass funnel entirely.
ecs-logs() {
    local container="${1:-}"
    local cluster="${2:-}"
    local service="${3:-}"
    local task_hint="${4:-}"

    local picked
    picked=$(_ecs_pick_cluster_service "$cluster" "$service") || return 1
    read cluster service <<< "$picked"

    local resolved
    resolved=$(_ecs_resolve_container "$cluster" "$service" "$container" "$task_hint") || return 1
    local task_id ec2_id container runtime_id
    read task_id ec2_id container runtime_id <<< "$resolved"

    local short="${runtime_id:0:12}"
    echo "Task: $task_id  EC2: $ec2_id  Container: $short"
    echo ""
    local short_q="${(q)short}"
    _ecs_ssm_run "$ec2_id" "docker logs $short_q 2>&1"
    echo ""
    echo "# Rerun: ecsl $container $cluster $service $task_id"
}

# ecs-logs-follow [container [cluster [service [task_id]]]]
# Like ecs-logs but streams live via SSM interactive session (Ctrl+C to stop).
ecs-logs-follow() {
    local container="${1:-}"
    local cluster="${2:-}"
    local service="${3:-}"
    local task_hint="${4:-}"

    local picked
    picked=$(_ecs_pick_cluster_service "$cluster" "$service") || return 1
    read cluster service <<< "$picked"

    local resolved
    resolved=$(_ecs_resolve_container "$cluster" "$service" "$container" "$task_hint") || return 1
    local task_id ec2_id container runtime_id
    read task_id ec2_id container runtime_id <<< "$resolved"

    local short="${runtime_id:0:12}"
    local parameters
    parameters=$(jq -cn --arg command "docker logs -f $short" '{command: [$command]}') || return 1
    echo "Tailing: $short on $ec2_id  (Ctrl+C to stop)"
    echo "# Rerun: ecslf $container $cluster $service $task_id"
    echo ""
    aws ssm start-session \
        --target "$ec2_id" \
        --document-name AWS-StartInteractiveCommand \
        --parameters "$parameters" \
        --region "$ECS_REGION"
}

# ecs-exec <cluster> <service> <container> <cmd> [task_id]
# Runs a command inside a container via SSM + docker exec.
ecs-exec() {
    local cluster="${1:?Usage: ecs-exec <cluster> <service> <container> <cmd> [task_id]}"
    local service="${2:?Usage: ecs-exec <cluster> <service> <container> <cmd> [task_id]}"
    local container="${3:?Usage: ecs-exec <cluster> <service> <container> <cmd> [task_id]}"
    local cmd="${4:?Usage: ecs-exec <cluster> <service> <container> <cmd> [task_id]}"
    local task_hint="${5:-}"

    local task_info
    task_info=$(_ecs_debug_task "$cluster" "$service" "$task_hint") || return 1
    local task_id="${task_info%% *}"
    local ec2_id="${task_info##* }"

    local runtime_id
    runtime_id=$(aws ecs describe-tasks \
        --cluster "$cluster" \
        --tasks "$task_id" \
        --region "$ECS_REGION" \
        --query "tasks[0].containers[?name=='$container'].runtimeId | [0]" \
        --output text 2>/dev/null)

    [[ -z "$runtime_id" || "$runtime_id" == "None" ]] && { echo "Container '$container' not found in task $task_id"; return 1; }

    local short="${runtime_id:0:12}"
    echo "docker exec $short $cmd"
    echo ""
    local short_q="${(q)short}"
    local cmd_q="${(q)cmd}"
    _ecs_ssm_run "$ec2_id" "docker exec $short_q sh -lc $cmd_q 2>&1"
    echo ""
    echo "# Rerun: ecse $cluster $service $container \"$cmd\" $task_id"
}

# ecs-curl <cluster> <service> <url> [task_id]
# HTTP GET from inside the task's network namespace via nsenter.
# Works for localhost endpoints (awsvpc — no docker network IP).
ecs-curl() {
    local cluster="${1:?Usage: ecs-curl <cluster> <service> <url> [task_id]}"
    local service="${2:?Usage: ecs-curl <cluster> <service> <url> [task_id]}"
    local url="${3:?Usage: ecs-curl <cluster> <service> <url> [task_id]}"
    local task_hint="${4:-}"

    case "$url" in
        http://*|https://*) ;;
        *)
            echo "URL must start with http:// or https://"
            return 1
            ;;
    esac

    # Exclude sidecar containers from the app-container pick.
    # Override per-session: ECS_CURL_EXCLUDE_CONTAINERS=log_router,opa,envoy
    local exclude="${ECS_CURL_EXCLUDE_CONTAINERS:-log_router,opa}"
    local jq_exclude=""
    local IFS=','
    local _name
    for _name in $exclude; do
        [[ -n "$_name" ]] && jq_exclude+=" && name!='$_name'"
    done
    unset IFS _name

    local task_info
    task_info=$(_ecs_debug_task "$cluster" "$service" "$task_hint") || return 1
    local task_id="${task_info%% *}"
    local ec2_id="${task_info##* }"

    local runtime_id
    runtime_id=$(aws ecs describe-tasks \
        --cluster "$cluster" \
        --tasks "$task_id" \
        --region "$ECS_REGION" \
        --query "tasks[0].containers[?name${jq_exclude}].runtimeId | [0]" \
        --output text 2>/dev/null)

    [[ -z "$runtime_id" || "$runtime_id" == "None" ]] && { echo "No app container found"; return 1; }

    local short="${runtime_id:0:12}"
    local short_q="${(q)short}"
    local url_q="${(q)url}"
    echo "curl $url  (via nsenter into $short)"
    echo ""
    _ecs_ssm_run "$ec2_id" \
        "PID=\$(docker inspect $short_q --format '{{.State.Pid}}') && nsenter -t \$PID --net -- curl -fsS -- $url_q 2>&1"
    echo ""
    echo "# Rerun: ecsc $cluster $service $url $task_id"
}

alias ecss='ecs-status'
alias ecsl='ecs-logs'
alias ecslf='ecs-logs-follow'
alias ecse='ecs-exec'
alias ecsc='ecs-curl'
