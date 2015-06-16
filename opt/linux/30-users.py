#!/usr/bin/env python2

from __future__ import print_function

import errno
import grp
import cPickle as pickle
import pwd
import subprocess

MAP_OLD = '/etc/host-userdata'
MAP_NEW = '/ch/meta/host-userdata'
DEFAULT_UID = 65531
DEFAULT_PGID = 65531
MIN_GID = 500  # assume smaller GIDs are system groups and leave them alone

def print(*args, **kwargs):
   __builtins__.print(*(('ch:',) + args), **kwargs)

def shell(*args):
   args = [str(i) for i in args]
   print('$ %s' % ' '.join(args))
   subprocess.call(args)

class UserVoodoo:

   def main(self):
      print('uid/gid magic starting')
      self.load_old()
      self.load_new()
      self.adjust()
      self.save_settings()
      print('uid/gid magic done')

   def adjust(self):
      # delete legacy secondary job user "chextern" if it exists
      try:
         pw = pwd.getpwnam('chextern')
         print('legacy secondary job user chextern found, deleting')
         shell('deluser', 'chextern')
         shell('delgroup', self.oldmap['group'][1])
      except KeyError:
         pass
      # remove groups found in old map
      for (gid, group) in self.oldmap['groups']:
         if (gid < MIN_GID):
            print('warning: GID %d is scary; will not remove' % gid)
         else:
            shell('delgroup', group)
      # adjust UID of primary job user (but not name)
      # this updates home directory ownership
      shell('usermod',
            '--uid', self.newmap['user'][0],
            'charlie')
      # add groups from new map
      for (gid, group) in self.newmap['groups']:
         if (gid < MIN_GID):
            print('warning: GID %d is scary; will not add' % gid)
         else:
            shell('addgroup', '--gid', gid, group)
            shell('adduser', 'charlie', group)
      # fix home directory ownership (remaining files are user problem)

   def load_new(self):
      self.newmap = pickle.load(open(MAP_NEW))
      self.print_user_info(self.newmap, 'new')

   def load_old(self):
      try:
         self.oldmap = pickle.load(open(MAP_OLD))
      except IOError as x:
         if (x.errno != errno.ENOENT):
            raise
         print('no old uid/gid map, using defaults')
         self.oldmap = {'user':   (DEFAULT_UID,
                                   pwd.getpwuid(DEFAULT_UID).pw_name),
                        'group':  (DEFAULT_PGID,
                                   grp.getgrgid(DEFAULT_PGID).gr_name),
                        'groups': list()}
      self.print_user_info(self.oldmap, 'old')

   def print_user_info(self, map_, tag):
      print('%s job user info:' % tag)
      print('  user:           %5d %s' % map_['user'])
      print('  primary group:  %5d %s' % map_['group'])
      for (gid, group) in map_['groups']:
         print('  group:          %5d %s' % (gid, group))

   def save_settings(self):
      pickle.dump(self.newmap, open(MAP_OLD, 'w'))
      print('wrote %s' % MAP_OLD)


if (__name__ == '__main__'):
   UserVoodoo().main()
