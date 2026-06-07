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
