# Elasticsearch Log Retention Management Guide

This guide explains how to manage log retention policies for your Bluesky self-hosted instance using Elasticsearch Index Lifecycle Management (ILM).

## Table of Contents
- [Overview](#overview)
- [Retention Policies](#retention-policies)
- [Setup](#setup)
- [Management](#management)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

## Overview

Index Lifecycle Management (ILM) automatically manages the lifecycle of your Elasticsearch indices based on:
- **Age**: How old the index is
- **Size**: How large the index has grown
- **Performance**: Moving data through hot/warm/cold phases

### Why Use ILM?

1. **Automatic cleanup**: Old logs are deleted automatically
2. **Cost optimization**: Reduce storage costs by removing old data
3. **Performance**: Keep your cluster fast by limiting data volume
4. **Compliance**: Maintain logs for required retention periods

## Retention Policies

We provide three pre-configured retention policies:

### 1. Standard 30-Day Retention (Default)
**Policy Name**: `filebeat-30day-policy`

```
Hot Phase:    0-7 days    (Active indexing, full search speed)
Warm Phase:   7-30 days   (Read-only, slower searches)
Delete:       After 30 days
```

**Best for**:
- General application logs
- Debug logs
- Performance monitoring
- Development logs

**Services**:
- Caddy (proxy logs)
- Social-app (frontend logs)
- Feed-generator
- Jetstream

### 2. Long 90-Day Retention
**Policy Name**: `filebeat-90day-policy`

```
Hot Phase:    0-30 days   (Active indexing)
Warm Phase:   30-60 days  (Read-only)
Cold Phase:   60-90 days  (Infrequent access)
Delete:       After 90 days
```

**Best for**:
- Audit logs
- Security events
- Compliance logs
- User activity tracking

**Services**:
- PDS (user data, authentication)
- Ozone (moderation decisions)
- PLC (identity changes)
- BGS (relay events)

### 3. Short 7-Day Retention
**Policy Name**: `filebeat-7day-policy`

```
Hot Phase:    0-3 days    (Active indexing)
Delete:       After 7 days
```

**Best for**:
- Verbose debug logs
- High-volume metrics
- Testing/development
- Temporary debugging

## Setup

### Initial Setup

1. **Deploy the Elastic Stack** (if not already done):
```bash
docker stack deploy -c docker-compose.swarm.yaml foodios_staging
```

2. **Wait for Elasticsearch to be ready** (~60 seconds):
```bash
# Check if Elasticsearch is ready
curl http://localhost:9201/_cluster/health

# Watch the logs
docker service logs -f foodios_staging_elasticsearch
```

3. **Apply retention policies**:
```bash
cd config/logging
./setup-retention-policies.sh
```

You should see:
```
✓ All policies applied successfully!

Current ILM Policies:
====================
  - filebeat-30day-policy
  - filebeat-90day-policy
  - filebeat-7day-policy
```

### Applying Policies to Specific Services

By default, all logs use the 30-day retention policy. To apply different policies to specific services:

#### Example: 90-day retention for PDS logs
```bash
curl -X PUT http://localhost:9201/filebeat-pds-*/_settings \
  -H 'Content-Type: application/json' \
  -d '{
    "index.lifecycle.name": "filebeat-90day-policy"
  }'
```

#### Example: 7-day retention for debug logs
```bash
curl -X PUT http://localhost:9201/filebeat-social-app-*/_settings \
  -H 'Content-Type: application/json' \
  -d '{
    "index.lifecycle.name": "filebeat-7day-policy"
  }'
```

### Recommended Policy Assignments

```bash
# 90-day retention (compliance/security)
curl -X PUT http://localhost:9201/filebeat-pds-*/_settings \
  -H 'Content-Type: application/json' \
  -d '{"index.lifecycle.name": "filebeat-90day-policy"}'

curl -X PUT http://localhost:9201/filebeat-ozone-*/_settings \
  -H 'Content-Type: application/json' \
  -d '{"index.lifecycle.name": "filebeat-90day-policy"}'

curl -X PUT http://localhost:9201/filebeat-plc-*/_settings \
  -H 'Content-Type: application/json' \
  -d '{"index.lifecycle.name": "filebeat-90day-policy"}'

# 30-day retention (default) - already applied
# No action needed for: caddy, bsky, social-app, etc.

# 7-day retention (high-volume debug)
# Apply as needed for specific debugging
```

## Management

### Using the Management Script

We provide a comprehensive management script for monitoring and managing retention:

```bash
cd config/logging
./manage-log-retention.sh [COMMAND]
```

#### Available Commands:

**1. View Current Status**
```bash
./manage-log-retention.sh status
```
Shows:
- Cluster health
- Disk usage
- Index count and sizes
- Active policies

**2. List All Policies**
```bash
./manage-log-retention.sh policies
```

**3. Check Policy Status for Indices**
```bash
./manage-log-retention.sh explain filebeat-pds-*
```
Shows which phase each index is in (hot/warm/cold/delete)

**4. Apply Policy to Indices**
```bash
./manage-log-retention.sh apply filebeat-90day-policy filebeat-bgs-*
```

**5. List All Indices**
```bash
./manage-log-retention.sh indices
```

**6. View Detailed Statistics**
```bash
./manage-log-retention.sh stats
```

**7. Trigger Manual Cleanup**
```bash
./manage-log-retention.sh cleanup
```

### Monitoring Disk Usage

#### Check total Elasticsearch disk usage:
```bash
curl http://localhost:9201/_cat/allocation?v
```

#### Check individual index sizes:
```bash
curl http://localhost:9201/_cat/indices/filebeat-*?v&h=index,store.size&s=store.size:desc
```

#### View largest indices:
```bash
curl -s http://localhost:9201/_cat/indices/filebeat-*?h=index,store.size | \
  sort -k2 -hr | head -10
```

## Best Practices

### 1. Monitor Disk Usage Regularly

Set up alerts when disk usage exceeds 80%:
```bash
# Add to cron for daily checks
0 9 * * * /path/to/manage-log-retention.sh status | grep "disk.percent" | awk '$3 > 80 {print "WARNING: Disk usage above 80%"}'
```

### 2. Adjust Policies Based on Usage

After running for a week, check which services generate the most logs:
```bash
./manage-log-retention.sh stats
```

Adjust policies accordingly:
- High-volume, low-importance logs → 7-day policy
- Important audit logs → 90-day policy

### 3. Regular Policy Reviews

Review and adjust policies quarterly:
```bash
# Check current policy assignments
curl http://localhost:9201/_ilm/explain/filebeat-*?human | \
  jq '.indices | to_entries[] | {index: .key, policy: .value.policy}'
```

### 4. Backup Important Indices

Before deletion, important indices can be backed up:
```bash
# Snapshot important index before deletion
curl -X PUT "http://localhost:9201/_snapshot/my_backup/snapshot_1?wait_for_completion=true" \
  -H 'Content-Type: application/json' \
  -d '{
    "indices": "filebeat-pds-2024.01.01",
    "ignore_unavailable": true
  }'
```

### 5. Storage Estimation

Estimate storage needs:
- **Low volume** (< 1GB/day): 30-day policy = ~30GB
- **Medium volume** (1-5GB/day): 30-day policy = ~150GB
- **High volume** (> 5GB/day): Consider 7-day policy or add storage

## Customizing Policies

### Creating a Custom Policy

1. Create a new policy file `elasticsearch-ilm-policy-custom.json`:
```json
{
  "policy": {
    "phases": {
      "hot": {
        "min_age": "0ms",
        "actions": {
          "rollover": {
            "max_primary_shard_size": "50gb",
            "max_age": "14d"
          }
        }
      },
      "delete": {
        "min_age": "14d",
        "actions": {
          "delete": {}
        }
      }
    }
  }
}
```

2. Apply it:
```bash
curl -X PUT http://localhost:9201/_ilm/policy/filebeat-14day-policy \
  -H 'Content-Type: application/json' \
  -d @elasticsearch-ilm-policy-custom.json
```

3. Assign to indices:
```bash
curl -X PUT http://localhost:9201/filebeat-myservice-*/_settings \
  -H 'Content-Type: application/json' \
  -d '{"index.lifecycle.name": "filebeat-14day-policy"}'
```

## Troubleshooting

### Indices Not Being Deleted

**Check ILM status:**
```bash
curl http://localhost:9201/_ilm/status
```

Should return: `{"operation_mode":"RUNNING"}`

**If stopped, start ILM:**
```bash
curl -X POST http://localhost:9201/_ilm/start
```

**Check specific index status:**
```bash
./manage-log-retention.sh explain filebeat-service-2024.01.01
```

### Policy Not Applying

**Verify policy exists:**
```bash
curl http://localhost:9201/_ilm/policy/filebeat-30day-policy
```

**Check index settings:**
```bash
curl http://localhost:9201/filebeat-service-2024.01.01/_settings | \
  jq '.[] | .settings.index.lifecycle'
```

### Disk Space Still Growing

**Check if ILM is running:**
```bash
curl http://localhost:9201/_ilm/status
```

**Manually trigger phase move:**
```bash
curl -X POST http://localhost:9201/_ilm/_move/filebeat-old-index \
  -H 'Content-Type: application/json' \
  -d '{
    "current_step": {
      "phase": "delete",
      "action": "delete",
      "name": "delete"
    }
  }'
```

**Check for indices without policies:**
```bash
curl -s http://localhost:9201/_cat/indices/filebeat-* | \
  while read -r line; do
    index=$(echo $line | awk '{print $3}')
    policy=$(curl -s "http://localhost:9201/$index/_settings" | \
      jq -r '.[] | .settings.index.lifecycle.name // "NONE"')
    if [ "$policy" = "NONE" ]; then
      echo "$index has no policy"
    fi
  done
```

### Logs Still Visible After Deletion

Elasticsearch marks indices for deletion but may not delete immediately. Check:
```bash
curl http://localhost:9201/_cat/indices?v
```

Look for indices in "close" state - these are being deleted.

## Storage Calculator

Estimate your storage needs:

```
Daily Log Volume × Retention Days = Total Storage Needed

Examples:
- 500MB/day × 30 days = 15GB
- 2GB/day × 30 days = 60GB
- 5GB/day × 90 days = 450GB
```

Add 20% overhead for Elasticsearch metadata and operations.

## Related Commands

```bash
# View cluster stats
curl http://localhost:9201/_cluster/stats?pretty

# View node stats
curl http://localhost:9201/_nodes/stats?pretty

# Clear cache
curl -X POST http://localhost:9201/_cache/clear

# Force merge old indices (before deletion)
curl -X POST http://localhost:9201/filebeat-2024.01.*/_forcemerge?max_num_segments=1
```

## Questions?

For more information:
- [Elasticsearch ILM Documentation](https://www.elastic.co/guide/en/elasticsearch/reference/current/index-lifecycle-management.html)
- [Filebeat Documentation](https://www.elastic.co/guide/en/beats/filebeat/current/index.html)

Run the help command for the management script:
```bash
./manage-log-retention.sh help
```
