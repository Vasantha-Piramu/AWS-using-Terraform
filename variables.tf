variable "region" {
    description = "specify region"
}

variable "vpc_cidr" {
    description = "cidr block for vpc"
    default = "10.0.0.0/16"
    type = any
}
variable "ami"{
    description = "input ami value"
}

variable "instance_type" {
    description = "value for instance_type"
}

