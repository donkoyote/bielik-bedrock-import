#!/bin/bash
# ============================================================
#  poznajawspl — Cleanup: usuwa wszystkie zasoby Bielik Bedrock
#  Uruchom w AWS CloudShell: bash <(curl -fsSL https://raw.githubusercontent.com/donkoyote/bielik-bedrock-import/main/cleanup.sh)
# ============================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BOLD='\033[1m'; BLUE='\033[0;34m'; NC='\033[0m'

log()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

STACK_NAME="bielik-bedrock-import"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo -e "\n${BOLD}🗑  poznajawspl — Cleanup Bielik Bedrock Import${NC}\n"
warn "To usunie: S3 bucket (z plikami modelu!), CodeBuild, IAM roles, SSM parameter."
read -rp "Na pewno chcesz usunąć wszystkie zasoby? [t/N]: " confirm
[[ "$confirm" =~ ^[tT]$ ]] || { log "Anulowano."; exit 0; }

# Znajdź bucket
BUCKET=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='ModelBucketName'].OutputValue" \
  --output text 2>/dev/null || echo "")

if [[ -n "$BUCKET" && "$BUCKET" != "None" ]]; then
  log "Czyszczenie bucketu S3: ${BUCKET}"
  aws s3 rm "s3://${BUCKET}" --recursive --quiet && ok "Bucket wyczyszczony"
fi

# Usuń CloudWatch Log Group z buildów CodeBuild
log "Usuwanie CloudWatch Log Group..."
CW_LOG_GROUP="/aws/codebuild/poznajawspl-Bielik-Import"
if aws logs describe-log-groups \
    --log-group-name-prefix "$CW_LOG_GROUP" \
    --region "$REGION" \
    --query 'logGroups[0].logGroupName' \
    --output text 2>/dev/null | grep -q "poznajawspl-Bielik-Import"; then
  aws logs delete-log-group \
    --log-group-name "$CW_LOG_GROUP" \
    --region "$REGION" \
    && ok "CloudWatch Log Group usunięta: ${CW_LOG_GROUP}"
else
  warn "Log Group nie istnieje lub już usunięta — pomijam"
fi

# Usuń SSM parameter z tokenem HuggingFace (tworzony przez deploy.sh poza CFN)
log "Usuwanie SSM Parameter (HuggingFace token)..."
if aws ssm get-parameter --name "/bielik-bedrock/hf-token" --region "$REGION" > /dev/null 2>&1; then
  aws ssm delete-parameter --name "/bielik-bedrock/hf-token" --region "$REGION"
  ok "SSM parameter usunięty: /bielik-bedrock/hf-token"
else
  warn "SSM parameter nie istnieje lub już usunięty — pomijam"
fi

log "Usuwanie stacka CFN: ${STACK_NAME}"
aws cloudformation delete-stack --stack-name "$STACK_NAME" --region "$REGION"
log "Czekam na zakończenie usuwania..."
aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" --region "$REGION"
ok "Stack usunięty ✅"

# Opcjonalnie: usuń zaimportowany model z Bedrock
echo ""
log "Sprawdzanie modeli Bielik w Bedrock..."
MODEL_ARN=$(aws bedrock list-imported-models \
  --region "$REGION" \
  --query "modelSummaries[?contains(modelName,'Bielik')].modelArn" \
  --output text 2>/dev/null || echo "")

if [[ -n "$MODEL_ARN" && "$MODEL_ARN" != "None" ]]; then
  warn "Znaleziono model w Bedrock: ${MODEL_ARN}"
  read -rp "Usunąć zaimportowany model z Bedrock? [t/N]: " del_model
  if [[ "$del_model" =~ ^[tT]$ ]]; then
    aws bedrock delete-imported-model --model-identifier "$MODEL_ARN" --region "$REGION"
    ok "Model usunięty z Bedrock"
  fi
fi

echo ""
ok "Cleanup zakończony. Żadnych zasobów, żadnych kosztów. 👋"
