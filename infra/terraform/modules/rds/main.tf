resource "aws_db_subnet_group" "this" {
  name       = var.subnet_group_name
  subnet_ids = var.subnet_ids

  tags = merge(var.tags, {
    Name = var.subnet_group_name
  })
}

resource "aws_db_instance" "this" {
  identifier = var.identifier

  engine         = "mysql"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = var.storage_type
  storage_encrypted     = var.storage_encrypted

  db_name  = var.db_name
  username = var.username
  password = var.password
  port     = var.port

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = var.security_group_ids
  publicly_accessible    = false

  multi_az                = var.multi_az
  backup_retention_period = var.backup_retention_period
  deletion_protection     = var.deletion_protection
  apply_immediately       = var.apply_immediately

  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : var.final_snapshot_identifier

  tags = merge(var.tags, {
    Name = var.identifier
  })
}
