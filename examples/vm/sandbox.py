#!/usr/bin/python2.7 -u

# Do a variety of security tests. This script needs to be run as root.
#
# The filesystem test directory needs a specific structure and all
# files/directories within are subject to change. See sandbox-make-files.sh.
#
# FIXME:
# command line arguments to jobscript
# this script is messy
#
# NOTE: Running this script in workstation mode can mess up something in the
# VDE networking. One symptom is that DNS stops working throughout the
# cluster. I have not figured out what breaks or why.
#
# WARNING: The sniff test can give false positives if more than one guest is
# present per host. This is because the logic enumerating virtual cluster
# members in test_sniff() accounts only for the first guest on a host.

from __future__ import division
from __future__ import print_function

import argparse
import io
import itertools as it
import os
import os.path
from pprint import pprint
import re
import socket
import subprocess as sp
import sys
import time


ARG = '{}'  # substituted for iterable items in par_cmd()
PING_CT = 3
PING_TIMEOUT = 6    # seconds
SNIFF_TIMEOUT = 12  # seconds
INTERNET_ADDRS = ['8.8.8.8',    # Google public DNS
                  '8.8.4.4',    # Google public DNS
                  '192.0.2.1']  # nonexistent example address (RFC 5737)
TRY_PORTS = [   22,  # ssh
               111,  # RPC portmapper (used for NFS and other stuff)
               988,  # Lustre
              2049,  # NFS
              3260,  # Panasas
              3095,  # Panasas
             10622]  # Panasas
CLUSTER_HOST_MIN = 1
CLUSTER_HOST_MAX = 252
PRE_IP_DELAY = 0  # wait in seconds before changing IP (poor man's sync)
RESPONSE_PRINT_CT = 3

# test commands for dir and file respectively
FS_READ = ['ls %(path)s',
           'cat %(path)s']
FS_WRITE = ['touch %(path)s/newfile && rm %(path)s/newfile',
            'echo hello >> %(path)s']
FS_TRAV = ['cat %(path)s/file',
           'echo %(path)s is a file 1>&2']

ap = argparse.ArgumentParser()
ap.add_argument('-e', '--extra',
                metavar='ADDR',
                default=list(),
                nargs='+')
ap.add_argument('-p', '--pattern',
                metavar='PAT',
                default=list(),
                nargs='+')
ap.add_argument('PHYS_IP_BASE')
ap.add_argument('--all', action='store_true')
ap.add_argument('--all-ips', action='store_true')
ap.add_argument('--all-net-tests', action='store_true')
ap.add_argument('--filesystem', metavar='PATH')
ap.add_argument('--ip-correct', action='store_true')
ap.add_argument('--ip-spoof-virtual', action='store_true')
ap.add_argument('--ip-spoof-physical', action='store_true')
ap.add_argument('--ping', action='store_true')
ap.add_argument('--portscan', action='store_true')
ap.add_argument('--sniff', action='store_true')
ap.add_argument('--log',
                metavar='FILE',
                help='default /tmp/sandbox.out',
                default='/tmp/sandbox.out')
args = ap.parse_args()
if (args.all):
   args.all_ips = True
   args.all_net_tests = True
   args.filesystem = True
if (args.all_ips):
   args.ip_correct = True
   args.ip_spoof_virtual = True
   args.ip_spoof_physical = True
if (args.all_net_tests):
   args.ping = True
   args.portscan = True
   args.sniff = True
if (not (   args.ip_correct
         or args.ip_spoof_virtual
         or args.ip_spoof_physical
         or args.filesystem)):
   ap.error('No test IPs specified (try --all-ips or --filesystem?)')
if (not (   args.ping
         or args.portscan
         or args.sniff
         or args.filesystem)):
   print('Warning: no tests specified (try --all-net-tests or --filesystem?)',
         file=sys.stderr)
args.pattern.append('172.22.%d.254')

print('Real space IP spoof base:')
print('  ', args.PHYS_IP_BASE)
print('Cluster IP pattern(s):')
for p in args.pattern:
   print('  ', p)
print('Internet hosts:')
for a in INTERNET_ADDRS:
   print('  ', a)
print('Extra hosts:')
for a in args.extra:
   print('  ', a)
print('TCP ports to scan:')
for p in TRY_PORTS:
   print('  %5d' % p)

log_fp = io.open(args.log, 'wb')
print_real = print
def print(*args, **kwargs):
   print_real(*args, **kwargs)
   if ('file' not in kwargs):
      print_real(file=log_fp, *(('***',) + args), **kwargs)

try:
   ch_guest_id = int(os.environ['CH_GUEST_ID'])
except KeyError:
   print('Error: No CH_GUEST_ID in environment (did you source charlie.sh?)',
         file=sys.stderr)
   sys.exit(1)

def main():
   global vcluster_guests
   vcluster_guests = vcluster_addrs_get(True, '172.22.%d.1')
   global vcluster_hosts
   vcluster_hosts = list(it.chain.from_iterable(vcluster_addrs_get(True, p)
                                                for p in args.pattern))
   global other_guests
   other_guests = vcluster_addrs_get(False, '172.22.%d.1')
   global other_hosts
   other_hosts = list(it.chain.from_iterable(vcluster_addrs_get(False, p)
                                             for p in args.pattern))
   if (args.ip_correct):
      ip_print()
      print('Network tests with correct IP (%s)' % ip_str())
      test_net('correct')
   if (args.ip_spoof_virtual):
      ip_spoof(ip_spoof_virtual)
      print('Network tests with spoofed virtual IP (%s)' % ip_str())
      pre_ip_wait(args.ip_correct)
      test_net('virtual spoofed')
      ip_restore()
   if (args.ip_spoof_physical):
      ip_spoof(ip_spoof_physical)
      print('Network tests with spoofed physical IP (%s)' % ip_str())
      pre_ip_wait(args.ip_correct)
      test_net('physical spoofed')
      ip_restore()
   test_filesystem()
   print('Done, IP is %s' % ip_str())

def fs_cdparent(path):
   print('Testing "cd .." from %s' % path)
   # split the two cd commands to prevent shell from optimizing it away
   out = shell("sudo sh -c 'cd %s && cd .. && readlink -f . && ls'"
               % args.filesystem)
   if (out == '''\
/ch
data1
data2
data3
data4
meta
opt
tmp
'''):
      print('  OK')
   else:
      print('  FAILED, see log for details')
   print(out, file=log_fp)

def fs_test(letter, cmds, path):
   if (os.path.isdir(path)):
      print('  directory', file=log_fp)
      cmd = cmds[0] % locals()
   elif (os.path.isfile(path)):
      print('  file', file=log_fp)
      cmd = cmds[1] % locals()
   elif (os.path.islink(path)):
      print('  broken symlink', file=log_fp)
      return '-'
   else:
      assert False
   out = shell("  sudo sh -c '%s' > /dev/null || true" % cmd)
   if (out == ''):
      print('  result: %s' % letter, file=log_fp)
      return letter
   else:
      print('  result: -', file=log_fp)
      print(out, file=log_fp)
      return '-'

def ip_exclude_me(addrs):
   'Given an iterable of IP addresses, return it as a list with my IP excluded.'
   my_addr = ip_get()[0]
   return [a for a in addrs if a != my_addr]

def ip_get():
   'Return a tuple: (IP address, mask bits, broadcast address, default gateway).'
   ret = None
   for line in sp.check_output(['ip', 'addr', 'show', 'eth0']).split('\n'):
      m = re.search(r'^\s*inet ([\d.]+)/(\d{2}) brd ([\d.]+)', line)
      if (m is not None):
         ret = m.groups()
         break
   for line in sp.check_output(['ip', 'route', 'show']).split('\n'):
      m = re.search(r'^default via ([\d.]+)', line)
      if (m is not None):
         ret += m.groups()
         break
   return tuple(ret)

def ip_octets_from(octets):
   return '.'.join(str(i) for i in octets)

def ip_octets_to(addr):
   m = re.search(r'^(\d+)\.(\d+)\.(\d+)\.(\d+)$', addr)
   return [int(i) for i in m.groups()]

def ip_print():
   print('*** IP status', file=log_fp)
   log_fp.write(sp.check_output(['ip', 'addr', 'show', 'eth0']))
   log_fp.write(sp.check_output(['ip', 'route', 'show']))

def ip_restore():
   sp.check_call(['sudo IFACE=eth0 /ch/opt/linux/network.sh'], shell=True)
   ip_print()

def ip_set(addr, masklen, bcast, gateway, gateway_needs_route=False):
   # This replicates the basic functionality of /ch/opt/linux/network.sh. I
   # couldn't figure out how to change the IP address without destroying all
   # the routing, so we just start over.
   sp.check_call(['sudo', 'ip', 'addr', 'flush', 'dev', 'eth0'])
   sp.check_call(['sudo', 'ip', 'addr', 'add',
                  '%s/%s' % (addr, masklen), 'broadcast', bcast, 'dev', 'eth0'])
   if (gateway_needs_route):
      sp.check_call(['sudo', 'ip', 'route', 'add', gateway, 'dev', 'eth0'])
   sp.check_call(['sudo', 'ip', 'route', 'add', 'default',
                  'via', gateway, 'dev', 'eth0'])
   ip_print()

def ip_spoof(mod_function):
   ip_set(gateway_needs_route=True, *mod_function(ip_get()))

def ip_spoof_physical(ip):
   (addr, masklen, bc, gw) = ip
   os_spoof = ip_octets_to(args.PHYS_IP_BASE)
   os_spoof[3] += ch_guest_id
   addr = ip_octets_from(os_spoof)
   os_spoof[3] = 255
   bc = ip_octets_from(os_spoof)
   return (addr, masklen, bc, gw)

def ip_spoof_virtual(ip):
   (addr, masklen, bc, gw) = ip
   os = ip_octets_to(addr)
   os[2] += 1
   addr = ip_octets_from(os)
   os = ip_octets_to(bc)
   os[2] += 1
   bc = ip_octets_from(os)
   return (addr, masklen, bc, gw)

def ip_str():
   return '%s/%s bc=%s gw=%s' % ip_get()

def par_cmd(cmd_base, iter_):
   'Return number of commands that succeeded.'
   print('cmd base = %s' % str(cmd_base), file=log_fp)
   def subif(base, sub):
      if (base == ARG):
         return sub
      else:
         return base
   children = set()
   rets = list()
   for arg in iter_:
      cmd = []
      p = (arg, sp.Popen([str(subif(j, arg)) for j in cmd_base],
                         stdout=sp.PIPE, stderr=sp.STDOUT))
      children.add(p)
   for p in children:
      (stdout, _) = p[1].communicate()
      print('\n*** pid %d stdout and stderr' % p[1].pid, file=log_fp)
      log_fp.write(stdout)
      rets.append((p[0], p[1].returncode))
   return [r[0] for r in rets if not r[1]]

def par_ping(msg, addrs):
   addrs = ip_exclude_me(addrs)
   print('Pinging %3d addresses: %s' % (len(addrs), msg))
   success = par_cmd(('ping', '-c', PING_CT, '-W', PING_TIMEOUT, ARG), addrs)
   print('%11d responded %s' % (len(success), str(success[:RESPONSE_PRINT_CT])))

def par_tcp(msg, port, addrs):
   addrs = ip_exclude_me(addrs)
   print('Trying TCP port %5d on %3d addresses: %s' % (port, len(addrs), msg))
   success = par_cmd(('nc', '-nvz', '-w', PING_TIMEOUT, ARG, port), addrs)
   print('%28d were open %s' % (len(success), str(success[:RESPONSE_PRINT_CT])))

def pre_ip_wait(old_boolean):
   if (old_boolean):
      print('Waiting %d seconds' % PRE_IP_DELAY)
      time.sleep(PRE_IP_DELAY)

def shell(cmd):
   print(cmd, file=log_fp)
   return sp.check_output(cmd, shell=True, stderr=sp.STDOUT)

def test_filesystem():
   if (not args.filesystem):
      print('Skipping filesystem tests')
      return
   # NOTE: We use subprocesses rather than native Python calls because all
   # this stuff needs to be done as root.
   fs_cdparent(args.filesystem)
   start_dir = os.getcwd()
   test_ct = 0
   fails = list()
   print('Filesystem tests in %s' % args.filesystem)
   for path in sorted(os.listdir(args.filesystem)):
      path = args.filesystem + '/' + path
      test_ct += 1
      m = re.search(r'~(...)$', path)
      if (m is None):
         print('skipping %s (no expected test result)' % path, file=log_fp)
      else:
         expected = m.group(1)
         print('found %s' % path, file=log_fp)
         result = (  fs_test('r', FS_READ, path)
                   + fs_test('w', FS_WRITE, path)
                   + fs_test('t', FS_TRAV, path))
         if (expected != result):
            print('  failed', file=log_fp)
            fails.append((path, result))
   print('  %d of %d tests failed %s' % (len(fails), test_ct, fails[:3]))
   os.chdir(start_dir)

def test_net(msg):
   test_ping(msg)
   test_portscan(msg)
   test_sniff(msg)

def test_ping(msg):
   if (not args.ping):
      print('Skipping ping tests (%s IP)' % msg)
      return
   print('Ping with %s IP ...' % msg)
   par_ping('vcluster guests and hosts',
            (vcluster_guests + vcluster_hosts)),
   par_ping('other guests and hosts, internet, and extra',
            (other_guests + other_hosts + INTERNET_ADDRS + args.extra))

def test_portscan(msg):
   if (not args.portscan):
      print('Skipping portscan tests (%s IP)' % msg)
      return
   print('TCP portscan with %s IP ...' % msg)
   for port in TRY_PORTS:
      par_tcp('vcluster guests and hosts', port,
              (vcluster_guests + vcluster_hosts))
      par_tcp('other guests and hosts, and extra', port,
              (other_guests + other_hosts + args.extra))

def test_sniff(msg):
   if (not args.sniff):
      print('Skipping sniff tests (%s IP)' % msg)
      return
   print('Sniffing with %s IP' % msg)
   cmd =  ['sudo', 'tcpdump', '-nnSU', '-i', 'eth0']
   cmd += ['not', 'src', '(']
   for addr in it.chain(vcluster_guests, vcluster_hosts):
      cmd += [addr, 'or']
   cmd.pop()  # remove extra "or"
   cmd += [')']
   print('sniff_cmd =', str(cmd), file=log_fp)
   p = sp.Popen(cmd, stdout=sp.PIPE, stderr=sp.STDOUT)
   time.sleep(SNIFF_TIMEOUT)
   sp.call(['sudo', 'kill', str(p.pid)])  # p is root so can't use p.terminate()
   (stdout, _) = p.communicate()
   print('\n*** pid %d stdout and stderr' % p.pid, file=log_fp)
   log_fp.write(stdout)
   m = re.search('^(\d+ packets captured)$', stdout, re.MULTILINE)
   print('  ', m.group(1))

def vcluster_addrs_get(incluster_p, pattern):
   '''Return IP addresses for machines associated with the virtual cluster.
      Specifically, enumerate each octet from CLUSTER_HOST_MIN to
      CLUSTER_HOST_MAX and insert it into pattern. If incluster_p, return
      addresses associated with machines in the virtual cluster; otherwise,
      return addresses associated with machines not in the virtual cluster.

      Note that this only includes the first guest on each host.'''
   incluster_hosts = set()
   with io.open('/etc/hosts', 'rt') as fp:
      for line in fp:
         m = re.search(r'172\.22\.(\d+)\.\d+', line)
         if (m is not None):
            incluster_hosts.add(int(m.group(1)))
   ret = list()
   for i in range(CLUSTER_HOST_MIN, CLUSTER_HOST_MAX + 1):
      if (   (    incluster_p and i     in incluster_hosts)
          or (not incluster_p and i not in incluster_hosts)):
         ret.append(pattern % i)
   return ret


if (__name__ == '__main__'):
   main()
