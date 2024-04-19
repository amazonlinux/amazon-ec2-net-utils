import random
import boto3
import time
import subprocess
import os

AMI_ID_SSM_PARAM = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"

# TODO: Make calls to these methods consistent. Either pass the client or initialize it everytime

def is_instance_ready(ec2_client, instance_id) -> bool:
    instance_state = get_instance_state(ec2_client, instance_id)
    for state in instance_state:
        if state != "running":
            return False
    if get_instance_ssm_state(instance_id) == False:
        return False
    return True

def get_ssh_command(ec2_client, instance_id):
    instance_state_response = ec2_client.describe_instances(InstanceIds=[instance_id])
    public_dns_names = [instance["PublicDnsName"] for instance in instance_state_response["Reservations"][0]["Instances"]]
    ssh_command = ["ssh -i ~/.ssh/angrykitten_server_key.pem ec2-user@" + public_dns_name for public_dns_name in public_dns_names]
    print(ssh_command[0])
    return

def is_instance_stopped(ec2_client, instance_id) -> bool:
    instance_state = get_instance_state(ec2_client, instance_id)
    for state in instance_state:
        if state != "stopped":
            return False
    return True

def get_instance_ssm_state(instance_id: str) -> bool:
    client = boto3.client('ssm')
    instance_information = client.describe_instance_information(Filters=[{'Key': 'InstanceIds', 'Values': [instance_id]}])
    if len(instance_information["InstanceInformationList"]) == 0:
        return False
    if instance_information["InstanceInformationList"][0]["PingStatus"] == "Online":
        return True
    return False

def get_instance_state(ec2_client, instance_id) -> list:
    instance_state_response = ec2_client.describe_instances(InstanceIds=[instance_id])
    return [instance_description["State"]["Name"] for instance_description in instance_state_response["Reservations"][0]["Instances"]]

def get_latest_al2023_ami() -> str:
    """
    Pull the latest AL2023 AMI from SSM.
    """
    return  boto3.client('ssm').get_parameter(Name=AMI_ID_SSM_PARAM)["Parameter"]["Value"]

def pick_security_group() -> str:
    """
    Returns a random security group id. Since this is mostly all done in test AWS accounts
    every security group is valid.
    """
    security_groups = boto3.client('ec2').describe_security_groups()
    return security_groups["SecurityGroups"][random.randrange(0, len(security_groups))]["GroupId"]

def exec_command(instance_id:str, command:str):
    """
    Executes a command on an instance.
    """
    client = boto3.client('ssm')
    print(f"\033[97m Running command: {command} on instance {instance_id}\033[00m")
    resp = client.send_command(InstanceIds=[instance_id], DocumentName="AWS-RunShellScript", Parameters={"commands": [command]})
    command_id:str = resp["Command"]["CommandId"]
    time.sleep(2)
    command_output = client.get_command_invocation(CommandId=command_id, InstanceId=instance_id)
    return command_output["StandardOutputContent"]

def get_instance_ip(instance_id:str):
    ec2_client = boto3.client('ec2')
    instance_state_response = ec2_client.describe_instances(InstanceIds=[instance_id])
    public_dns_names = [instance["PublicDnsName"] for instance in instance_state_response["Reservations"][0]["Instances"]]
    return public_dns_names[0]

def copy_rpms_to_ec2(rpmdir, ssh_key_file, instance_id, remote_dir):
    """
    Copy all .rpm files from the specified directory to a remote EC2 instance.
    """
    ip = get_instance_ip(instance_id)
    # Make remote dir
    exec_command(instance_id, f'mkdir -m 0777 -p {remote_dir}')
    # Get a list of all .rpm files in the specified directory and its subdirectories
    rpm_files = []
    for root, dirs, files in os.walk(rpmdir):
        rpm_files.extend([os.path.join(root, f) for f in files if f.endswith('.rpm')])

    # Construct the scp command to copy the files
    scp_command = [
        'scp',
        '-r',
        '-o StrictHostKeyChecking=no',
        '-o UserKnownHostsFile=/dev/null',
        '-i', f"~/.ssh/{ssh_key_file}.pem",
    ]
    scp_command.extend(rpm_files)
    scp_command.append(f'ec2-user@{ip}:{remote_dir}')

    # Execute the scp command
    subprocess.run(scp_command, check=True)