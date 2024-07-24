# implementation of ch-image modify

import enum
import os
import subprocess
import sys
import tempfile
import uuid

import charliecloud as ch
import build
import build_cache as bu
import force
import image as im

lark = im.lark

class Modify_Mode(enum.Enum):
   COMMAND_SEQ = "commands"
   INTERACTIVE = "interactive"
   SCRIPT = "script"

def main(cli_):
   global called
   called = True

   # Need to pass tree to build.py
   global tree

   # In this file, “cli” is used as a global variable
   global cli
   cli = cli_

   # CLI opts that “build.py” expects, but that don’t make sense in the context
   # of “modify”. We set “parse_only” to “False” because we don’t do any
   # parsing, and “context” to the root of the filesystem to ensure that
   # necessary files (e.g. the modify script) will always be somewhere in the
   # context dir.
   cli.parse_only = False
   cli.context = os.path.abspath(os.sep)

   build.cli_process_common(cli)

   commands = []
   # “Flatten” commands array
   for c in cli.c:
      commands += c
   src_image = im.Image(im.Reference(cli.image_ref))
   out_image = im.Image(im.Reference(cli.out_image))
   if (not src_image.unpack_exist_p):
      ch.FATAL("not in storage: %s" % src_image.ref)
   if (cli.out_image == cli.image_ref):
      ch.FATAL("output must be different from source image (%s)" % cli.image_ref)
   if (cli.script is not None):
      if (not ch.Path(cli.script).exists):
         ch.FATAL("%s: no such file" % cli.script)

   # This kludge is necessary because cli is a global variable, with cli.tag
   # assumed present elsewhere in the file. Here, cli.tag represents the
   # destination image.
   cli.tag = str(out_image)

   # Determine modify mode based on what is present in command line
   if (commands != []):
      if (cli.interactive):
         ch.FATAL("incompatible opts: “-c”, “-i”")
      if (cli.script is not None):
         ch.FATAL("script mode incompatible with command mode")
      mode = Modify_Mode.COMMAND_SEQ
   elif (cli.script is not None):
      if (cli.interactive):
         ch.FATAL("script mode incompatible with interactive mode")
      mode = Modify_Mode.SCRIPT
   elif (sys.stdin.isatty() or (cli.interactive)):
      mode = Modify_Mode.INTERACTIVE
   else:
      # Write stdin to tempfile, copy tempfile into container as a script, run
      # script.
      stdin = sys.stdin.read()
      if (stdin == ''):
         ch.FATAL("modify mode unclear")

      tmp = tempfile.NamedTemporaryFile()
      with open(tmp.name, 'w') as fd:
         fd.write(stdin)

      cli.script = tmp.name

      mode = Modify_Mode.SCRIPT

   ch.VERBOSE("modify shell: %s" % cli.shell)
   ch.VERBOSE("modify mode: %s" % mode.value)

   if (mode == Modify_Mode.INTERACTIVE):
      # Interactive case

      # Generate “fake” SID for build cache. We do this because we can’t compute
      # an SID, but we still want to make sure that it’s unique enough that
      # we’re unlikely to run into a collision.
      fake_sid = uuid.uuid4()
      out_image.unpack_clear()
      out_image.copy_unpacked(src_image)
      bu.cache.worktree_adopt(out_image, src_image.ref.for_path)
      bu.cache.ready(out_image)
      bu.cache.branch_nocheckout(src_image.ref, out_image.ref)
      foo = subprocess.run([ch.CH_BIN + "/ch-run", "--unsafe", "-w"]
                            + sum([["-b", i] for i in cli.bind], [])
                            + [str(out_image.ref), "--", cli.shell])
      if (foo.returncode == ch.Ch_Run_Retcode.EXIT_CMD.value):
         # FIXME: Write a better error message?
         ch.FATAL("can't run shell: %s" % cli.shell)
      ch.VERBOSE("using SID %s" % fake_sid)
      # FIXME: metadata history stuff? See misc.import_.
      if (out_image.metadata["history"] == []):
         out_image.metadata["history"].append({ "empty_layer": False,
                                                "command":     "ch-image import"})
      out_image.metadata_save()
      bu.cache.commit(out_image.unpack_path, fake_sid, "MODIFY interactive", [])
   else:
      # non-interactive case
      if (mode == Modify_Mode.SCRIPT):
         # script specified
         tree = modify_tree_make_script(src_image.ref, cli.script)
      elif (mode == Modify_Mode.COMMAND_SEQ):
         # “-c” specified
         tree = modify_tree_make(src_image.ref, commands)
      else:
         assert False, "unreachable code reached"

      # FIXME: pretty printing should prob go here, see issue #1908.
      image_ct = sum(1 for i in tree.children_("from_"))

      build.parse_tree_traverse(tree, image_ct, cli)

def modify_tree_make(src_img, cmds):
   """Construct a parse tree corresponding to a set of “ch-image modify”
      commands, as though the commands had been specified in a Dockerfile. Note
      that because “ch-image modify” simply executes one or more commands inside
      a container, the only Dockerfile instructions we need to consider are
      “FROM” and “RUN”. E.g. for the command line

         $ ch-image modify -c 'echo foo' -c 'echo bar' -- foo foo2

      this function produces the following parse tree

         start
            dockerfile
               from_
                  image_ref
                     IMAGE_REF foo
               run
                  run_shell
                     LINE_CHUNK echo foo
               run
                  run_shell
                     LINE_CHUNK echo bar
      """
   # Children of dockerfile tree
   df_children = []
   # Metadata attribute. We use this attribute in the “_pretty” method for our
   # “Tree” class. Constructing a tree without specifying a “Meta” instance that
   # has been given a “line” value will result in the attribute not being present,
   # which causes an error when we try to access that attribute. Here we give the
   # attribute a debug value of -1 to avoid said errors.
   meta = lark.tree.Meta()
   meta.line = -1
   df_children.append(im.Tree(lark.Token('RULE', 'from_'),
                      [im.Tree(lark.Token('RULE', 'image_ref'),
                        [lark.Token('IMAGE_REF', str(src_img))],
                        meta)
                      ], meta))
   if (cli.shell is not None):
      df_children.append(im.Tree(lark.Token('RULE', 'shell'),
                         [lark.Token('STRING_QUOTED', '"%s"' % cli.shell),
                          lark.Token('STRING_QUOTED', '"-c"')
                         ],meta))
   for cmd in cmds:
      df_children.append(im.Tree(lark.Token('RULE', 'run'),
                         [im.Tree(lark.Token('RULE', 'run_shell'),
                           [lark.Token('LINE_CHUNK', cmd)],
                           meta)
                         ], meta))
   return im.Tree(lark.Token('RULE', 'start'), [im.Tree(lark.Token('RULE','dockerfile'), df_children)], meta)

def modify_tree_make_script(src_img, path):
   """Temporary(?) analog of “modify_tree_make” for the non-interactive version
      of “modify” using a script. For the command line:

         $ ch-image modify foo foo2 /path/to/script

      this function produces the following parse tree

         start
            dockerfile
               from_
                  image_ref
                     IMAGE_REF foo
               copy
                  copy_shell
                     WORD /path/to/script WORD /ch/script.sh
               run
                  run_shell
                     LINE_CHUNK /ch/script.sh
      """
   # Children of dockerfile tree
   df_children = []
   # Metadata attribute. We use this attribute in the “_pretty” method for our
   # “Tree” class. Constructing a tree without specifying a “Meta” instance that
   # has been given a “line” value will result in the attribute not being present,
   # which causes an error when we try to access that attribute. Here we give the
   # attribute a debug value of -1 to avoid said errors.
   meta = lark.tree.Meta()
   meta.line = -1
   df_children.append(im.Tree(lark.Token('RULE', 'from_'),
                      [im.Tree(lark.Token('RULE', 'image_ref'),
                        [lark.Token('IMAGE_REF', str(src_img))],
                        meta)
                      ], meta))
   df_children.append(im.Tree(lark.Token('RULE', 'copy'),
                      [im.Tree(lark.Token('RULE', 'copy_shell'),
                        [lark.Token('WORD', path),
                         lark.Token('WORD', '/ch/script.sh')
                        ], meta)
                      ],meta))
   # FIXME: Add error handling if “cli.shell” doesn’t exist (issue #1913).
   df_children.append(im.Tree(lark.Token('RULE', 'run'),
                      [im.Tree(lark.Token('RULE', 'run_shell'),
                        [lark.Token('LINE_CHUNK', '%s /ch/script.sh' % cli.shell)],
                        meta)
                      ], meta))
   return im.Tree(lark.Token('RULE', 'start'), [im.Tree(lark.Token('RULE','dockerfile'), df_children)], meta)
