# 🦅 Bielik 11B → Amazon Bedrock

> **Jeden command. Zero lokalnej konfiguracji. Polski model AI w chmurze AWS.**

Automatyczny import [Bielik-11B-v3.0-Instruct](https://huggingface.co/speakleash/Bielik-11B-v3.0-Instruct) (projekt [SpeakLeash](https://speakleash.org)) do Amazon Bedrock przez AWS CloudShell — bez instalowania czegokolwiek na swoim komputerze.

📺 **Tutorial na YouTube:** [youtube.com/@livinginacloud](https://www.youtube.com/@livinginacloud)  
📝 **Blog post:** [poznajaws.pl](https://poznajaws.pl)

---

## ⚡ TL;DR — Uruchomienie

Otwórz **[AWS CloudShell](https://console.aws.amazon.com/cloudshell)** i wklej:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/donkoyote/bielik-bedrock-import/main/deploy.sh)
```

Skrypt zapyta tylko o token HuggingFace — resztą zajmie się sam.

---

## Co się dzieje pod spodem?

```
CloudShell (Ty wklejasz 1 komendę)
    │
    ├─ 1. Pobiera szablon CloudFormation z tego repo
    ├─ 2. Tworzy infrastrukturę AWS (~2 min):
    │       ├── S3 Bucket          (pliki modelu ~22 GB)
    │       ├── IAM Role CodeBuild
    │       ├── IAM Role Bedrock
    │       ├── SSM Parameter      (HuggingFace token — bezpiecznie)
    │       └── CodeBuild Project
    └─ 3. Uruchamia CodeBuild, który:
            ├── [install]     pip install huggingface_hub
            ├── [pre_build]   pobiera token z SSM
            ├── [build]       snapshot_download → aws s3 sync (~22 GB)
            └── [post_build]  bedrock.create_model_import_job + polling
```

**Szacowany czas:** 35–55 minut (głównie transfer danych)  
**Szacowany koszt jednorazowy:** ~$0.95–1.40 · **Storage:** ~$0.54/mies · **Inference:** pay-per-use

👉 Szczegółowy breakdown kosztów: [sekcja Koszty infrastruktury](#koszty-infrastruktury--eu-central-1)

---

## Wymagania

- Konto AWS z uprawnieniami: `CloudFormation`, `S3`, `IAM`, `CodeBuild`, `Bedrock`, `SSM`
- Konto [HuggingFace](https://huggingface.co) — darmowe
- Zaakceptowane warunki modelu: [speakleash/Bielik-11B-v3.0-Instruct](https://huggingface.co/speakleash/Bielik-11B-v3.0-Instruct) *(kliknij "Agree" na stronie)*
- Token HuggingFace z uprawnieniem `read` → [wygeneruj tutaj](https://huggingface.co/settings/tokens)

> **Wspierane regiony:** `eu-central-1` ✅ `us-east-1` ✅ `us-east-2` ✅ `us-west-2` ✅  
> Bedrock Custom Model Import nie jest dostępny we wszystkich regionach.

---

## Monitorowanie importu

Po uruchomieniu `deploy.sh` skrypt wypisze gotowe komendy. Możesz też użyć:

```bash
# Logi CodeBuild na żywo
aws logs tail /aws/codebuild/LIAC-Bielik-Import --follow --region us-east-1

# Status modelu w Bedrock
aws bedrock list-imported-models \
  --region us-east-1 \
  --query 'modelSummaries[*].{Name:modelName,Status:modelStatus}' \
  --output table
```

---

## Testowanie modelu po imporcie

> **Ważne:** Custom Imported Models nie obsługują `converse` API. Należy używać `invoke_model` z formatem promptu zgodnym z Llama 3 Instruct.

```python
import boto3, json

bedrock   = boto3.client("bedrock",         region_name="us-east-1")
runtime   = boto3.client("bedrock-runtime", region_name="us-east-1")

# Pobierz ARN zaimportowanego modelu
models    = bedrock.list_imported_models()
model_arn = next(
    m["modelArn"] for m in models["modelSummaries"]
    if "Bielik" in m["modelName"]
)
print("Model ARN:", model_arn)

# Format promptu Llama 3 Instruct
prompt = """<|begin_of_text|><|start_header_id|>user<|end_header_id|>
Wyjaśnij mi w 3 zdaniach, czym jest Amazon Bedrock.<|eot_id|>
<|start_header_id|>assistant<|end_header_id|>
"""

response = runtime.invoke_model(
    modelId=model_arn,
    contentType="application/json",
    accept="application/json",
    body=json.dumps({
        "prompt": prompt,
        "max_gen_len": 512,
        "temperature": 0.7,
        "top_p": 0.9,
    })
)

result = json.loads(response["body"].read())
print(result["generation"])
```

**Funkcja pomocnicza do wielokrotnego użycia:**

```python
import boto3, json

def zapytaj_bielika(pytanie: str, max_tokenow: int = 512) -> str:
    bedrock = boto3.client("bedrock",         region_name="us-east-1")
    runtime = boto3.client("bedrock-runtime", region_name="us-east-1")

    models    = bedrock.list_imported_models()
    model_arn = next(
        m["modelArn"] for m in models["modelSummaries"]
        if "Bielik" in m["modelName"]
    )

    prompt = (
        "<|begin_of_text|>"
        "<|start_header_id|>user<|end_header_id|>\n"
        f"{pytanie}<|eot_id|>\n"
        "<|start_header_id|>assistant<|end_header_id|>\n"
    )

    resp = runtime.invoke_model(
        modelId=model_arn,
        contentType="application/json",
        accept="application/json",
        body=json.dumps({
            "prompt": prompt,
            "max_gen_len": max_tokenow,
            "temperature": 0.7,
            "top_p": 0.9,
        })
    )
    return json.loads(resp["body"].read())["generation"]


# Użycie
print(zapytaj_bielika("Czym jest Amazon S3? Odpowiedz krótko."))
```

**Szybki test czy model rozumie po polsku** — zadaj pytanie wymagające wiedzy historycznej:

```python
odpowiedz = zapytaj_bielika(
    "Podaj dotychczasowe miasta, będące stolicą Polski."
)
print(odpowiedz)
```

Poprawna odpowiedź powinna wymienić: **Gniezno** (pierwsza historyczna stolica), **Kraków** (od ok. X w. do 1596 r.) i **Warszawa** (od 1596 r. do dziś). Jeśli model odpowiada płynnie po polsku i zna historię — działa poprawnie. ✅


---

## 🗑️ Cleanup — usuwanie zasobów

Otwórz **[AWS CloudShell](https://console.aws.amazon.com/cloudshell)** i wklej:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/donkoyote/bielik-bedrock-import/main/cleanup.sh)
```

Skrypt pyta o potwierdzenie i usuwa kolejno:

1. **S3 bucket** — pliki modelu (~22 GB)
2. **CloudWatch Logs** — log group z buildów CodeBuild
3. **Stack CloudFormation** — CodeBuild Project, IAM Roles, SSM Parameter
4. **Model w Bedrock** *(opcjonalnie, pyta osobno)*

Po cleanup nie pozostają żadne zasoby generujące koszty.

---

## Struktura repozytorium

```
bielik-bedrock-import/
├── deploy.sh                          # ← główny skrypt (1 komenda w CloudShell)
├── cleanup.sh                         # usuwanie zasobów
├── cloudformation/
│   └── bielik-bedrock-import.yaml    # infrastruktura + buildspec inline
└── README.md
```

---

## Parametry CFN (opcjonalne nadpisanie)

Skrypt `deploy.sh` używa domyślnych wartości. Jeśli chcesz dostosować, możesz ręcznie wywołać CFN:

```bash
aws cloudformation deploy \
  --template-file cloudformation/bielik-bedrock-import.yaml \
  --stack-name bielik-bedrock-import \
  --region us-east-1 \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    HuggingFaceToken="hf_TWOJ_TOKEN" \
    BedrockModelName="Bielik-11B-v3-Instruct" \
    S3Prefix="bielik-11b-v3" \
    ModelId="speakleash/Bielik-11B-v3.0-Instruct"
```

---

## Koszty infrastruktury — eu-central-1

> Wszystkie ceny w USD dla regionu **EU (Frankfurt) eu-central-1**, stan na luty 2026.  
> Weryfikuj aktualne stawki: [aws.amazon.com/bedrock/pricing](https://aws.amazon.com/bedrock/pricing/) · [aws.amazon.com/codebuild/pricing](https://aws.amazon.com/codebuild/pricing/)

### 💸 Jednorazowy koszt wdrożenia

| Usługa | Zasób | Stawka eu-central-1 | Zużycie | Koszt |
|--------|-------|---------------------|---------|-------|
| **CloudFormation** | Stack deploy | $0 | — | **$0.00** |
| **IAM** | Role, Policy | $0 | — | **$0.00** |
| **SSM Parameter Store** | 1 Standard Parameter | $0 | — | **$0.00** |
| **CodeBuild** | `BUILD_GENERAL1_LARGE` (Linux) | $0.020/min | ~45 min | **~$0.90** |
| **S3** | Upload 22 GB z CodeBuild → S3 | $0 (intra-region transfer) | 22 GB | **$0.00** |
| **S3 PUT requests** | ~10 000 requestów | $0.0055/1000 | 10k | **~$0.06** |
| **CloudWatch Logs** | Logi buildu ~50 MB | Free tier: 5 GB/mies | <1 GB | **$0.00** |
| **Bedrock** | Import modelu (jednorazowy job) | $0 (import jest bezpłatny) | — | **$0.00** |
| | | | **RAZEM** | **~$0.96** |

> **Uwaga dot. CodeBuild:** AWS nie publikuje osobnych tabel cen per-region dla CodeBuild — stosuje jedną globalną stawkę. Stawka `general1.large` to **$0.020/min** (Linux). Potwierdź aktualną wartość w [AWS Pricing Calculator](https://calculator.aws/).

---

### 📦 Miesięczny koszt utrzymania (storage)

| Usługa | Zasób | Stawka eu-central-1 | Ilość | Koszt/mies |
|--------|-------|---------------------|-------|------------|
| **S3 Standard** | Pliki modelu | $0.0245/GB | 22 GB | **~$0.54** |
| **SSM Parameter Store** | Standard Parameter (HF token) | $0 | 1 | **$0.00** |
| **CloudWatch Logs** | Retencja logów buildu | $0.03/GB | ~0.05 GB | **~$0.00** |
| **CodeBuild Project** | Sam projekt (bez buildów) | $0 | — | **$0.00** |
| | | | **RAZEM** | **~$0.54/mies** |

> 💡 Jeśli model jest już zaimportowany i bucket S3 nie jest potrzebny, możesz go usunąć poleceniem `./cleanup.sh`. Oszczędza ~$0.54/mies, ale utracisz możliwość re-importu bez ponownego downloadu.

---

### 🤖 Koszt inference (używanie modelu)

Custom Model Import w Bedrock rozlicza się inaczej niż foundation models — nie płacisz za tokeny, lecz za **czas aktywności kopii modelu** w oknach 5-minutowych.

| Składnik | Szczegóły |
|----------|-----------|
| **Import modelu** | **$0** — bezpłatny |
| **Model storage w Bedrock** | **$0** — pliki zostają w Twoim S3, Bedrock nie kopiuje |
| **Inference billing** | CMU (Custom Model Unit) × czas × stawka/CMU/min |
| **Okno rozliczeniowe** | 5 minut od pierwszego wywołania |
| **Bielik 11B ≈ CMU** | ~2–3 CMU (zależy od wersji hardware przydzielonej przez Bedrock) |
| **Stawka CMU** | Sprawdź na stronie Bedrock → Custom Model Import → Twój model → `GetImportedModel` |

**Przykładowe wyliczenie** (orientacyjne, dla CMU v1 w eu-central-1):

```
1 zapytanie testowe (~5 min aktywności):
  2 CMU × $0.0021/CMU/min × 5 min = ~$0.02

100 zapytań dziennie (model aktywny ~2h):
  2 CMU × $0.0021/CMU/min × 120 min = ~$0.50/dzień = ~$15/mies
```

> **Jak sprawdzić dokładną stawkę CMU dla Twojego modelu:**
> ```bash
> aws bedrock get-imported-model \
>   --model-identifier "arn:aws:bedrock:eu-central-1:ACCOUNT:imported-model/MODEL_ID" \
>   --region eu-central-1 \
>   --query '{CMU: customModelUnitsPerModelCopy, Version: customModelUnitsVersion}'
> ```
> Następnie sprawdź stawkę dla tej wersji na [stronie cennika Bedrock](https://aws.amazon.com/bedrock/pricing/) → sekcja "Custom Model Import".

---

### 📊 Podsumowanie

| Scenariusz | Koszt |
|------------|-------|
| **Jednorazowy deploy** | ~$0.96 |
| **S3 storage/mies (jeśli zachowujesz bucket)** | ~$0.54 |
| **Test (kilka zapytań)** | ~$0.02–$0.10 |
| **Produkcja light (100 req/dzień)** | ~$15–$20/mies |
| **Cleanup (usuń bucket po imporcie)** | $0 ongoing |

---

## FAQ

### 🔴 Błąd: `GatedRepoError: 403 Forbidden` podczas pobierania modelu

To najczęstszy problem przy pierwszym uruchomieniu. Model Bielik jest **gated** — HuggingFace wymaga jednorazowej akceptacji warunków zanim token zadziała.

**Rozwiązanie:**
1. Wejdź na [https://huggingface.co/speakleash/Bielik-11B-v3.0-Instruct](https://huggingface.co/speakleash/Bielik-11B-v3.0-Instruct)
2. Kliknij **"Agree and access repository"** (przycisk pojawia się po zalogowaniu)
3. Zaktualizuj token w SSM jeśli build już się wywalił:
```bash
aws ssm put-parameter \
  --name "/bielik-bedrock/hf-token" \
  --value "hf_TWOJ_TOKEN" \
  --type String \
  --overwrite \
  --region us-east-1
```
4. Odpal build ponownie:
```bash
aws codebuild start-build --project-name LIAC-Bielik-Import --region us-east-1
```

> **Uwaga:** Samo posiadanie tokenu HuggingFace nie wystarczy. Akceptacja warunków i token to dwie niezależne rzeczy.

---

### ❓ Dlaczego CloudShell a nie lokalny terminal?

Zero konfiguracji. Nie musisz instalować AWS CLI, Pythona ani żadnych zależności. CloudShell ma je wszystkie wbudowane i już wie o Twoim koncie AWS.

### ❓ Czy moje dane są bezpieczne?

Token HuggingFace jest przechowywany w AWS SSM Parameter Store, nie w zmiennych środowiskowych ani logach. CodeBuild pobiera go dynamicznie tylko na czas wykonania.

### ❓ Ile miejsca zajmuje model w S3?

~22 GB (5 plików safetensors). Koszt S3 to ~$0.50/miesiąc.

### ❓ Jak długo trwa cały proces?

Zwykle 35–55 minut: ~20 min download z HuggingFace, ~10 min sync do S3, ~15 min import w Bedrock.

### 🔴 Błąd: `ValidationException: This action doesn't support the model`

Próbujesz wywołać model przez `converse` API — to API **nie obsługuje Custom Imported Models**. Dotyczy tylko modeli natywnie dostępnych w Bedrock (Anthropic, Meta, Mistral itp.).

**Rozwiązanie — użyj `invoke_model` zamiast `converse`:**

```python
# ❌ NIE DZIAŁA dla custom imported models
client.converse(modelId=model_arn, messages=[...])

# ✅ DZIAŁA
runtime.invoke_model(
    modelId=model_arn,
    contentType="application/json",
    accept="application/json",
    body=json.dumps({
        "prompt": "<|begin_of_text|><|start_header_id|>user<|end_header_id|>\nTwoje pytanie<|eot_id|>\n<|start_header_id|>assistant<|end_header_id|>\n",
        "max_gen_len": 512,
        "temperature": 0.7,
    })
)
```

Pełny przykład z funkcją pomocniczą znajdziesz w sekcji [Testowanie modelu po imporcie](#testowanie-modelu-po-imporcie).

---

### 🔴 Błąd: `could not find the expected file config.json` w Bedrock

Bedrock dostał S3 URI ale nie znalazł kompletnego modelu. Najczęstsza przyczyna: poprzedni build wywalił się w trakcie downloadu (np. błąd 403) i wgrał do S3 tylko kilka małych plików — bez wag modelu (`.safetensors`).

**Sprawdź co jest w S3:**
```bash
aws s3 ls s3://TWOJ-BUCKET/bielik-11b-v3/ --recursive --human-readable
```
Powinno być 5 plików `.safetensors` łącznie ~22 GB. Jeśli ich nie ma — prefix jest niekompletny.

**Rozwiązanie — wyczyść i odpal od nowa:**
```bash
# Wyczyść niekompletny prefix
aws s3 rm s3://TWOJ-BUCKET/bielik-11b-v3/ --recursive

# Odpal nowy build (pobierze i wgra od zera)
aws codebuild start-build --project-name LIAC-Bielik-Import --region us-east-1
```

> Skrypt od wersji z tym fix-em automatycznie sprawdza liczbę plików `.safetensors` przed wywołaniem Bedrocka i failuje wcześniej z czytelnym komunikatem.

---

### ❓ Build się wysypał — jak sprawdzić co poszło nie tak?

```bash
# Logi na żywo
aws logs tail /aws/codebuild/LIAC-Bielik-Import --follow --region us-east-1

# Ostatni build i jego status
aws codebuild list-builds-for-project \
  --project-name LIAC-Bielik-Import \
  --region us-east-1 \
  --query 'ids[0]' --output text | \
  xargs -I{} aws codebuild batch-get-builds --ids {} \
  --query 'builds[0].{Status:buildStatus,Phase:currentPhase,Reason:phases[-1].contexts[-1].message}' \
  --output table --region us-east-1
```

Najczęstsze przyczyny błędów:

| Błąd | Przyczyna | Rozwiązanie |
|------|-----------|-------------|
| `GatedRepoError: 403` | Brak akceptacji warunków modelu | Kliknij "Agree" na stronie HuggingFace |
| `could not find config.json` | Niekompletny upload do S3 (brak `.safetensors`) | Wyczyść prefix S3 i odpal build od nowa |
| `ValidationException: doesn't support the model` | Użycie `converse` zamiast `invoke_model` | Zamień API — custom models wymagają `invoke_model` |
| `YAML_FILE_ERROR` | Problem z buildspec | Zaktualizuj deploy.sh z repo |
| `Bedrock import Failed` | Złe pliki modelu lub brak uprawnień IAM | Sprawdź logi Bedrock i IAM Role |
| `No space left on device` | Za mało miejsca na dysku | Zmień `ComputeType` na `BUILD_GENERAL1_2XLARGE` |

### ❓ Czy mogę uruchomić import jeszcze raz bez re-deployu CFN?

Tak. Stack CFN tworzy infrastrukturę raz. Build możesz odpalać wielokrotnie:
```bash
aws codebuild start-build --project-name LIAC-Bielik-Import --region us-east-1
```

### ❓ W jakich regionach działa Bedrock Custom Model Import?

Aktualnie: `eu-central-1`, `us-east-1`, `us-east-2`, `us-west-2`. Pełna lista w [dokumentacji AWS](https://docs.aws.amazon.com/bedrock/latest/userguide/custom-model-supported.html).

---

## O projekcie Bielik

[Bielik](https://speakleash.org) to polski model językowy tworzony przez społeczność [SpeakLeash](https://speakleash.org). Licencja Apache 2.0 — możesz używać komercyjnie.

---

*Materiał przygotowany przez [poznajaws.pl](https://poznajaws.pl)*  
*Znalazłeś błąd? Otwórz [issue](https://github.com/donkoyote/bielik-bedrock-import/issues) lub PR!*
