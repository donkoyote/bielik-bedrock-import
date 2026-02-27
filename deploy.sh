#!/bin/bash
# ============================================================
#  Bielik 11B → Amazon Bedrock
#
#  Uruchom w AWS CloudShell (jedyna komenda którą musisz znać):
#
#    bash <(curl -fsSL https://raw.githubusercontent.com/donkoyote/bielik-bedrock-import/main/deploy.sh)
#
#  Repozytorium: https://github.com/donkoyote/bielik-bedrock-import
#  Blog:         https://poznajaws.pl
#  YouTube:      https://www.youtube.com/@livinginacloud
#
#  CFN template wbudowany w skrypt — zero zewnętrznych zależności.
#  Działa od razu po sklonowaniu lub curl-u, nawet bez dostępu do GitHub.
# ============================================================

set -euo pipefail

# ── Kolory ──────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

log()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
step() { echo -e "\n${BOLD}━━━  $*  ━━━${NC}"; }

# ── Banner ──────────────────────────────────────────────────
echo -e "
${BOLD}╔══════════════════════════════════════════════════╗
║   🦅  Bielik 11B → Amazon Bedrock               ║
║   @livinginacloud · youtube.com               ║
╚══════════════════════════════════════════════════╝${NC}
"

# ── Konfiguracja ─────────────────────────────────────────────
STACK_NAME="bielik-bedrock-import"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
TEMPLATE_FILE="/tmp/bielik-bedrock-import.yaml"

# ── Krok 0: Sprawdź środowisko ────────────────────────────────
step "Krok 0: Sprawdzanie środowiska"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) \
  || err "Nie można pobrać tożsamości AWS. Czy jesteś w CloudShell?"

log "Account ID : ${ACCOUNT_ID}"
log "Region     : ${REGION}"

SUPPORTED_REGIONS=("eu-central-1" "us-east-1" "us-east-2" "us-west-2")
if [[ ! " ${SUPPORTED_REGIONS[*]} " =~ " ${REGION} " ]]; then
  warn "Region ${REGION} może nie obsługiwać Bedrock Custom Model Import."
  warn "Rekomendowany region: us-east-1"
  read -rp "  Kontynuować mimo to? [t/N]: " confirm
  [[ "$confirm" =~ ^[tT]$ ]] || err "Zmień region: export AWS_DEFAULT_REGION=us-east-1 i uruchom ponownie."
fi
ok "Środowisko OK"

# ── Krok 1a: Akceptacja warunków modelu na HuggingFace ────────
step "Krok 1: Akceptacja warunków modelu"

echo ""
echo -e "  Model Bielik jest ${BOLD}gated${NC} — wymaga jednorazowej akceptacji warunków."
echo ""
echo -e "  ${BOLD}👉 Otwórz poniższy link w przeglądarce i kliknij 'Agree and access repository':${NC}"
echo ""
echo -e "     ${YELLOW}https://huggingface.co/speakleash/Bielik-11B-v3.0-Instruct${NC}"
echo ""
echo -e "  ${BOLD}⚠️  Bez tego kroku pobieranie modelu zakończy się błędem 403!${NC}"
echo ""

while true; do
  read -rp "  Czy zaakceptowałeś/aś warunki na stronie modelu? [t/N]: " accepted
  if [[ "$accepted" =~ ^[tT]$ ]]; then
    ok "Warunki zaakceptowane — przechodzimy dalej"
    break
  else
    echo ""
    warn "Poczekaj — najpierw wejdź na stronę modelu i kliknij 'Agree and access repository':"
    echo -e "     ${YELLOW}https://huggingface.co/speakleash/Bielik-11B-v3.0-Instruct${NC}"
    echo ""
  fi
done

# ── Krok 1b: Token HuggingFace ────────────────────────────────
step "Krok 2: Token HuggingFace"

echo ""
echo -e "  Teraz wygeneruj token dostępu (jeśli jeszcze nie masz)."
echo -e "  ${BOLD}👉${NC} Wejdź na: ${YELLOW}https://huggingface.co/settings/tokens${NC}"
echo -e "  ${BOLD}👉${NC} Kliknij 'New token' → uprawnienie: ${BOLD}read${NC} → skopiuj"
echo ""
read -rsp "  Wklej token HuggingFace (hf_...): " HF_TOKEN
echo ""
[[ "$HF_TOKEN" =~ ^hf_ ]] || err "Token powinien zaczynać się od 'hf_'. Sprawdź i uruchom ponownie."
ok "Token wygląda poprawnie"

# ── Krok 2: Zapisz szablon CFN ────────────────────────────────
#
#  Template jest wbudowany bezpośrednio w ten skrypt (heredoc).
#  Nie wymaga dostępu do GitHub ani żadnego zewnętrznego URL.
#
step "Krok 3: Przygotowanie szablonu CloudFormation"

cat > "$TEMPLATE_FILE" << 'CFNEOF'
AWSTemplateFormatVersion: '2010-09-09'
Description: >
  LIAC — Bielik 11B na Amazon Bedrock.
  Tworzy: S3 bucket, IAM roles, SSM parameter, CodeBuild project.
  Repozytorium: https://github.com/donkoyote/bielik-bedrock-import

Parameters:
  HuggingFaceToken:
    Type: String
    NoEcho: true
    Description: Token API z HuggingFace (read)
  ModelId:
    Type: String
    Default: speakleash/Bielik-11B-v3.0-Instruct
  BedrockModelName:
    Type: String
    Default: Bielik-11B-v3-Instruct
  S3Prefix:
    Type: String
    Default: bielik-11b-v3

Resources:

  ModelBucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Sub "donkoyote-bielik-${AWS::AccountId}-${AWS::Region}"
      BucketEncryption:
        ServerSideEncryptionConfiguration:
          - ServerSideEncryptionByDefault:
              SSEAlgorithm: AES256
      PublicAccessBlockConfiguration:
        BlockPublicAcls: true
        BlockPublicPolicy: true
        IgnorePublicAcls: true
        RestrictPublicBuckets: true
      Tags:
        - Key: Project
          Value: LIAC-Bielik

  HuggingFaceTokenParam:
    Type: AWS::SSM::Parameter
    Properties:
      Name: /bielik-bedrock/hf-token
      Type: String
      Value: !Ref HuggingFaceToken
      Description: HuggingFace API token dla importu Bielik 11B

  BedrockImportRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub "LIAC-Bielik-Bedrock-${AWS::Region}"
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: bedrock.amazonaws.com
            Action: sts:AssumeRole
      Policies:
        - PolicyName: S3ReadForImport
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action: [s3:GetObject, s3:ListBucket]
                Resource:
                  - !GetAtt ModelBucket.Arn
                  - !Sub "${ModelBucket.Arn}/*"

  CodeBuildRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub "LIAC-Bielik-CodeBuild-${AWS::Region}"
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: codebuild.amazonaws.com
            Action: sts:AssumeRole
      Policies:
        - PolicyName: S3Access
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action: [s3:PutObject, s3:GetObject, s3:ListBucket, s3:DeleteObject]
                Resource:
                  - !GetAtt ModelBucket.Arn
                  - !Sub "${ModelBucket.Arn}/*"
        - PolicyName: BedrockImport
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action:
                  - bedrock:CreateModelImportJob
                  - bedrock:GetModelImportJob
                  - bedrock:ListModelImportJobs
                  - bedrock:GetImportedModel
                Resource: "*"
        - PolicyName: SSMRead
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action: ssm:GetParameter
                Resource: !Sub "arn:aws:ssm:${AWS::Region}:${AWS::AccountId}:parameter/bielik-bedrock/*"
        - PolicyName: CloudWatchLogs
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action: [logs:CreateLogGroup, logs:CreateLogStream, logs:PutLogEvents]
                Resource: !Sub "arn:aws:logs:${AWS::Region}:${AWS::AccountId}:log-group:/aws/codebuild/*"
        - PolicyName: PassRoleToBedrock
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action: iam:PassRole
                Resource: !GetAtt BedrockImportRole.Arn

  BielikImportProject:
    Type: AWS::CodeBuild::Project
    Properties:
      Name: LIAC-Bielik-Import
      Description: "HuggingFace → S3 → Amazon Bedrock import dla Bielik 11B"
      ServiceRole: !GetAtt CodeBuildRole.Arn
      TimeoutInMinutes: 480
      QueuedTimeoutInMinutes: 60
      Environment:
        Type: LINUX_CONTAINER
        ComputeType: BUILD_GENERAL1_LARGE
        Image: aws/codebuild/standard:7.0
        PrivilegedMode: false
        EnvironmentVariables:
          - Name: BUCKET_NAME
            Value: !Ref ModelBucket
          - Name: MODEL_ID
            Value: !Ref ModelId
          - Name: BEDROCK_MODEL_NAME
            Value: !Ref BedrockModelName
          - Name: S3_PREFIX
            Value: !Ref S3Prefix
          - Name: BEDROCK_IMPORT_ROLE_ARN
            Value: !GetAtt BedrockImportRole.Arn
          - Name: HF_TOKEN_SSM_PATH
            Value: !Ref HuggingFaceTokenParam
          - Name: AWS_REGION_NAME
            Value: !Ref AWS::Region
      Source:
        Type: NO_SOURCE
        BuildSpec: |
          version: 0.2
          phases:
            install:
              runtime-versions:
                python: 3.11
              commands:
                - pip install huggingface_hub --quiet
                - |
                  cat > /tmp/download_model.py << 'ENDOFSCRIPT'
                  import os, sys
                  from huggingface_hub import snapshot_download
                  print("Pobieranie modelu:", os.environ["MODEL_ID"])
                  snapshot_download(
                      repo_id=os.environ["MODEL_ID"],
                      local_dir="/tmp/model",
                      token=os.environ["HF_TOKEN"],
                      ignore_patterns=["*.md", ".gitattributes", "*.txt"],
                  )
                  print("Download OK")
                  ENDOFSCRIPT
                - |
                  cat > /tmp/bedrock_import.py << 'ENDOFSCRIPT'
                  import boto3, os, time, sys
                  bedrock = boto3.client("bedrock", region_name=os.environ["AWS_REGION_NAME"])
                  job = bedrock.create_model_import_job(
                      jobName="bielik-" + str(int(time.time())),
                      importedModelName=os.environ["BEDROCK_MODEL_NAME"],
                      roleArn=os.environ["BEDROCK_IMPORT_ROLE_ARN"],
                      modelDataSource={
                          "s3DataSource": {
                              "s3Uri": "s3://" + os.environ["BUCKET_NAME"] + "/" + os.environ["S3_PREFIX"] + "/"
                          }
                      }
                  )
                  job_arn = job["jobArn"]
                  print("Job ARN: " + job_arn)
                  for i in range(60):
                      time.sleep(60)
                      resp = bedrock.get_model_import_job(jobIdentifier=job_arn)
                      state = resp["status"]
                      print("[" + str(i+1) + "/60] " + state)
                      if state == "Complete":
                          print("Model gotowy!")
                          print("ARN: " + resp.get("importedModelArn", ""))
                          sys.exit(0)
                      elif state in ("Failed", "Cancelled"):
                          print("BLAD: " + resp.get("failureMessage", "Nieznany blad"))
                          sys.exit(1)
                  print("Polling timeout - sprawdz Bedrock console")
                  sys.exit(1)
                  ENDOFSCRIPT
            pre_build:
              commands:
                - echo "Pobieranie tokenu z SSM"
                - export HF_TOKEN=$(aws ssm get-parameter --name "$HF_TOKEN_SSM_PATH" --query Parameter.Value --output text)
                - echo "Token OK | Model $MODEL_ID | Bucket $BUCKET_NAME/$S3_PREFIX"
                - df -h /
            build:
              commands:
                - echo "Download modelu z HuggingFace"
                - python3 /tmp/download_model.py
                - echo "Sync do S3"
                - aws s3 sync /tmp/model s3://$BUCKET_NAME/$S3_PREFIX/ --no-progress
                - echo "S3 sync OK"
                - aws s3 ls s3://$BUCKET_NAME/$S3_PREFIX/ --recursive --human-readable
                - echo "Sprawdzanie wymaganych plikow..."
                - aws s3 ls s3://$BUCKET_NAME/$S3_PREFIX/config.json || (echo "BLAD: brak config.json" && exit 1)
                - SHARD_COUNT=$(aws s3 ls s3://$BUCKET_NAME/$S3_PREFIX/ --recursive | grep "safetensors$" | wc -l)
                - echo "Znaleziono shardow: $SHARD_COUNT"
                - "[ \"\$SHARD_COUNT\" -ge 1 ] || (echo \"BLAD: brak plikow safetensors - model niepelny\" && exit 1)"
                - echo "Weryfikacja OK - $SHARD_COUNT shardow gotowych do importu"
            post_build:
              commands:
                - echo "Import do Amazon Bedrock"
                - python3 /tmp/bedrock_import.py
      Artifacts:
        Type: NO_ARTIFACTS
      LogsConfig:
        CloudWatchLogs:
          Status: ENABLED
          GroupName: /aws/codebuild/LIAC-Bielik-Import
      Tags:
        - Key: Project
          Value: LIAC-Bielik

Outputs:
  StartBuildCommand:
    Description: "Komenda do uruchomienia importu"
    Value: !Sub "aws codebuild start-build --project-name ${BielikImportProject} --region ${AWS::Region} --query 'build.id' --output text"
  WatchLogsCommand:
    Description: "Logi na żywo"
    Value: !Sub "aws logs tail /aws/codebuild/LIAC-Bielik-Import --follow --region ${AWS::Region}"
  ModelBucketName:
    Description: "Bucket S3 z plikami modelu"
    Value: !Ref ModelBucket
  CheckBedrockModels:
    Description: "Sprawdź zaimportowane modele"
    Value: !Sub "aws bedrock list-imported-models --region ${AWS::Region} --query 'modelSummaries[*].{Name:modelName,Status:modelStatus,ARN:modelArn}' --output table"
CFNEOF

ok "Szablon CFN gotowy → ${TEMPLATE_FILE}"

# ── Krok 3: Deploy CloudFormation ─────────────────────────────
step "Krok 4: Deploy stacka CloudFormation"

log "Tworzenie / aktualizowanie stacka: ${STACK_NAME}"
log "To zajmie ~2 minuty..."

aws cloudformation deploy \
  --template-file "$TEMPLATE_FILE" \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    HuggingFaceToken="$HF_TOKEN" \
  --tags \
    Project=LIAC-Bielik \
  --no-fail-on-empty-changeset

ok "Stack CFN gotowy ✅"

# ── Krok 4: Odczyt Outputs ────────────────────────────────────
step "Krok 5: Odczyt konfiguracji"

get_output() {
  aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" \
    --output text
}

CMD_LOGS=$(get_output WatchLogsCommand)
CMD_CHECK=$(get_output CheckBedrockModels)
BUCKET=$(get_output ModelBucketName)

ok "Bucket S3 : ${BUCKET}"

# ── Krok 5: Uruchom CodeBuild ──────────────────────────────────
step "Krok 6: Uruchamianie importu (CodeBuild)"

log "Startuję build..."
BUILD_ID=$(aws codebuild start-build \
  --project-name LIAC-Bielik-Import \
  --region "$REGION" \
  --query 'build.id' \
  --output text)

ok "Build uruchomiony! ID: ${BUILD_ID}"

# ── Podsumowanie ───────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  🚀 Import uruchomiony! Co dalej:                           ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}📋 Obserwuj logi na żywo:${NC}"
echo -e "   ${YELLOW}${CMD_LOGS}${NC}"
echo ""
echo -e "${BOLD}🔍 Sprawdź status buildu:${NC}"
echo -e "   ${YELLOW}aws codebuild batch-get-builds --ids '${BUILD_ID}' --query 'builds[0].{Status:buildStatus,Phase:currentPhase}' --output table --region ${REGION}${NC}"
echo ""
echo -e "${BOLD}🤖 Po zakończeniu — sprawdź model w Bedrock:${NC}"
echo -e "   ${YELLOW}${CMD_CHECK}${NC}"
echo ""
echo -e "${BOLD}⏱  Szacowany czas:${NC}  35–55 minut (download + upload + Bedrock import)"
echo -e "${BOLD}💰 Szacowany koszt:${NC} ~\$0.30 + opłata Bedrock za import"
echo ""
echo -e "Masz pytania? → ${BOLD}poznajaws.pl${NC} lub ${BOLD}youtube.com/@livinginacloud${NC}"
echo ""
