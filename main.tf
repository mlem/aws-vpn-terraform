provider "aws" {
  region = "eu-central-1"
  profile = "${var.aws_profile}"
}

data "template_file" "aws_region" {
  template = "$${region}"

  vars {
    #Change the number 13 to number specific to your region from variables.tf file.
    region = "eu-central-1"
  }
}

#================ Print AWS region selected ================
output "aws_region" {
  value = "${data.template_file.aws_region.rendered}"
}

#================ VPC ================
resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = "true"

  tags {
    Name = "vpn-vpc"
    env = "vpn"
  }
}

#================ IGW ================
resource "aws_internet_gateway" "igw" {
  vpc_id = "${aws_vpc.vpc.id}"

  tags {
    Name = "vpn-vpc-igw"
    env = "vpn"
  }
}

#================ Public Subnet ================
resource "aws_subnet" "pub_subnet" {
  vpc_id = "${aws_vpc.vpc.id}"
  availability_zone = "${data.template_file.aws_region.rendered}a"
  cidr_block = "10.0.1.0/24"
  map_public_ip_on_launch = "true"

  tags {
    Name = "vpn-pub-subnet"
    env = "vpn"
  }
}

#================ Route Table ================
resource "aws_route_table" "pub_rtb" {
  vpc_id = "${aws_vpc.vpc.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.igw.id}"
  }

  tags {
    Name = "pub-rtb"
    env = "vpn"
  }
}

#================ Route Table Association ================
resource "aws_route_table_association" "pub_rtb_assoc" {
  subnet_id = "${aws_subnet.pub_subnet.id}"
  route_table_id = "${aws_route_table.pub_rtb.id}"
}

#================ Security Groups ================
resource "aws_security_group" "vpn_sg" {
  name = "vpn-sg"
  description = "OpenVPN Security Group"
  vpc_id = "${aws_vpc.vpc.id}"

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"] #Restrict to you own IP
  }
  ingress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 943
    to_port = 943
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 1194
    to_port = 1194
    protocol = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "vpn-sg"
    env = "vpn"
  }
}

#================ VPN Spot Instance Role/Profile ================
data "aws_iam_policy_document" "instance_assume_role_policy_for_ec2" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "spot_instance_role" {
  assume_role_policy = "${data.aws_iam_policy_document.instance_assume_role_policy_for_ec2.json}"
  name = "SpotInstanceRoleFor_OpenVPN"
}

resource "aws_iam_instance_profile" "spot_instance_profile" {
  name = "spot_instance_profile_for_openvpn"
  role = "${aws_iam_role.spot_instance_role.name}"
}

#================ VPN Instance ================
resource "aws_spot_instance_request" "instance_request" {
  count = 1
  spot_price = "0.005"
  iam_instance_profile = "${aws_iam_instance_profile.spot_instance_profile.name}"
  wait_for_fulfillment = true

  ami = "ami-00a75511aff95fb1e"
  availability_zone = "${data.template_file.aws_region.rendered}a"
  instance_type = "${var.instance_type}"
  key_name = "test_key_pair"
  vpc_security_group_ids = ["${aws_security_group.vpn_sg.id}"]
  subnet_id = "${aws_subnet.pub_subnet.id}"
  user_data = "${file("user-data.sh")}"

  tags {
    Name = "vpn-instance"
    env = "vpn"
  }
}

#================ Elastic IP (Optional) ================
resource "aws_eip" "eip" {
  instance = "${aws_spot_instance_request.instance_request.spot_instance_id}"
  vpc = "true"

  tags {
    Name = "vpn-ip"
    env = "vpn"
  }
}
