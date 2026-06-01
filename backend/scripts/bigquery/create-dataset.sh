#!/bin/bash
# Run once to create the BigQuery dataset and events table.
# Usage: PROJECT_ID=your-project bash scripts/bigquery/create-dataset.sh

set -e

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"
DATASET="metrosafar_analytics"
LOCATION="asia-south1"

echo "Creating dataset $DATASET in project $PROJECT_ID..."
bq mk --location="$LOCATION" --dataset "$PROJECT_ID:$DATASET" 2>/dev/null || echo "Dataset already exists"

echo "Creating events table..."
bq mk --table \
  --time_partitioning_field=event_date \
  --time_partitioning_type=DAY \
  --time_partitioning_expiration=46656000 \
  --clustering_fields=event_name,city_id \
  "$PROJECT_ID:$DATASET.events" \
  scripts/bigquery/events_schema.json

echo "Done!"
