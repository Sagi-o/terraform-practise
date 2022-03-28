# terraform-practise
AWS Infrastructure using Terraform

# Commands
terraform init

terraform plan

terraform apply --auto-approve

terraform apply -target aws_instance.my_first_server

terraform apply -var-file terraform.tfvars

terraform apply -var "subnet_prefix=10.0.100/24"


terraform destroy

terraform destroy -target aws_instance.my_first_server


terraform state list

terraform state show aws_vpc.my_vpc

terraform output

terraform refresh
