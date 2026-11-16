# NOTE: create-github-appが登録したplan用・apply用のGitHub AppのClient IDと秘密鍵をTerraformの管理に移す
import {
  to = github_actions_environment_variable.terraform_plan_app_client_id
  id = "home-iac:terraform-plan:PLAN_APP_CLIENT_ID"
}

import {
  to = github_actions_environment_secret.terraform_plan_app_private_key
  id = "home-iac:terraform-plan:PLAN_APP_PRIVATE_KEY"
}

import {
  to = github_actions_environment_variable.terraform_apply_app_client_id
  id = "home-iac:terraform-apply:APPLY_APP_CLIENT_ID"
}

import {
  to = github_actions_environment_secret.terraform_apply_app_private_key
  id = "home-iac:terraform-apply:APPLY_APP_PRIVATE_KEY"
}
