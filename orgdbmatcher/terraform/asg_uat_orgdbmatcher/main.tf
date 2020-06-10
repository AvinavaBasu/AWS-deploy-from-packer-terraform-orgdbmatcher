provider "aws" {
  region = "us-east-1"

  # Make it faster by skipping something
  skip_get_ec2_platforms      = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  skip_credentials_validation = true
  skip_requesting_account_id  = true
}

module "asg" {
  source = "terraform-aws-modules/autoscaling/aws"
   name = "acceptance-orgdbmatcher-application"


  # Launch configuration
  lc_name = "acceptance-orgdbmatcher-launchconfiguration"

  image_id        = "ami-073ac09ab966e4d01"
  instance_type   = "c5.4xlarge"
  key_name        = "orgdbmatcher_uat_keypair"
  security_groups = ["sg-0cebd055785d1d242"]

  ebs_block_device = [
    {
      device_name           = "/dev/xvdz"
      volume_type           = "gp2"
      volume_size           = "50"
      delete_on_termination = true
    },
  ]

  root_block_device = [
    {
      volume_size = "100"
      volume_type = "gp2"
    },
  ]

  # Auto scaling group
  asg_name                  = "acceptance-orgdbmatcher-autoscaling"
  vpc_zone_identifier       = ["subnet-05c77147fb11cdd5b"]
  health_check_type         = "EC2"
  min_size                  = 1
  max_size                  = 1
  desired_capacity          = 1
  wait_for_capacity_timeout = 0
  user_data                 = "${file("userdata.sh")}"
  iam_instance_profile      = "acceptance-orgdbmatcher-application-role"

  tags = [
    {
      key                 = "Environment"
      value               = "uat"
      propagate_at_launch = true
    },
    {
      key                 = "Project"
      value               = "orgdbmatcher"
      propagate_at_launch = true
    },
  ]
}