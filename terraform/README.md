# Terraform — aws-lambda-with-spring

Provisions AWS infrastructure for Spring-based Lambda functions behind an HTTP API Gateway with a custom domain.

---

## DNS Scenarios

Choose the scenario that matches how your domain is set up.

---

### Scenario 1 — Registrar: GoDaddy, DNS: GoDaddy

GoDaddy owns and manages the domain entirely. You delegate just the `api` subdomain to Route53 so Terraform can manage everything from there.

```
GoDaddy (your-task.dev)
  └── api   NS → Route53 nameservers        ← one record, added manually in GoDaddy

Route53 (api.your-task.dev)                 ← Terraform manages this
  ├── _c4xxx.api.your-task.dev  CNAME → ACM validation
  └── api.your-task.dev         A     → API Gateway (ALIAS)
```

**Terraform file:** `main-with-route53.tf.example` → rename to `main.tf`

**Steps:**
1. `terraform apply` → copy the 4 NS values from the `route53_name_servers` output
2. GoDaddy → **DNS** → **Add Record**:
   ```
   Type:  NS
   Name:  api
   Value: ns-111.awsdns-11.com.    ← add all 4, one per record
   TTL:   3600
   ```
3. Propagates in 5–30 minutes — Terraform handles everything else

---

### Scenario 2 — Registrar: GoDaddy, DNS: Azure DNS

GoDaddy is the registrar but nameservers point to Azure DNS. Azure DNS is the authoritative host for `your-task.dev`. Terraform uses the `azurerm` provider to write records directly into Azure DNS.

```
GoDaddy (registrar only — nameservers point to Azure)

Azure DNS (your-task.dev)                   ← Terraform manages these records
  ├── _c4xxx.api  CNAME → ACM validation
  └── api         CNAME → API Gateway custom domain
```

**Terraform file:** `main.tf` (current)

**Steps:**
1. Export Azure credentials:
   ```bash
   export ARM_TENANT_ID="<tenant-id>"
   export ARM_CLIENT_ID="<sp-client-id>"
   export ARM_CLIENT_SECRET="<sp-secret>"
   export ARM_SUBSCRIPTION_ID="<sub-id>"
   ```
2. `terraform init && terraform apply`
3. No manual DNS steps — Terraform writes all records into Azure DNS automatically

**Requirement:** Service principal needs **DNS Zone Contributor** role on the Azure DNS zone.

---

### Scenario 3 — Registrar: GoDaddy, DNS: Azure DNS, subdomain zone in Route53

GoDaddy is the registrar, Azure DNS manages `your-task.dev`, but you want Route53 to manage `api.your-task.dev`. Azure DNS delegates the subdomain to Route53 via an NS record.

```
GoDaddy (registrar only — nameservers point to Azure)

Azure DNS (your-task.dev)
  └── api   NS → Route53 nameservers        ← one record, added manually in Azure

Route53 (api.your-task.dev)                 ← Terraform manages this
  ├── _c4xxx.api.your-task.dev  CNAME → ACM validation
  └── api.your-task.dev         A     → API Gateway (ALIAS)
```

**Terraform file:** `main-with-route53.tf.example` → rename to `main.tf`

**Steps:**
1. `terraform apply` → copy the 4 NS values from the `route53_name_servers` output
2. Add NS delegation record in Azure DNS:

   **Azure portal:** DNS zones → your-task.dev → + Record set
   ```
   Name:  api
   Type:  NS
   TTL:   3600
   Values: ns-111.awsdns-11.com.
           ns-222.awsdns-22.net.
           ns-333.awsdns-33.org.
           ns-444.awsdns-44.co.uk.
   ```

   **Or via `az` CLI:**
   ```bash
   az network dns record-set ns create \
     --resource-group DefaultResourceGroup-WEU \
     --zone-name your-task.dev \
     --name api --ttl 3600

   # repeat for each of the 4 nameservers
   az network dns record-set ns add-record \
     --resource-group DefaultResourceGroup-WEU \
     --zone-name your-task.dev \
     --record-set-name api \
     --nsdname ns-111.awsdns-11.com.
   ```

3. Propagates in 5–30 minutes — all `*.api.your-task.dev` queries route to Route53

---

### Scenario comparison

| | Scenario 1 | Scenario 2 | Scenario 3 |
|---|---|---|---|
| Registrar | GoDaddy | GoDaddy | GoDaddy |
| DNS host | GoDaddy | Azure DNS | Azure DNS + Route53 |
| Terraform file | `main-with-route53.tf.example` | `main.tf` | `main-with-route53.tf.example` |
| AWS providers needed | `aws` only | `aws` + `azurerm` | `aws` only |
| Manual DNS step | Add NS in GoDaddy | None | Add NS in Azure DNS |
| Propagation | 5–30 min | Instant | 5–30 min |

---

## Resources created

| Module / Resource | What it creates |
|---|---|
| `module.ecr` | ECR repository per image; pulls from GHCR and pushes to ECR |
| `module.s3` | S3 buckets (none by default) |
| `module.lambda` | Lambda function (container image), IAM role, CloudWatch log group |
| `module.acm` | ACM certificate (DNS validation) |
| `azurerm_dns_cname_record.acm_validation` | ACM validation CNAME in Azure DNS *(Scenario 2)* |
| `azurerm_dns_cname_record.api` | `api.your-task.dev` CNAME in Azure DNS *(Scenario 2)* |
| `aws_route53_zone.api` | Route53 hosted zone for `api.your-task.dev` *(Scenarios 1 & 3)* |
| `aws_route53_record.acm_validation` | ACM validation CNAME in Route53 *(Scenarios 1 & 3)* |
| `aws_route53_record.api` | `api.your-task.dev` ALIAS in Route53 *(Scenarios 1 & 3)* |
| `aws_acm_certificate_validation` | Blocks until ACM confirms certificate is issued |
| `module.api_gateway_route` | HTTP API Gateway, routes, Lambda integrations, custom domain |

---

## Apply execution order

### Scenarios 1 & 3 (Route53)

```
1. module.ecr                        create ECR repo, pull from GHCR, push image
2. module.s3                         create S3 buckets (parallel with ecr)
3. module.lambda                     create Lambda functions (waits for ecr)
4. module.acm                        create ACM certificate
5. aws_route53_zone.api              create Route53 hosted zone for api.your-task.dev
6. aws_route53_record.acm_validation write validation CNAME into Route53
7. aws_acm_certificate_validation    poll until certificate = ISSUED
8. module.api_gateway_route          create API Gateway + custom domain
9. aws_route53_record.api            point api.your-task.dev → API Gateway (ALIAS)
```

### Scenario 2 (Azure DNS)

```
1. module.ecr                               create ECR repo, pull from GHCR, push image
2. module.s3                                create S3 buckets (parallel with ecr)
3. module.lambda                            create Lambda functions (waits for ecr)
4. module.acm                               create ACM certificate
5. azurerm_dns_cname_record.acm_validation  write validation CNAME into Azure DNS
6. aws_acm_certificate_validation           poll until certificate = ISSUED
7. module.api_gateway_route                 create API Gateway + custom domain
8. azurerm_dns_cname_record.api             point api.your-task.dev → API Gateway
```

---

## Prerequisites

| Tool | Purpose |
|---|---|
| `terraform >= 1.14` | Infrastructure provisioning |
| `docker` | Pull image from GHCR, push to ECR |
| `aws` CLI | ECR login during `docker push` |

---

## Variables

### App config (all scenarios)

Configured in `locals` inside `main.tf`.

| Local | Default | Description |
|---|---|---|
| `domain.name` | `api.your-task.dev` | Custom domain. Set to `""` to skip ACM and custom domain entirely. |

### Scenario 2 only — Azure DNS

| Variable | Default | Description |
|---|---|---|
| `azure_resource_group` | `DefaultResourceGroup-WEU` | Resource group containing the DNS zone |
| `azure_dns_zone` | `your-task.dev` | Azure DNS zone name |

Azure auth via environment variables (never stored in state):

| Env var | Description |
|---|---|
| `ARM_TENANT_ID` | Azure AD tenant ID |
| `ARM_CLIENT_ID` | Service principal client ID |
| `ARM_CLIENT_SECRET` | Service principal client secret |
| `ARM_SUBSCRIPTION_ID` | Azure subscription ID |

---

## Outputs

| Output | Description |
|---|---|
| `ecr_repository_urls` | Map of ECR repository URLs |
| `s3_bucket_names` | Map of S3 bucket names |
| `lambda_function_names` | Map of Lambda function names |
| `function_urls` | Lambda function URLs (only for `enable_function_url = true`) |
| `api_gateway_endpoint` | Default API Gateway invoke URL |
| `route53_name_servers` | 4 NS values to add in GoDaddy or Azure DNS *(Scenarios 1 & 3 only)* |

---

## Adding a new Lambda function

Add an entry to the `functions` map in `main.tf`:

```hcl
"my-new-function" = {
  memory_size           = 512
  environment_variables = { MY_VAR = "value" }
  enable_function_url   = false
  api_gateway_route = {
    path_prefix   = "my-path"
    path_rewrites = { "my-path" = "/internal-path" }
  }
}
```

All functions share the same ECR image. `path_rewrites` rewrites the incoming path prefix before forwarding to Lambda.

---

## Skipping the custom domain

Set `name = ""` in the `domain` local. ACM, DNS records, and the API Gateway custom domain are all skipped.

```hcl
domain = {
  name = ""
}
```

---

## State

| Setting | Value |
|---|---|
| Bucket | `tfpocbucket001` |
| Key | `aws-lambda-with-spring/terraform.tfstate` |
| Region | `eu-north-1` |
| Encryption | enabled |
