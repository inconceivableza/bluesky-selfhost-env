-- Add Docker container metadata to log records
-- This script extracts container ID from the file path and queries Docker API

function add_container_metadata(tag, timestamp, record)
    -- Get the container ID from the filepath if it exists
    local filepath = record["_p"]
    if not filepath then
        return 2, timestamp, record
    end

    -- Extract container ID from path like: /var/lib/docker/containers/<container_id>/<file>
    local container_id = string.match(filepath, "/var/lib/docker/containers/([^/]+)/")

    if not container_id then
        return 2, timestamp, record
    end

    -- Add short container ID
    record["container_id"] = string.sub(container_id, 1, 12)

    -- Try to get container name from Docker API
    -- Note: This requires Docker socket access
    local handle = io.popen('docker inspect --format="{{.Name}}" ' .. container_id .. ' 2>/dev/null')
    if handle then
        local container_name = handle:read("*a")
        handle:close()

        if container_name and container_name ~= "" then
            -- Remove leading slash and trailing newline
            container_name = string.gsub(container_name, "^/", "")
            container_name = string.gsub(container_name, "%s+$", "")
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
