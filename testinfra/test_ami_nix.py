import base64
import boto3
import gzip
import logging
import os
import pytest
import requests
import socket
import testinfra
import time
from botocore.exceptions import ClientError
from ec2instanceconnectcli.EC2InstanceConnectLogger import EC2InstanceConnectLogger
from ec2instanceconnectcli.EC2InstanceConnectKey import EC2InstanceConnectKey
from time import sleep
from typing import Optional, Dict, Any, List, Callable
from functools import wraps

# if GITHUB_RUN_ID is not set, use a default value that includes the user and hostname
RUN_ID = os.environ.get(
    "GITHUB_RUN_ID",
    "unknown-ci-run-"
    + os.environ.get("USER", "unknown-user")
    + "@"
    + socket.gethostname(),
)
AMI_NAME = os.environ.get("AMI_NAME")
postgresql_schema_sql_content = """
ALTER DATABASE postgres SET "app.settings.jwt_secret" TO  'my_jwt_secret_which_is_not_so_secret';
ALTER DATABASE postgres SET "app.settings.jwt_exp" TO 3600;

ALTER USER supabase_admin WITH PASSWORD 'postgres';
ALTER USER postgres WITH PASSWORD 'postgres';
ALTER USER authenticator WITH PASSWORD 'postgres';
ALTER USER pgbouncer WITH PASSWORD 'postgres';
ALTER USER supabase_auth_admin WITH PASSWORD 'postgres';
ALTER USER supabase_storage_admin WITH PASSWORD 'postgres';
ALTER USER supabase_replication_admin WITH PASSWORD 'postgres';
ALTER ROLE supabase_read_only_user WITH PASSWORD 'postgres';
ALTER ROLE supabase_admin SET search_path TO "$user",public,auth,extensions;
"""
realtime_env_content = ""
adminapi_yaml_content = """
port: 8085
host: 0.0.0.0
ref: aaaaaaaaaaaaaaaaaaaa
jwt_secret: my_jwt_secret_which_is_not_so_secret
metric_collectors:
    - filesystem
    - meminfo
    - netdev
    - loadavg
    - cpu
    - diskstats
    - vmstat
node_exporter_additional_args:
    - '--collector.filesystem.ignored-mount-points=^/(boot|sys|dev|run).*'
    - '--collector.netdev.device-exclude=lo'
cert_path: /etc/ssl/adminapi/server.crt
key_path: /etc/ssl/adminapi/server.key
upstream_metrics_refresh_duration: 60s
pgbouncer_endpoints:
    - 'postgres://pgbouncer:postgres@localhost:6543/pgbouncer'
fail2ban_socket: /var/run/fail2ban/fail2ban.sock
upstream_metrics_sources:
    -
        name: system
        url: 'https://localhost:8085/metrics'
        labels_to_attach: [{name: supabase_project_ref, value: aaaaaaaaaaaaaaaaaaaa}, {name: service_type, value: db}]
        skip_tls_verify: true
    -
        name: postgresql
        url: 'http://localhost:9187/metrics'
        labels_to_attach: [{name: supabase_project_ref, value: aaaaaaaaaaaaaaaaaaaa}, {name: service_type, value: postgresql}]
    -
        name: gotrue
        url: 'http://localhost:9122/metrics'
        labels_to_attach: [{name: supabase_project_ref, value: aaaaaaaaaaaaaaaaaaaa}, {name: service_type, value: gotrue}]
    -
        name: postgrest
        url: 'http://localhost:3001/metrics'
        labels_to_attach: [{name: supabase_project_ref, value: aaaaaaaaaaaaaaaaaaaa}, {name: service_type, value: postgrest}]
monitoring:
    disk_usage:
        enabled: true
firewall:
    enabled: true
    internal_ports:
        - 9187
        - 8085
        - 9122
    privileged_ports:
        - 22
    privileged_ports_allowlist:
        - 0.0.0.0/0
    filtered_ports:
        - 5432
        - 6543
    unfiltered_ports:
        - 80
        - 443
    managed_rules_file: /etc/nftables/supabase_managed.conf
pg_egress_collect_path: /tmp/pg_egress_collect.txt
aws_config:
    creds:
        enabled: false
        check_frequency: 1h
        refresh_buffer_duration: 6h
"""
pgsodium_root_key_content = (
    "0000000000000000000000000000000000000000000000000000000000000000"
)
postgrest_base_conf_content = """
db-uri = "postgres://authenticator:postgres@localhost:5432/postgres?application_name=postgrest"
db-schema = "public, storage, graphql_public"
db-anon-role = "anon"
jwt-secret = "my_jwt_secret_which_is_not_so_secret"
role-claim-key = ".role"
openapi-mode = "ignore-privileges"
db-use-legacy-gucs = true
admin-server-port = 3001
server-host = "*6"
db-pool-acquisition-timeout = 10
max-rows = 1000
db-extra-search-path = "public, extensions"
"""
gotrue_env_content = """
API_EXTERNAL_URL=http://localhost
GOTRUE_API_HOST=0.0.0.0
GOTRUE_SITE_URL=
GOTRUE_DB_DRIVER=postgres
GOTRUE_DB_DATABASE_URL=postgres://supabase_auth_admin@localhost/postgres?sslmode=disable
GOTRUE_JWT_ADMIN_ROLES=supabase_admin,service_role
GOTRUE_JWT_AUD=authenticated
GOTRUE_JWT_SECRET=my_jwt_secret_which_is_not_so_secret
"""
walg_config_json_content = """
{
  "AWS_REGION": "ap-southeast-1",
  "WALG_S3_PREFIX": "",
  "PGDATABASE": "postgres",
  "PGUSER": "supabase_admin",
  "PGPORT": 5432,
  "WALG_DELTA_MAX_STEPS": 6,
  "WALG_COMPRESSION_METHOD": "lz4"
}
"""
anon_key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFhYWFhYWFhYWFhYWFhYWFhYWFhIiwicm9sZSI6ImFub24iLCJpYXQiOjE2OTYyMjQ5NjYsImV4cCI6MjAxMTgwMDk2Nn0.QW95aRPA-4QuLzuvaIeeoFKlJP9J2hvAIpJ3WJ6G5zo"
service_role_key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFhYWFhYWFhYWFhYWFhYWFhYWFhIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTY5NjIyNDk2NiwiZXhwIjoyMDExODAwOTY2fQ.Om7yqv15gC3mLGitBmvFRB3M4IsLsX9fXzTQnFM7lu0"
supabase_admin_key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFhYWFhYWFhYWFhYWFhYWFhYWFhIiwicm9sZSI6InN1cGFiYXNlX2FkbWluIiwiaWF0IjoxNjk2MjI0OTY2LCJleHAiOjIwMTE4MDA5NjZ9.jrD3j2rBWiIx0vhVZzd1CXFv7qkAP392nBMadvXxk1c"
init_json_content = f"""
{{
  "jwt_secret": "my_jwt_secret_which_is_not_so_secret",
  "project_ref": "aaaaaaaaaaaaaaaaaaaa",
  "logflare_api_key": "",
  "logflare_pitr_errors_source": "",
  "logflare_postgrest_source": "",
  "logflare_pgbouncer_source": "",
  "logflare_db_source": "",
  "logflare_gotrue_source": "",
  "anon_key": "{anon_key}",
  "service_key": "{service_role_key}",
  "supabase_admin_key": "{supabase_admin_key}",
  "common_name": "db.aaaaaaaaaaaaaaaaaaaa.supabase.red",
  "region": "ap-southeast-1",
  "init_database_only": false
}}
"""

# Configure logging
logger = logging.getLogger("ami-tests")
handler = logging.StreamHandler()
formatter = logging.Formatter("%(asctime)s %(name)-12s %(levelname)-8s %(message)s")
handler.setFormatter(formatter)
logger.addHandler(handler)
logger.setLevel(logging.DEBUG)

# Constants
MAX_RETRIES = 5
INITIAL_RETRY_DELAY = 2
MAX_RETRY_DELAY = 32
AWS_REGION = "ap-southeast-1"
INSTANCE_TYPE = "t4g.micro"
SECURITY_GROUPS = ["sg-0a883ca614ebfbae0", "sg-014d326be5a1627dc"]
IAM_PROFILE = "pg-ap-southeast-1"
SSH_PORT = 22
SSH_TIMEOUT = 60
HEALTH_CHECK_TIMEOUT = 300  # 5 minutes
HEALTH_CHECK_INTERVAL = 5

def retry_with_backoff(
    max_retries: int = MAX_RETRIES,
    initial_delay: int = INITIAL_RETRY_DELAY,
    max_delay: int = MAX_RETRY_DELAY,
    exceptions: tuple = (Exception,),
):
    """Decorator that implements exponential backoff for retrying operations."""
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            delay = initial_delay
            for attempt in range(max_retries):
                try:
                    return func(*args, **kwargs)
                except exceptions as e:
                    if attempt == max_retries - 1:
                        logger.error(f"Operation failed after {max_retries} attempts: {str(e)}")
                        raise
                    logger.warning(f"Attempt {attempt + 1}/{max_retries} failed: {str(e)}")
                    sleep(delay)
                    delay = min(delay * 2, max_delay)
            return None
        return wrapper
    return decorator

def validate_aws_resources(ec2_client, iam_client) -> None:
    """Validate AWS resources before instance creation."""
    try:
        # Check security groups
        for sg in SECURITY_GROUPS:
            ec2_client.describe_security_groups(GroupIds=[sg])
        
        # Check IAM role
        iam_client.get_instance_profile(InstanceProfileName=IAM_PROFILE)
        
        logger.info("AWS resources validation successful")
    except ClientError as e:
        logger.error(f"AWS resource validation failed: {str(e)}")
        raise

def create_ec2_instance(ec2_resource, image_id: str, user_data: str) -> Any:
    """Create EC2 instance with proper error handling."""
    try:
        instances = ec2_resource.create_instances(
            BlockDeviceMappings=[
                {
                    "DeviceName": "/dev/sda1",
                    "Ebs": {
                        "VolumeSize": 8,
                        "Encrypted": True,
                        "DeleteOnTermination": True,
                        "VolumeType": "gp3",
                    },
                },
            ],
            MetadataOptions={
                "HttpTokens": "required",
                "HttpEndpoint": "enabled",
            },
            IamInstanceProfile={"Name": IAM_PROFILE},
            InstanceType=INSTANCE_TYPE,
            MinCount=1,
            MaxCount=1,
            ImageId=image_id,
            NetworkInterfaces=[
                {
                    "DeviceIndex": 0,
                    "AssociatePublicIpAddress": True,
                    "Groups": SECURITY_GROUPS,
                }
            ],
            UserData=user_data,
            TagSpecifications=[
                {
                    "ResourceType": "instance",
                    "Tags": [
                        {"Key": "Name", "Value": "ci-ami-test-nix"},
                        {"Key": "creator", "Value": "testinfra-ci"},
                        {"Key": "testinfra-run-id", "Value": RUN_ID},
                    ],
                }
            ],
        )
        return instances[0]
    except ClientError as e:
        logger.error(f"Failed to create EC2 instance: {str(e)}")
        raise

@retry_with_backoff()
def wait_for_instance_running(instance) -> None:
    """Wait for instance to be in running state with retries."""
    try:
        instance.wait_until_running()
        logger.info("Instance is running")
    except Exception as e:
        logger.error(f"Failed to wait for instance running state: {str(e)}")
        raise

@retry_with_backoff()
def wait_for_public_ip(instance) -> str:
    """Wait for instance to have a public IP with retries."""
    while not instance.public_ip_address:
        logger.warning("Waiting for public IP to be available")
        sleep(5)
        instance.reload()
    return instance.public_ip_address

@retry_with_backoff()
def wait_for_ssh(ip_address: str) -> None:
    """Wait for SSH to be available with retries."""
    while True:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            if sock.connect_ex((ip_address, SSH_PORT)) == 0:
                logger.info("SSH is available")
                return
        finally:
            sock.close()
        logger.warning("Waiting for SSH to be available")
        sleep(10)

@retry_with_backoff()
def get_ssh_connection(instance_ip: str, ssh_identity_file: str) -> Any:
    """Get SSH connection with retries."""
    return testinfra.get_host(
        f"paramiko://ubuntu@{instance_ip}?timeout={SSH_TIMEOUT}",
        ssh_identity_file=ssh_identity_file,
    )

def check_service_health(host: Any, service: str, check: Callable) -> bool:
    """Check health of a specific service."""
    try:
        cmd = check(host)
        if cmd.failed:
            logger.warning(f"{service} not ready")
            return False
        return True
    except Exception as e:
        logger.warning(f"Connection failed during {service} check: {str(e)}")
        return False

def is_healthy(host: Any, instance_ip: str, ssh_identity_file: str) -> bool:
    """Check if all services are healthy."""
    health_checks = [
        ("postgres", lambda h: h.run("sudo -u postgres /usr/bin/pg_isready -U postgres")),
        ("adminapi", lambda h: h.run(
            f"curl -sf -k --connect-timeout 30 --max-time 60 https://localhost:8085/health -H 'apikey: {supabase_admin_key}'"
        )),
        ("postgrest", lambda h: h.run(
            "curl -sf --connect-timeout 30 --max-time 60 http://localhost:3001/ready"
        )),
        ("gotrue", lambda h: h.run(
            "curl -sf --connect-timeout 30 --max-time 60 http://localhost:8081/health"
        )),
        ("kong", lambda h: h.run("sudo kong health")),
        ("fail2ban", lambda h: h.run("sudo fail2ban-client status")),
    ]

    for service, check in health_checks:
        if not check_service_health(host, service, check):
            return False
    return True

def wait_for_healthy(host: Any, instance_ip: str, ssh_identity_file: str) -> None:
    """Wait for all services to be healthy with timeout."""
    start_time = time.time()
    while time.time() - start_time < HEALTH_CHECK_TIMEOUT:
        if is_healthy(host, instance_ip, ssh_identity_file):
            logger.info("All services are healthy")
            return
        sleep(HEALTH_CHECK_INTERVAL)
    raise TimeoutError("Services did not become healthy within timeout period")

@pytest.fixture(scope="session")
def host():
    """Create and manage an EC2 instance for testing."""
    instance = None
    try:
        # Initialize AWS clients
        ec2_resource = boto3.resource("ec2", region_name=AWS_REGION)
        ec2_client = boto3.client("ec2", region_name=AWS_REGION)
        iam_client = boto3.client("iam", region_name=AWS_REGION)

        # Validate AWS resources
        validate_aws_resources(ec2_client, iam_client)

        # Get AMI
        images = list(ec2_resource.images.filter(
            Filters=[{"Name": "name", "Values": [AMI_NAME]}],
        ))
        if len(images) != 1:
            raise ValueError(f"Expected exactly one AMI, found {len(images)}")
        image = images[0]

        # Create instance
        def gzip_then_base64_encode(s: str) -> str:
            return base64.b64encode(gzip.compress(s.encode())).decode()

        user_data = f"""#cloud-config
hostname: db-aaaaaaaaaaaaaaaaaaaa
write_files:
    - {{path: /etc/postgresql.schema.sql, content: {gzip_then_base64_encode(postgresql_schema_sql_content)}, permissions: '0600', encoding: gz+b64}}
    - {{path: /etc/realtime.env, content: {gzip_then_base64_encode(realtime_env_content)}, permissions: '0664', encoding: gz+b64}}
    - {{path: /etc/adminapi/adminapi.yaml, content: {gzip_then_base64_encode(adminapi_yaml_content)}, permissions: '0600', owner: 'adminapi:root', encoding: gz+b64}}
    - {{path: /etc/postgresql-custom/pgsodium_root.key, content: {gzip_then_base64_encode(pgsodium_root_key_content)}, permissions: '0600', owner: 'postgres:postgres', encoding: gz+b64}}
    - {{path: /etc/postgrest/base.conf, content: {gzip_then_base64_encode(postgrest_base_conf_content)}, permissions: '0664', encoding: gz+b64}}
    - {{path: /etc/gotrue.env, content: {gzip_then_base64_encode(gotrue_env_content)}, permissions: '0664', encoding: gz+b64}}
    - {{path: /etc/wal-g/config.json, content: {gzip_then_base64_encode(walg_config_json_content)}, permissions: '0664', owner: 'wal-g:wal-g', encoding: gz+b64}}
    - {{path: /tmp/init.json, content: {gzip_then_base64_encode(init_json_content)}, permissions: '0600', encoding: gz+b64}}
runcmd:
    - 'sudo echo \"pgbouncer\" \"postgres\" >> /etc/pgbouncer/userlist.txt'
    - 'cd /tmp && aws s3 cp --region ap-southeast-1 s3://init-scripts-staging/project/init.sh .'
    - 'bash init.sh "staging"'
    - 'rm -rf /tmp/*'
"""

        instance = create_ec2_instance(ec2_resource, image.id, user_data)
        logger.info(f"Created instance {instance.id}")

        # Wait for instance to be running
        wait_for_instance_running(instance)

        # Set up EC2 Instance Connect
        ec2logger = EC2InstanceConnectLogger(debug=False)
        temp_key = EC2InstanceConnectKey(ec2logger.get_logger())
        ec2ic = boto3.client("ec2-instance-connect", region_name=AWS_REGION)
        
        @retry_with_backoff()
        def send_ssh_key():
            response = ec2ic.send_ssh_public_key(
                InstanceId=instance.id,
                InstanceOSUser="ubuntu",
                SSHPublicKey=temp_key.get_pub_key(),
            )
            if not response["Success"]:
                raise Exception("Failed to send SSH public key")
        
        send_ssh_key()

        # Wait for public IP and SSH
        ip_address = wait_for_public_ip(instance)
        wait_for_ssh(ip_address)

        # Get SSH connection
        host = get_ssh_connection(ip_address, temp_key.get_priv_key_file())

        # Wait for services to be healthy
        wait_for_healthy(host, ip_address, temp_key.get_priv_key_file())

        yield host

    except Exception as e:
        logger.error(f"Error in host fixture: {str(e)}")
        raise
    finally:
        if instance:
            try:
                instance.terminate()
                logger.info(f"Terminated instance {instance.id}")
            except Exception as e:
                logger.error(f"Failed to terminate instance: {str(e)}")


def test_postgrest_is_running(host):
    postgrest = host.service("postgrest")
    assert postgrest.is_running


def test_postgrest_responds_to_requests(host):
    res = requests.get(
        f"http://{host.backend.get_hostname()}/rest/v1/",
        headers={
            "apikey": anon_key,
            "authorization": f"Bearer {anon_key}",
        },
    )
    assert res.ok


def test_postgrest_can_connect_to_db(host):
    res = requests.get(
        f"http://{host.backend.get_hostname()}/rest/v1/buckets",
        headers={
            "apikey": service_role_key,
            "authorization": f"Bearer {service_role_key}",
            "accept-profile": "storage",
        },
    )
    assert res.ok


# There would be an error if the `apikey` query parameter isn't removed,
# since PostgREST treats query parameters as conditions.
#
# Worth testing since remove_apikey_query_parameters uses regexp instead
# of parsed query parameters.
def test_postgrest_starting_apikey_query_parameter_is_removed(host):
    res = requests.get(
        f"http://{host.backend.get_hostname()}/rest/v1/buckets",
        headers={
            "accept-profile": "storage",
        },
        params={
            "apikey": service_role_key,
            "id": "eq.absent",
            "name": "eq.absent",
        },
    )
    assert res.ok


def test_postgrest_middle_apikey_query_parameter_is_removed(host):
    res = requests.get(
        f"http://{host.backend.get_hostname()}/rest/v1/buckets",
        headers={
            "accept-profile": "storage",
        },
        params={
            "id": "eq.absent",
            "apikey": service_role_key,
            "name": "eq.absent",
        },
    )
    assert res.ok


def test_postgrest_ending_apikey_query_parameter_is_removed(host):
    res = requests.get(
        f"http://{host.backend.get_hostname()}/rest/v1/buckets",
        headers={
            "accept-profile": "storage",
        },
        params={
            "id": "eq.absent",
            "name": "eq.absent",
            "apikey": service_role_key,
        },
    )
    assert res.ok


# There would be an error if the empty key query parameter isn't removed,
# since PostgREST treats empty key query parameters as malformed input.
#
# Worth testing since remove_apikey_and_empty_key_query_parameters uses regexp instead
# of parsed query parameters.
def test_postgrest_starting_empty_key_query_parameter_is_removed(host):
    res = requests.get(
        f"http://{host.backend.get_hostname()}/rest/v1/buckets",
        headers={
            "accept-profile": "storage",
        },
        params={
            "": "empty_key",
            "id": "eq.absent",
            "apikey": service_role_key,
        },
    )
    assert res.ok


def test_postgrest_middle_empty_key_query_parameter_is_removed(host):
    res = requests.get(
        f"http://{host.backend.get_hostname()}/rest/v1/buckets",
        headers={
            "accept-profile": "storage",
        },
        params={
            "apikey": service_role_key,
            "": "empty_key",
            "id": "eq.absent",
        },
    )
    assert res.ok


def test_postgrest_ending_empty_key_query_parameter_is_removed(host):
    res = requests.get(
        f"http://{host.backend.get_hostname()}/rest/v1/buckets",
        headers={
            "accept-profile": "storage",
        },
        params={
            "id": "eq.absent",
            "apikey": service_role_key,
            "": "empty_key",
        },
    )
    assert res.ok
