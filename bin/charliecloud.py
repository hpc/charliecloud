from __future__ import print_function

import argparse
import errno
import io
import json
import os
import os.path
from pprint import pprint
import re
import shutil
import signal
import subprocess
import sys
import uuid

import docopt


script = os.path.basename(sys.argv[0])
package = 'charliecloud'
fullname = '%s (part of %s)' % (script, package)
cl = dict()
warnings = list()
error_ct = 0
warning_ct = 0


IMAGE_FMT = 'qcow2'
IMAGE_EXT = 'qcow2'
CLUSTER_SIZE = '512k'


class Invalid_Argument_Type(Exception): pass
class SIGTERM(Exception): pass
class SIGUSR1(Exception): pass


class Tristate(object):
   'Tri-state object from <http://stackoverflow.com/a/9504358/396038>.'

   __slots__ = ('value',)

   true_strings =  set(('true',  'yes', 'y', 'on'))   # True
   false_strings = set(('false', 'no',  'n', 'off'))  # False
   maybe_strings = set(('maybe', 'prompt'))           # None

   def __init__(self, value):
      if (any(value is v for v in (True, False, None))):
         self.value = value
      elif (isinstance(value, basestring)):
         value = value.lower()
         if (value in self.true_strings):
            self.value = True
         elif (value in self.false_strings):
            self.value = False
         elif (value in self.maybe_strings):
            self.value = None
         else:
            raise ValueError('Cannot convert string to Tristate')
      else:
         raise ValueError('Need True, False, None, or a corresponding string')

   def __eq__(self, other):
      return self.value is other
   def __ne__(self, other):
      return self.value is not other
   def __nonzero__(self):   # Python 3: __bool__()
      raise TypeError('Tristate value cannot be used as implicit boolean')

   def __str__(self):
      return str(self.value)
   def __repr__(self):
      return 'Tristate(%s)' % (self.value)

   @classmethod
   def from_terminal(class_, message, require_yesno=True):
      'Prompt user for a value. See <http://stackoverflow.com/a/3042378>.'
      assert (require_yesno), 'unimplemented'
      while (True):
         try:
            return class_(raw_input('* %s ' % message))
         except ValueError:
            pass


def clargs_parse(text, config_file=None):
   # Build a map of the defaults
   defaultsl = docopt.parse_defaults(text)
   defaults = dict()
   for o in defaultsl:
      if (o.long is not None):
         defaults[o.long] = o.value
      if (o.short is not None):
         defaults[o.short] = o.value
   # Parse arguments to dictionary
   argsd = docopt.docopt(text, version=version())
   # Add configured overrides
   if (config_file is not None):
      if (os.path.exists(config_file)):
         print ('found host configuration file %s' % config_file)
         over = json.load(io.open(config_file))
         for (k,v) in over.iteritems():
            argsd[k] = v
   # Infer types of arguments. Basically, we try to convert the default values
   # to increasingly stringent types; if it works, we assume that's the desired
   # type and try to convert the argument's actual value.
   for (k,v) in defaults.iteritems():
      if (isinstance(v, basestring)):  # default was provided
         try:
            try:         # integer
               int(v)
               try:
                  argsd[k] = int(argsd[k])
               except ValueError:
                  raise Invalid_Argument_Type(k, 'integer')
            except ValueError:
               try:      # float
                  float(v)
                  try:
                     argsd[k] = float(argsd[k])
                  except ValueError:
                     raise Invalid_Argument_Type(k, 'float')
               except ValueError:
                  try:   # tristate
                     Tristate(v)
                     try:
                        argsd[k] = Tristate(argsd[k])
                     except ValueError:
                        raise Invalid_Argument_Type(k, 'tristate')
                  except ValueError:
                     pass
         except Invalid_Argument_Type as x:
            # FIXME: integrate better with other usage error reporting
            fatal('expected %s value for %s' % (x.args[1], x.args[0]))
   # Convert to namespace
   argsns = argparse.Namespace()
   for (k, v) in argsd.iteritems():
      k = k.lower()                  # convert to lower-case
      k = k.replace('-', '_')        # dash to underscore
      k = re.sub(r'\W', '', k)       # remove non-alphanumeric, non-underscore
      k = re.sub(r'^[_\d]+', '', k)  # remove leading underscores and digits
      setattr(argsns, k, v)
   # Done
   global cl
   cl = argsns
   #pprint(vars(cl))
   return cl

def error(msg):
   global error_ct
   error_ct += 1
   print('ERROR: %s' % msg, file=sys.stderr)

def fallocate(name, size, clobber=False):
   "Create a new disk file using the fallocate() system call."
   # FIXME: Currently this will not work on OS X, because it doesn't have that
   # system call. However, check the "mkfile" command as that may work
   # similarly. Alternately, we could just drop back to qemu-img create.
   if (os.path.exists(name)):
      if (clobber):
         if (os.path.isfile(name)):
            warning("deleting %s" % name)
            os.unlink(name)
         else:
            fatal("can't fallocate: %s exists and is not a regular file" % name)
      else:
         fatal("can't fallocate: %s exists, won't clobber" % name)
   shell('fallocate', ('-l', size, name))

def fatal(msg):
   print('FATAL: %s' % msg, file=sys.stderr)
   sys.exit(1)

def grep(filename, regex, ignore_read_err=False):
   """If ignore_nonexist, then simply return None if the file can't be read,
      rather than raising an exception."""
   try:
      with io.open(filename, 'r') as fp:
         data = fp.read()
         return re.search(regex, data, re.MULTILINE)
   except IOError as x:
      if (not ignore_read_err):
         raise

def hostlist_expand(hostlist):
   # There is a Python module to expand hostlists, but that would add another
   # dependency. If we have SLURM, we almost certainly have a hostlist utility
   # too, so use that; these tend to have a variety of default delimiters, so
   # try not to care much about those.
   expanded_str = subprocess.check_output(['hostlist', '-e', hostlist])
   return re.split(r'\W+', expanded_str.strip())

def make_empty_file(filename, dir_='.'):
   open(os.path.join(dir_, filename), 'w').close()

def memtotal_kb():
   return int(grep('/proc/meminfo', r'^MemTotal:\s+(\d+) kB$').group(1))

def mkdir(base, dir_, clobber=False):
   dir_ = os.path.join(base, dir_)
   if (os.path.exists(dir_) and not os.path.isdir(dir_)):
      fatal('need directory %s but non-directory in the way' % (dir_))
   if (not os.path.exists(dir_)):
      os.mkdir(dir_)
   elif (clobber):
      # Don't remove the directory itself, just clean it out. This avoids
      # breaking less -F.
      for i in os.listdir(dir_):
         i = os.path.join(dir_, i)
         if (os.path.isdir(i)):
            shutil.rmtree(i)
         else:
            os.unlink(i)
   return dir_

def o_direct_p(dir_):
   'Return True if O_DIRECT is supported in dir, False otherwise.'
   filename = '%s/o_direct_test.%s' % (dir_, uuid.uuid4().hex)
   try:
      fp = os.open(filename, os.O_CREAT|os.O_EXCL|os.O_DIRECT, 0600)
   except OSError:
      return False
   os.close(fp)
   os.unlink(filename)
   return True

def path(dir_=None):
   bin_dir = os.path.dirname(__file__)
   result = os.path.realpath(os.path.join(bin_dir, '..'))
   if (dir_ is not None):
      result = os.path.join(result, dir_)
   return result

def qemu_img_commit(overlay):
   shell('qemu-img', ('commit', overlay))
   unlink(overlay)

def qemu_img_create(name, clobber, size=None, base=None):
   assert ((size or base) and not (size and base))
   opts = { 'cluster_size':    CLUSTER_SIZE,
            'lazy_refcounts':  'on' }
   if (base):
      opts['backing_file'] = os.path.abspath(base)
   if (not clobber and os.path.exists(name)):
      fatal('%s already exists' % (name))
   shell('qemu-img', ('create', '-f', IMAGE_FMT, '-o', qemu_options(opts),
                      name, size))

def qemu_img_info(name):
   shell('qemu-img', ('info', name))

def qemu_options(d):
   return ','.join('%s=%s' % (opt, arg) for (opt, arg) in d.iteritems())

def signals_default():
   signal.signal(signal.SIGTERM, signal.SIG_DFL)
   signal.signal(signal.SIGUSR1, signal.SIG_DFL)

def signals_listen():
   signal.signal(signal.SIGTERM, sigterm_handle_once)
   signal.signal(signal.SIGUSR1, sigusr1_handle_once)

def sigterm_handle_once(signum, frame):
   signals_default()
   print('SIGTERM received')
   raise SIGTERM()

def sigusr1_handle_once(signum, frame):
   signals_default()
   print('SIGUSR1 received')
   raise SIGUSR1()

def shell(cmd, args, outerr=None, async=False, failok=False):
   '''Execute cmd with arguments args and return the resulting subprocess.Popen
      object. This is done directly, without going through the shell. Thus,
      shell tricks like tilde expansion aren't done.

      cmd can be either a string or a sequence of strings.

      args needs to be an iterable. If it's not, it's turned into one using
      shell_args_toseq(). Pass an empty iterable if there are no arguments.

      outerr, if not None, is the name of a file to hold standard output and
      standard error. If it already exists, it will be overwritten. Note that
      buffering in the child process can result in out-of-order output. If
      None, then standard output and error are shared with the parent.

      If async is False, then wait until the child process completes before
      returning. Otherwise, return immediately; the caller is then responsible
      for calling wait() and dealing with the return value.

      If equals_sep is True, then use the equals sign to separate arguments
      from argument values rather than placing them in separate items in
      args.'''
   args = shell_args_toseq(args)
   if (isinstance(cmd, basestring)):
      cmd = [cmd]
   #pprint(cmd + args)
   print('$ ' + ' '.join(cmd + args), end=' ')
   if (outerr is not None):
      print('>& %s' % (outerr))
      stdout = io.open(outerr, 'wb', buffering=0)
   else:
      print()
      stdout = None  # use parent's stdout
   if (async):
      stdin=open(os.devnull, 'rb')
   else:
      stdin=None     # share parent's stdin
   p = subprocess.Popen(cmd + args, stdin=stdin,
                        stdout=stdout, stderr=subprocess.STDOUT)
   if (not async):
      wait(p, failok=failok)
   return p

def shell_args_toseq(args):
   '''Convert args into a sequence suitable for a subprocess invocation.
      Specifically:

        - If args is a string, split it on whitespace and return the resulting
          list.

        - If args is a mapping, key and value comprise pairs of list elements;
          return the resulting list (note that order is arbitrary). If the
          value is itself a mapping, repeat the key once per sub-value, in
          order of sub-key (sub-keys are otherwise ignored). For example, {1:
          {2:3, 4:5}} becomes [1, 3, 1, 5].

        - Otherwise, call str() on each element of args and return the
          resulting sequence.

      If none of this works, raise ValueError.'''
   try:                                                            # string
      return args.split()
   except AttributeError:
      try:                                                         # mapping
         ret = list()
         for (k, v) in args.iteritems():
            try:
               for (k2, v2) in v.iteritems():
                  ret.append(str(k))
                  if (v2 is not None): ret.append(str(v2))
            except AttributeError as x:
               # v is not a mapping
               ret.append(str(k))
               if (v is not None): ret.append(str(v))
         return ret
      except AttributeError:                                       # sequence
         try:
            return [str(i) for i in args if (i is not None)]
         except TypeError as x:
            raise ValueError("invalid type for args: %s" % (type(args)))

def unlink(filename, ignore_errs=False):
   try:
      os.unlink(filename)
   except (IOError, OSError) as x:
      print("can't delete %s: %s" % (filename, x))
      if (not ignore_errs):
         fatal('aborting after unlink error')
   else:
      print("deleted %s" % filename)

def version():
   return open('%s/VERSION' % path()).readline().rstrip()

def wait(pop, signal=None, failok=False):
   if (signal):
      pop.send_signal(signal)
   try:
      signals_listen()
      pop.wait()
      signals_default()
      if (pop.returncode != 0 and not (failok or signal)):
         fatal('subprocess exited with code %d, aborting' % pop.returncode)
   except (SIGTERM, SIGUSR1):
      print('killing subprocess')
      pop.terminate()
      pop.wait()
      print('killed subprocess exited with code %d' % pop.returncode)
   return pop.returncode

def warning(text, save=True):
   global warning_ct
   warning_ct += 1
   print('WARNING: %s' % text, file=sys.stderr)
   if (save):
      warnings.append(text)

def warnings_dump():
   global warnings
   for w in warnings:
      warning(w, save=False)
   warnings = list()

def unlink_f(path):
   try:
      os.unlink(path)
   except OSError as x:
      if (x.errno != errno.ENOENT): raise
