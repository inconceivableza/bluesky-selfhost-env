-- Add Docker container metadata to log records
-- This script extracts container ID from the file path and uses tag to get container info

function add_container_metadata(tag, timestamp, record)
    -- Try to get container ID from multiple possible sources
    local container_id = nil

    -- Check if filepath exists in record (we set Path_Key to 'filepath' in config)
    if record["filepath"] then
        container_id = string.match(record["filepath"], "/var/lib/docker/containers/([^/]+)/")
    end

    -- If not found, try to extract from tag
    -- Fluent Bit tail input creates tags like: docker.container_id
    if not container_id and tag then
        container_id = string.match(tag, "docker%.([a-f0-9]+)")
    end

    if not container_id then
        -- No container ID found, add debug info
        record["debug_no_container_id"] = true
        return 2, timestamp, record
    end

    -- Add full and short container ID
    record["container_id_full"] = container_id
    record["container_id"] = string.sub(container_id, 1, 12)

    -- Try to read container name from Docker config.v2.json
    -- This file contains container metadata including name
    local config_file = "/var/lib/docker/containers/" .. container_id .. "/config.v2.json"
    local file = io.open(config_file, "r")

    if file then
        local content = file:read("*a")
        file:close()

        -- Extract container name using pattern matching
        -- Look for "Name":"/<container_name>"
        local container_name = string.match(content, '"Name":"/?([^"]+)"')

        if container_name then
            record["container_name"] = container_name

            -- Extract service name from Swarm container name
            -- Format: stackname_servicename.instance.taskid
            local service_name = string.match(container_name, "^[^_]+_([^%.]+)")
            if service_name then
                record["service_name"] = service_name
            end
        end
    end

    return 2, timestamp, record
end
