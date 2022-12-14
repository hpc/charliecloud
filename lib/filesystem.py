STORAGE_VERSION = 5
      """Return the number of disk bytes consumed by path. Note this is
         probably different from the file size."""
      # Zero out GZIP header timestamp, bytes 4–7 zero-indexed inclusive [1],
      # to ensure layer hash is consistent. See issue #1080.
         ch.FATAL("can’t mkdir: %s: %s: %s" % (self.name, x.filename,
                                               x.strerror))
         ch.FATAL("can’t mkdir: %s: %s: %s" % (self.name, x.filename,
                                               x.strerror))
      return ch.ossafe(super().open,
                       "can't open for %s: %s" % (mode, self.name),
                       mode, *args, **kwargs)
      ch.ossafe(super().rename,
                "can’t rename: %s -> %s" % (self.name, name_new),
                name_new)
                     % (self.name, x.filename, x.strerror))
            ch.FATAL("can’t symlink: source exists and isn't a symlink: %s"
                     % self.name)
                     % (self.name, target, self.readlink()))
         ch.FATAL("can’t symlink: %s -> %s: %s" % (self.name, target,
                                                   x.strerror))

      elif (v_found in {None, 1, 2, 3, 4}):  # initialize/upgrade
         ch.INFO("%s storage directory: v%d %s"
                 % (op, STORAGE_VERSION, self.root))
         ch.FATAL("incompatible storage directory v%d: %s"
                  % (v_found, self.root),
                  'you can delete and re-initialize with "ch-image reset"')
         ch.WARNING("storage dir: invalid at old default, ignoring: %s"
                    % old.root)
                     "concurrent instances of ch-image cannot share the same storage directory")
                     % (msg_prefix, img), ch.BUG_REPORT_PLZ)
          # WARNING: version_file might not be Path
         text = self.version_file.file_read_all()

                     % (stat.S_IFMT(st.st_mode), targetpath))