import boto3
import time
import get_aws_data
import sys

DEFAULT_INSTANCE_TYPE = "t2.micro"

IMAGE_ID = get_aws_data.get_latest_al2023_ami()

# User data to just run for some time. SLOWLY
# USER_DATA = "#!/bin/bash\nfor i in {1..100}\ndo\nsleep 1\ndone\n"
USER_DATA = ""

REBOOT_COUNT = 5

REMOTE_DIR = "/home/ec2-user/package"

LAUNCH_INSTANCE_CONFIG = {
    "MaxCount": 1,
    "MinCount": 1,
    "ImageId": IMAGE_ID,
    "InstanceType": DEFAULT_INSTANCE_TYPE,
    "EbsOptimized": False,
    "NetworkInterfaces": [
        {
        "AssociatePublicIpAddress": True,
        "DeviceIndex": 0,
        "Groups": [
            "sg-08f73919194d678bd"
        ]
        }
    ],
    "TagSpecifications": [
        {
        "ResourceType": "instance",
        "Tags": [
            {
            "Key": "Name",
            "Value": "ec2-net-utils-reboot-test"
            }
        ]
        }
    ],
    "UserData": USER_DATA,
    "PrivateDnsNameOptions": {
        "HostnameType": "ip-name",
        "EnableResourceNameDnsARecord": True,
        "EnableResourceNameDnsAAAARecord": False
    }
}


def main(ec2_client, ssh_key_name, rpm_directory):
    # Launch a graviton instance in ec2 using boto and my aws profile
    run_instance_response = ec2_client.run_instances(KeyName= ssh_key_name, **LAUNCH_INSTANCE_CONFIG)
    # print(run_instance_response["Instances"])
    instance_id = [instance["InstanceId"] for instance in run_instance_response["Instances"]][0]
    print(instance_id)
    time.sleep(2)
    # Wait for instance to be running
    wait_for_instance_to_be_ready(ec2_client, instance_id)
    # TODO: Move these colourful prints to separate methods.
    print("\033[92mInstance is ready\033[00m")

    # Check on initial boot
    stdout = get_aws_data.exec_command(instance_id, "journalctl | grep 'Reloaded networkd' | wc -l").strip("\n")
    check_stdout(stdout, ec2_client, instance_id)
    # Upload new rpm
    get_aws_data.copy_rpms_to_ec2(rpm_directory, ssh_key_name, instance_id, REMOTE_DIR)
    # Update to new rpm
    get_aws_data.exec_command(instance_id, f"yum update -y {REMOTE_DIR}/*.rpm")
    
    for i in range(REBOOT_COUNT):
        # Clean up instance for "new" boot
        get_aws_data.exec_command(instance_id, "journalctl --rotate")
        get_aws_data.exec_command(instance_id, "journalctl --vacuum-time=1s")
        get_aws_data.exec_command(instance_id, "cloud-init clean")
        get_aws_data.exec_command(instance_id, "cloud-init clean --machine-id")
        # reboot
        print("\033[97mRebooting instance\033[00m")
        # Calling reboot_instances does not work here since that does not reflect in the instance state
        # we need the instance to be "up" before we can start working with it. Stopping and starting is
        # more trackable via state
        ec2_client.stop_instances(InstanceIds=[instance_id])
        time.sleep(2)
        wait_for_instance_to_be_stopped(ec2_client, instance_id)
        time.sleep(2)
        ec2_client.start_instances(InstanceIds=[instance_id])
        time.sleep(2)
        wait_for_instance_to_be_ready(ec2_client, instance_id)
        # Check for "Reloaded networkd" since last boot
        # There should only be one reload
        stdout = get_aws_data.exec_command(instance_id, "journalctl -b | grep 'Reloaded networkd' | wc -l").strip("\n")
        # Make sure there is just 1
        check_stdout(stdout, ec2_client, instance_id)
        print("\033[92mThings look fine\033[00m")
        print(f"Reboot {i+1}/{REBOOT_COUNT}")
    get_aws_data.get_ssh_command(ec2_client, instance_id)


def check_stdout(stdout, ec2_client, instance_id):
    if stdout != "1":
        print("\033[91m Looks like the system is showing the issue\033[00m")
        print(f"\033[91m \tstdout: {stdout}\033[00m")
        get_aws_data.get_ssh_command(ec2_client, instance_id)
        sys.exit(1)

def wait_for_instance_to_be_ready(ec2_client, instance_id):
    # TODO: Combine the two "wait_for..." methods
    while(get_aws_data.is_instance_ready(ec2_client, instance_id) == False):
        print("\033[97mWaiting for instance to be ready...\033[00m")
        time.sleep(5)
    print("\033[92mInstance is ready\033[00m")

def wait_for_instance_to_be_stopped(ec2_client, instance_id):
    while(get_aws_data.is_instance_stopped(ec2_client, instance_id) == False):
        print("\033[97mWaiting for instance to be stopped...\033[00m")
        time.sleep(5)
    print("\033[92mInstance is Stopped\033[00m")

if __name__ == "__main__":
    ec2_client = boto3.client('ec2')
    SSH_KEY_NAME = sys.argv[1]
    main(ec2_client, SSH_KEY_NAME, sys.argv[2])