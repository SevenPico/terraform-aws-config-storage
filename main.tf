
module "storage" {
  source  = "registry.terraform.io/cloudposse/s3-log-storage/aws"
  version = "0.28.0"
  count   = module.this.enabled ? 1 : 0

  acl                      = "private"
  force_destroy            = var.force_destroy
  force_destroy_enabled    = var.force_destroy
  lifecycle_rule_enabled   = false
  versioning_enabled       = true
  sse_algorithm            = var.sse_algorithm
  kms_master_key_arn       = var.kms_master_key_arn
  block_public_acls        = true
  block_public_policy      = true
  ignore_public_acls       = true
  restrict_public_buckets  = true
  access_log_bucket_prefix = var.access_log_bucket_prefix
  access_log_bucket_name   = var.access_log_bucket_name
  allow_ssl_requests_only  = var.allow_ssl_requests_only
  policy                   = join("", data.aws_iam_policy_document.aws_config_bucket_policy.*.json)

  bucket_notifications_enabled = var.bucket_notifications_enabled
  bucket_notifications_type    = var.bucket_notifications_type
  bucket_notifications_prefix  = var.bucket_notifications_prefix

  context = module.this.context
}

data "aws_iam_policy_document" "aws_config_bucket_policy" {
  count = module.this.enabled ? 1 : 0

  statement {
    sid = "AWSConfigBucketPermissionsCheck"

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    dynamic "principals" {
      for_each = var.child_accounts
      content {
        type = "AWS"
        identifiers = [each.value]
      }
    }

    effect  = "Allow"
    actions = ["s3:GetBucketAcl"]

    resources = [
      local.s3_bucket_arn
    ]
  }

  statement {
    sid = "AWSConfigBucketExistenceCheck"

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    dynamic "principals" {
      for_each = var.child_accounts
      content {
        type = "AWS"
        identifiers = [each.value]
      }
    }

    effect  = "Allow"
    actions = ["s3:ListBucket"]

    resources = [
      local.s3_bucket_arn
    ]
  }

  statement {
    sid = "AWSConfigBucketDelivery"

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    effect  = "Allow"
    actions = ["s3:PutObject"]

    condition {
      test     = "StringLike"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    resources = [local.s3_object_prefix]
  }


  dynamic "statement" {
    for_each = var.child_accounts
    content {
      sid = "AWSConfigBucketDelivery${each.value}"

      principals {
        type = "AWS"
        identifiers = [each.value]
      }

      effect  = "Allow"
      actions = ["s3:PutObject"]

      condition {
        test     = "StringLike"
        variable = "s3:x-amz-acl"
        values   = ["bucket-owner-full-control"]
      }

      resources = ["${local.s3_bucket_arn}/${each.key}/*"]
    }
  }

}

#-----------------------------------------------------------------------------------------------------------------------
# Locals and Data Sources
#-----------------------------------------------------------------------------------------------------------------------
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  current_account_id = data.aws_caller_identity.current.account_id
  config_spn         = "config.amazonaws.com"
  s3_bucket_arn      = format("arn:%s:s3:::%s", data.aws_partition.current.id, module.this.id)
  s3_object_prefix   = format("%s/AWSLogs/*", local.s3_bucket_arn)
}
