#!/usr/bin/env bash
# test-sa.sh — Test service account permissions against Vertex AI
# Usage: bash test-sa.sh [--sa-key PATH] [--project PROJECT] [--region REGION] [--model MODEL]
# Exit codes: 0 = SA can call Vertex AI, 1 = failed
# Read-only — does not modify any files
set -euo pipefail

SA_KEY="${GOOGLE_APPLICATION_CREDENTIALS:-}"
PROJECT="${ANTHROPIC_VERTEX_PROJECT_ID:-}"
REGION="us-east5"
MODEL="claude-sonnet-4-6"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sa-key)  SA_KEY="$2"; shift 2 ;;
    --project) PROJECT="$2"; shift 2 ;;
    --region)  REGION="$2"; shift 2 ;;
    --model)   MODEL="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: bash test-sa.sh [--sa-key PATH] [--project PROJECT] [--region REGION] [--model MODEL]"
      echo "  --sa-key  PATH     Service account key file (default: \$GOOGLE_APPLICATION_CREDENTIALS)"
      echo "  --project PROJECT  GCP project ID (default: \$ANTHROPIC_VERTEX_PROJECT_ID or gcloud)"
      echo "  --region  REGION   Vertex AI region (default: us-east5)"
      echo "  --model   MODEL    Model to test (default: claude-sonnet-4-6)"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 2 ;;
  esac
done

# Auto-detect project if not set
if [[ -z "$PROJECT" ]]; then
  PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
fi

if [[ -z "$PROJECT" ]]; then
  echo "❌ No project specified. Use --project or set ANTHROPIC_VERTEX_PROJECT_ID"
  exit 1
fi

# Auto-detect SA key if not set
if [[ -z "$SA_KEY" ]]; then
  SA_KEY=$(find ~/.config/gcloud/legacy_credentials -name "adc.json" 2>/dev/null | head -1 || echo "")
fi

if [[ -z "$SA_KEY" || ! -f "$SA_KEY" ]]; then
  echo "❌ No service account key found. Use --sa-key or set GOOGLE_APPLICATION_CREDENTIALS"
  exit 1
fi

echo "Testing Vertex AI access..."
echo "  SA Key:  $SA_KEY"
echo "  Project: $PROJECT"
echo "  Region:  $REGION"
echo "  Model:   $MODEL"
echo ""

python3 << PYEOF
from google.oauth2 import service_account
import google.auth.transport.requests
import urllib.request, json, sys

SCOPES = ['https://www.googleapis.com/auth/cloud-platform']
try:
    creds = service_account.Credentials.from_service_account_file(
        '$SA_KEY', scopes=SCOPES)
    creds.refresh(google.auth.transport.requests.Request())
except Exception as e:
    print(f'❌ Failed to load/refresh SA credentials: {e}')
    sys.exit(1)

host = '${REGION}-aiplatform.googleapis.com'
url = (f'https://{host}/v1/projects/$PROJECT/locations/$REGION'
       f'/publishers/anthropic/models/$MODEL:streamRawPredict')

payload = json.dumps({
    'anthropic_version': 'vertex-2023-10-16',
    'max_tokens': 10, 'stream': False,
    'messages': [{'role': 'user', 'content': 'Say hi'}]
}).encode()

req = urllib.request.Request(url, data=payload, method='POST', headers={
    'Authorization': f'Bearer {creds.token}',
    'Content-Type': 'application/json',
})

try:
    resp = urllib.request.urlopen(req)
    result = json.loads(resp.read())
    text = result['content'][0]['text'].strip()
    print(f'✅ Success: {text}')
except urllib.error.HTTPError as e:
    body = e.read().decode()[:300]
    print(f'❌ HTTP {e.code}: {body}')
    if e.code == 403:
        print()
        print('   The service account needs the Vertex AI User role.')
        print('   Contact your GCP admin to grant roles/aiplatform.user.')
    sys.exit(1)
PYEOF
