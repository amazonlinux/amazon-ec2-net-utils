#!/usr/bin/python2
'''
A simple test case for ENI attach/detach with error injection for talking
to IMDS. Intended to be run on an instance with AWS credentials already set up.
'''

import unittest

import urllib2

import boto3
import botocore
from datetime import datetime
import json
import subprocess
import re
import time
        
def log(error):
    print('{}Z {}'.format(datetime.utcnow().isoformat(), error))


class InstanceManipulator():
    def get_instance_id(self):
        opener = urllib2.build_opener(urllib2.HTTPHandler)
        token_request = urllib2.Request(url="http://169.254.169.254/latest/api/token")
        token_request.add_header('X-aws-ec2-metadata-token-ttl-seconds', 20)
        token_request.get_method = lambda: 'PUT'
        token = opener.open(token_request).read()

        id_request = urllib2.Request(url='http://169.254.169.254/latest/meta-data/instance-id')
        id_request.add_header('X-aws-ec2-metadata-token', token)
        return opener.open(id_request).read()

    def get_region(self):
        opener = urllib2.build_opener(urllib2.HTTPHandler)
        token_request = urllib2.Request(url="http://169.254.169.254/latest/api/token")
        token_request.add_header('X-aws-ec2-metadata-token-ttl-seconds', 20)
        token_request.get_method = lambda: 'PUT'
        token = opener.open(token_request).read()

        id_request = urllib2.Request(url='http://169.254.169.254/latest/dynamic/instance-identity/document')
        id_request.add_header('X-aws-ec2-metadata-token', token)
        self.identity_doc = json.loads(opener.open(id_request).read())
        return self.identity_doc['region']
        
    def __init__(self):
        self.instance_id = self.get_instance_id()
        self.region = self.get_region()
        self.ec2_client = boto3.client('ec2', region_name=self.region)


    def get_subnet_id(self, instance_id):
        try:
            result = self.ec2_client.describe_instances(InstanceIds=[self.instance_id])
            vpc_subnet_id = result['Reservations'][0]['Instances'][0]['SubnetId']
            log("Subnet id: {}".format(vpc_subnet_id))

        except botocore.exceptions.ClientError as e:
            log("Error describing the instance {}: {}".format(self.instance_id, e.response['Error']))
            vpc_subnet_id = None

        return vpc_subnet_id


    def create_interface(self, subnet_id):
        network_interface_id = None

        if subnet_id:
            try:
                network_interface = self.ec2_client.create_network_interface(SubnetId=subnet_id)
                network_interface_id = network_interface['NetworkInterface']['NetworkInterfaceId']
                log("Created network interface: {}".format(network_interface_id))
            except botocore.exceptions.clientError as e:
                log("Error creating network interface: {}".format(e.response['Error']))

        return network_interface_id


    def attach_interface(self, network_interface_id, instance_id, device_index=1):
        attachment = None

        if network_interface_id and instance_id:
            try:
                attach_interface = self.ec2_client.attach_network_interface(
                    NetworkInterfaceId=network_interface_id,
                    InstanceId=instance_id,
                    DeviceIndex=device_index
                    )
                attachment = attach_interface['AttachmentId']
                log("Created network attachment: {}".format(attachment))
            except botocore.exceptions.ClientError as e:
                log("Error attaching network interface: {}".format(e.response['Error']))
                raise e

        return attachment

    def detach_interface(self, attachment_id):
        try:
            self.ec2_client.detach_network_interface(
                AttachmentId=attachment_id
                )
            log("Detached network interface: {}".format(attachment_id))
            return True

        except botocore.exceptions.ClientError as e:
            log("Error detaching interface {}: {}".format(attachment_id, e.response['Error']))
            return False

    def delete_interface(self, network_interface_id):
        deleted = False
        tries = 30
        while not deleted:
            try:
                self.ec2_client.delete_network_interface(
                    NetworkInterfaceId=network_interface_id
                    )
                log("Deleted network interface: {}".format(network_interface_id))
                return True

            except botocore.exceptions.ClientError as e:
                log("Error deleting interface {}: {}".format(network_interface_id, e.response['Error']))
                time.sleep(1)
                tries = tries - 1
                if tries == 0:
                    return False

def verify_interface(interface_nr=1, time_remaining=40):
    ip = None

    while ip is None:
        process = subprocess.Popen(['/sbin/ifconfig', 'eth{}'.format(interface_nr)],
                                   stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE)
        stdout, stderr = process.communicate()
        print stdout,stderr

        m = re.search(r'inet ([0-9.]+)', stdout)
        if m is not None:
            ip = m.group(0)

        time.sleep(1)
        time_remaining -= 1
        if time_remaining == 0:
            return False
        
    return True

def ifdown(interface_nr=1):
    r = subprocess.call(['/sbin/ec2ifdown', 'eth{}'.format(interface_nr)])
    if r == 0:
        return True
    return False
    
class BasicENI(unittest.TestCase):

    def test_add_remove(self):
        '''
        Very basic add/remove of ENI. Verify interface gets an IP.
        '''
        instance = InstanceManipulator()
        subnet_id = instance.get_subnet_id(instance.get_instance_id())
        interface_id = instance.create_interface(subnet_id)
        try:
            attachment = instance.attach_interface(interface_id, instance.get_instance_id())
        except botocore.exceptions.ClientError as e:
            self.assertTrue(instance.delete_interface(interface_id),
                            "Failed deleting interface {} after attach failure".format(interface_id))
            self.assertTrue(False, "Failed to attach interface: {}".format(e.response))
            
        self.assertTrue(interface_id, "Failed creating interface")
        self.assertTrue(attachment, "Failed to attach interface")

        self.assertTrue(verify_interface(), "Interface didn't come up with IP address")

        # This is implicit with the detach, but for simple test, be explicit to have more test paths
        self.assertTrue(ifdown(), "Could not ifdown interface")

        self.assertTrue(instance.detach_interface(attachment),
                        "Failed detaching interface {}, attachment {}".format(interface_id, attachment))
        self.assertTrue(instance.delete_interface(interface_id),
                        "Failed deleting interface {}".format(interface_id))

        log("Success")

    def test_add_remove_without_IMDS(self):
        '''
        Run a simple add/remove but make IMDS unavailable for a period of time.
        '''
        imds_ip = "169.254.169.254"
        instance = InstanceManipulator()
        instance_id = instance.get_instance_id()
        subnet_id = instance.get_subnet_id(instance_id)

        result = True

        for i in range(1,4):
            interface_id = instance.create_interface(subnet_id)
            log("Iteration {} of try without IMDS".format(i))
            try:
                # Reject IMDS queries to fail fast (drop has a longer timeout)
                subprocess.call(['/sbin/iptables', '-A', 'OUTPUT', '--destination', imds_ip, '-j', 'REJECT'])
                log("REJECT packets to IMDS")
                attachment = instance.attach_interface(interface_id, instance_id)
            except botocore.exceptions.ClientError as e:
                subprocess.call(['/sbin/iptables', '-D', 'OUTPUT', '--destination', imds_ip, '-j', 'REJECT'])
                self.assertTrue(instance.delete_interface(interface_id),
                                "Failed deleting interface {} after attach failure".format(interface_id))
                self.assertTrue(False, "Failed to attach interface: {}".format(e.response))
        
            log("Check that interface does *NOT* come up...")

            # Wait i*4 as somewhere between 4 and 12 seconds (for a 4 test iteration) should hit the right
            # code path to ensure we do actually retry the imds token.
            self.assertFalse(verify_interface(time_remaining=i*4), "Interface came up when it shouldn't have!")

            # Now see if it comes up.
            log("Re-enable packets to IMDS")
            subprocess.call(['/sbin/iptables', '-D', 'OUTPUT', '--destination', imds_ip, '-j', 'REJECT'])

            self.assertTrue(interface_id, "Failed creating interface")
            self.assertTrue(attachment, "Failed to attach interface")

            result = verify_interface()

            self.assertTrue(instance.detach_interface(attachment),
                            "Failed detaching interface {}, attachment {}".format(interface_id, attachment))
            self.assertTrue(instance.delete_interface(interface_id),
                            "Failed deleting interface {}".format(interface_id))
            if not result:
                break

        log("Success")
        self.assertTrue(result, "Failed to verify interface")    

    def test_add_remove_many(self):
        '''
        Add as many ENIs as possible and then remove them.
        '''
        instance = InstanceManipulator()
        subnet_id = instance.get_subnet_id(instance.get_instance_id())

        interfaces = []
        attached = []

        test_range = range(1,100)

        for i in test_range:
            interface_id = instance.create_interface(subnet_id)

            try:
                attached.append(instance.attach_interface(interface_id, instance.get_instance_id(), i))
            except botocore.exceptions.ClientError as e:
                if e.response['Error']['Code'] == 'AttachmentLimitExceeded':
                    instance.delete_interface(interface_id)
                    log("Limit of {} interfaces reached".format(len(interfaces)))
                else:
                    self.assertFalse(False, "EC2 error attaching interface: {}".format(e.response))
                break
            else:
                interfaces.append(interface_id)
                self.assertTrue(interfaces[-1], "Failed creating interface {}".format(i))
                self.assertTrue(attached[-1], "Faild to attach interface {}".format(i))
                log("Created and attached interface number {}".format(len(interfaces)))

        for i in range(0,len(interfaces)):
            self.assertTrue(verify_interface(i+1), "Interface {} didn't come up with IP address".format(i+1))

        for i in range(0,len(interfaces)):
            self.assertTrue(instance.detach_interface(attached[i]),
                            "Failed to detach interface {} ({}) attachment {}".format(i, interfaces[i], attached[i]))
            self.assertTrue(instance.delete_interface(interfaces[i]), "Failed to delete interface {}".format(i))

if __name__ == '__main__':
    unittest.main()
