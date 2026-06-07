# HTTP API Gateway Configuration

This project uses a single **AWS HTTP API Gateway** (`aws_apigatewayv2_api`) to front three Lambda functions, each handling a distinct path prefix.

## Route Mapping

| Route Key | Lambda | Path Handled |
|---|---|---|
| `ANY /api/{proxy+}` | `aws-lambda-with-spring` | All `/api/*` requests not matched below |
| `ANY /product/{proxy+}` | `aws-lambda-with-spring-product` | All `/product/*` requests |
| `ANY /planning/{proxy+}` | `aws-lambda-with-spring-planning` | All `/planning/*` requests |

> `{proxy+}` is a greedy path parameter — it matches one or more path segments after the prefix.

## How Route Specificity Works

API Gateway resolves routes by **most-specific match**, not declaration order. A request to `/product/123` matches `ANY /product/{proxy+}` before `ANY /api/{proxy+}`, even though `/api/{proxy+}` was declared first.

## Terraform Structure

### `terraform/main.tf` — Route wiring

Routes are generated dynamically from the `functions` local map using `api_gateway_path_prefix`:

```hcl
module "api_gateway" {
  source = "./modules/api-gateway"
  name   = "aws-lambda-api"

  integrations = {
    for k, v in local.http_functions :
    "ANY /${v.api_gateway_path_prefix}/{proxy+}" => {
      lambda_function_arn  = module.lambda[k].function_arn
      lambda_function_name = module.lambda[k].function_name
    }
  }
}
```

To add a new Lambda behind the gateway, add an entry to `locals.functions` in `main.tf` with `api_type = "http"` and a unique `api_gateway_path_prefix`.

### `terraform/modules/api-gateway/` — Reusable module

| Resource | Purpose |
|---|---|
| `aws_apigatewayv2_api` | Creates the HTTP API with CORS settings |
| `aws_apigatewayv2_integration` | One `AWS_PROXY` integration per route, pointing to the Lambda ARN |
| `aws_apigatewayv2_route` | Binds each route key (e.g. `ANY /product/{proxy+}`) to its integration |
| `aws_apigatewayv2_stage` | `$default` stage with `auto_deploy = true` and CloudWatch access logging |
| `aws_lambda_permission` | Grants `apigateway.amazonaws.com` invoke rights on each Lambda |
| `aws_cloudwatch_log_group` | Stores access logs under `/aws/apigateway/<name>`, retained 5 days |

### Module inputs (`variables.tf`)

| Variable | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | — | API Gateway name |
| `stage_name` | `string` | `$default` | Stage name |
| `integrations` | `map(object)` | — | Map of `"METHOD /path"` → Lambda ARN + name |
| `cors` | `object` | allow all | CORS policy applied at the API level |

### Module outputs (`outputs.tf`)

| Output | Description |
|---|---|
| `api_id` | The API Gateway ID |
| `api_endpoint` | The invoke URL (base URL for all routes) |
| `execution_arn` | Used to scope Lambda permissions |

## CORS Default Policy

The module ships with a permissive default suitable for development:

```hcl
allow_origins     = ["*"]
allow_methods     = ["*"]
allow_headers     = ["*"]
expose_headers    = []
max_age           = 86400
allow_credentials = false
```

Override the `cors` variable in `main.tf` when deploying to production.

## Adding a New Lambda Route

1. Add an entry to `locals.functions` in `terraform/main.tf`:

```hcl
"aws-lambda-with-spring-orders" = {
  api_type                = "http"
  api_gateway_path_prefix = "orders"
  memory_size             = 3008
  environment_variables   = {
    API_BASE_URI = "/orders"
  }
}
```

2. The `module "api_gateway"` block automatically picks it up — no changes to the module are needed.

The new route `ANY /orders/{proxy+}` will be created on the next `terraform apply`.

## Important: Exact Path vs Greedy Match

`{proxy+}` requires at least one segment after the prefix. A request to `/product` (no trailing path) will **not** match `ANY /product/{proxy+}`. If you need to handle exact prefix paths, add an explicit route:

```hcl
"ANY /product" => { ... }
```

## Path Rewriting (External Path ≠ Lambda Internal Path)

If a Lambda's internal routes use a different base path than what API Gateway exposes, use **parameter mapping** on the integration to rewrite the path before it reaches the Lambda.

**Example:** API Gateway exposes `ANY /min/{proxy+}` but the Lambda handles requests at `/api/min/*`.

Add `request_parameters` to the `aws_apigatewayv2_integration` resource in `modules/api-gateway/main.tf`:

```hcl
resource "aws_apigatewayv2_integration" "this" {
  # ... existing config ...
  request_parameters = {
    "overwrite:path" = "/api$request.path"
  }
}
```

`$request.path` resolves to the full incoming path (e.g. `/min/items/123`), so `/api$request.path` rewrites it to `/api/min/items/123`.

### Making it configurable per-integration

Extend the `integrations` variable in `modules/api-gateway/variables.tf` with an optional field:

```hcl
variable "integrations" {
  type = map(object({
    lambda_function_arn  = string
    lambda_function_name = string
    path_prefix_rewrite  = optional(string)  # e.g. "/api"
  }))
}
```

Update the integration resource to apply it conditionally:

```hcl
resource "aws_apigatewayv2_integration" "this" {
  for_each = var.integrations
  # ...
  request_parameters = each.value.path_prefix_rewrite != null ? {
    "overwrite:path" = "${each.value.path_prefix_rewrite}$request.path"
  } : {}
}
```

Pass `path_prefix_rewrite` only for lambdas that need it in `terraform/main.tf`:

```hcl
module "api_gateway" {
  source = "./modules/api-gateway"
  name   = "aws-lambda-api"

  integrations = {
    "ANY /min/{proxy+}" = {
      lambda_function_arn  = module.lambda["aws-lambda-with-spring-min"].function_arn
      lambda_function_name = module.lambda["aws-lambda-with-spring-min"].function_name
      path_prefix_rewrite  = "/api"   # rewrites /min/... → /api/min/...
    }
  }
}
```

Lambdas that omit `path_prefix_rewrite` (or set it to `null`) pass the path through unchanged.
