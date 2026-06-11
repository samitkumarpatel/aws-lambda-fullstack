# Infrastructure — Terraform

Production AWS infrastructure for frontend microfrontends, API (Lambda + API Gateway), ECR, ACM, and Route 53. Organised into reusable modules and independently deployable stacks.

---

## Folder structure

```
infrastructure/
├── modules/                  # Reusable building blocks — never deployed directly
│   ├── frontend/             # S3 + CloudFront distribution
│   ├── lambda/               # Lambda function + IAM role
│   ├── ecr/                  # ECR repository
│   ├── api-gateway/          # HTTP API Gateway + custom domain
│   └── acm/                  # ACM certificate + Route 53 DNS validation
│
├── stacks/                   # Deployable units — each has its own state
│   ├── dns/                  # Route 53 hosted zone (deploy once)
│   ├── certificates/         # ACM certificates (deploy once)
│   ├── api/                  # API Gateway + all Lambdas + ECR repos
│   └── frontends/
│       ├── todo/             # S3 + CloudFront for todo app
│       └── album/            # S3 + CloudFront for album app
│
└── envs/
    ├── prod/
    │   ├── terraform.tfvars
    │   └── backend.hcl
    └── staging/
        ├── terraform.tfvars
        └── backend.hcl
```

---

## Stack lifecycles

| Stack | Changes | Why isolated |
|---|---|---|
| `dns` | Once | Destroying the hosted zone is catastrophic |
| `certificates` | Once | ACM cert loss breaks all HTTPS |
| `api` | Per backend feature | Lambda + ECR + API Gateway change together |
| `frontends/*` | Per app, independently | Each app has its own state — destroy one without touching others |

---

## Environment files

Each environment folder carries two files.

**`backend.hcl`** — backend config passed at `init` time (varies per env and per stack):

```hcl
bucket         = "your-tf-state-prod"
key            = "frontends/todo/terraform.tfstate"
region         = "eu-west-1"
dynamodb_table = "tf-state-lock-prod"
```

**`terraform.tfvars`** — input variable values passed at `plan` time:

```hcl
environment = "prod"
domain      = "todo.your-task.dev"
aws_region  = "eu-west-1"
cert_arn    = "arn:aws:acm:us-east-1:123456789:certificate/abc"
```

> The `key` in `backend.hcl` changes per stack. Each stack gets its own state file:
> `dns/terraform.tfstate`, `certificates/terraform.tfstate`, `api/terraform.tfstate`, `frontends/todo/terraform.tfstate`, etc.

---

## Deploying a stack

Replace `<stack>` with the stack path (e.g. `frontends/todo`, `api`, `dns`) and `<env>` with `prod` or `staging`.

```bash
# 1. Initialise with the environment backend
terraform -chdir=stacks/<stack> \
  init -backend-config=../../envs/<env>/backend.hcl

# 2. Plan and save the output
terraform -chdir=stacks/<stack> \
  plan -var-file=../../envs/<env>/terraform.tfvars -out=tfplan

# 3. Apply the saved plan
terraform -chdir=stacks/<stack> \
  apply tfplan
```

### Examples

```bash
# Deploy the todo frontend to prod
terraform -chdir=stacks/frontends/todo \
  init -backend-config=../../envs/prod/backend.hcl

terraform -chdir=stacks/frontends/todo \
  plan -var-file=../../envs/prod/terraform.tfvars -out=tfplan

terraform -chdir=stacks/frontends/todo \
  apply tfplan

# Deploy the API stack to staging
terraform -chdir=stacks/api \
  init -backend-config=../../envs/staging/backend.hcl

terraform -chdir=stacks/api \
  plan -var-file=../../envs/staging/terraform.tfvars -out=tfplan

terraform -chdir=stacks/api \
  apply tfplan
```

---

## Makefile shortcuts

A `Makefile` at the repo root wraps the three-step flow. Pass `STACK` and `ENV` as arguments.

```makefile
STACK ?= frontends/todo
ENV   ?= prod

init:
	terraform -chdir=stacks/$(STACK) init \
	  -backend-config=../../envs/$(ENV)/backend.hcl

plan:
	terraform -chdir=stacks/$(STACK) plan \
	  -var-file=../../envs/$(ENV)/terraform.tfvars \
	  -out=tfplan

apply:
	terraform -chdir=stacks/$(STACK) apply tfplan

destroy:
	terraform -chdir=stacks/$(STACK) destroy \
	  -var-file=../../envs/$(ENV)/terraform.tfvars
```

Usage:

```bash
make init  STACK=frontends/todo  ENV=prod
make plan  STACK=frontends/todo  ENV=prod
make apply STACK=frontends/todo  ENV=prod

make plan  STACK=api             ENV=staging
make plan  STACK=dns             ENV=prod
```

---

## Adding a new frontend app

1. Copy an existing frontend stack folder:
   ```bash
   cp -r stacks/frontends/todo stacks/frontends/shop
   ```
2. Update `stacks/frontends/shop/variables.tf` with the new app's variables.
3. Update `envs/prod/backend.hcl` key to `frontends/shop/terraform.tfstate` when deploying.
4. Add a DNS record for `shop.your-task.dev` — either manually in Route 53 or as an output consumed by the `dns` stack.
5. Deploy:
   ```bash
   make init  STACK=frontends/shop ENV=prod
   make plan  STACK=frontends/shop ENV=prod
   make apply STACK=frontends/shop ENV=prod
   ```

---

## Adding a new Lambda function

All Lambda functions live in the `api` stack. Open `stacks/api/lambdas.tf` and add a new module block:

```hcl
module "shop_fn" {
  source = "../../modules/lambda"

  name      = "shop"
  image_uri = "${module.shop_ecr.repository_url}:latest"
  # ...other variables
}
```

Add the corresponding ECR repo in the same file, then redeploy the `api` stack:

```bash
make plan  STACK=api ENV=prod
make apply STACK=api ENV=prod
```

---

## State backend setup

Before using any stack, the S3 bucket and DynamoDB table for state locking must exist. Bootstrap them once manually or with a separate Terraform workspace not tracked here.

| Resource | Purpose |
|---|---|
| S3 bucket | Stores `.tfstate` files, one key per stack |
| DynamoDB table | State locking — prevents concurrent applies |

Recommended S3 bucket settings: versioning enabled, server-side encryption, public access blocked.
